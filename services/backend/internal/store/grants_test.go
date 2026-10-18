//go:build integration

// Package store_test asserts the ownership rule: every service role can write the tables of
// its own schema and nothing else, except the column-level grants listed in extraWrites.
// It runs against a migrated database with role logins enabled (`just up`, or CI).
//
// Each statement touches no rows (WHERE false, or fails a NOT NULL check), so the test reads
// only the privilege check: SQLSTATE 42501 means denied, anything else means allowed.
package store_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

var owners = map[string]string{
	"auth":      "auth_svc",
	"platform":  "platform_svc",
	"docbridge": "docbridge_svc",
}

var roles = []string{"auth_svc", "platform_svc", "docbridge_svc", "worker_svc"}

// Writes allowed outside the owner's schema: "role op schema.table".
var extraWrites = map[string]bool{
	"worker_svc UPDATE docbridge.tasks":       true, // status column, see probeColumn
	"worker_svc INSERT docbridge.task_events": true,
}

// The column used in UPDATE probes; for tasks it is one of the worker's columns.
var probeColumn = map[string]string{"docbridge.tasks": "status"}

func dsn(user, password string) string {
	host := os.Getenv("TEST_DB_HOST")
	if host == "" {
		host = "localhost:5440"
	}
	return fmt.Sprintf("postgres://%s:%s@%s/docbridge?sslmode=disable", user, password, host)
}

func rolePassword(role string) string {
	if p := os.Getenv(role + "_PASSWORD"); p != "" {
		return p
	}
	return role + "_local"
}

type table struct{ schema, name, firstColumn string }

func (t table) String() string { return t.schema + "." + t.name }

func tables(t *testing.T, ctx context.Context) []table {
	conn, err := pgx.Connect(ctx, dsn("migrator", envOr("MIGRATOR_PASSWORD", "migrator")))
	if err != nil {
		t.Fatalf("connect as migrator: %v", err)
	}
	defer conn.Close(ctx)

	rows, err := conn.Query(ctx, `
		SELECT c.table_schema, c.table_name, c.column_name
		FROM information_schema.columns c
		JOIN information_schema.tables t USING (table_schema, table_name)
		WHERE t.table_type = 'BASE TABLE' AND c.ordinal_position = 1
		  AND c.table_schema NOT IN ('pg_catalog', 'information_schema')
		ORDER BY 1, 2`)
	if err != nil {
		t.Fatal(err)
	}
	var out []table
	for rows.Next() {
		var tb table
		if err := rows.Scan(&tb.schema, &tb.name, &tb.firstColumn); err != nil {
			t.Fatal(err)
		}
		if tb.schema == "public" && tb.name == "schema_migrations" {
			continue
		}
		out = append(out, tb)
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
	return out
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// allowed runs stmt in a rolled-back transaction and reports whether the privilege check passed.
func allowed(ctx context.Context, conn *pgx.Conn, stmt string) (bool, error) {
	tx, err := conn.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, stmt)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "42501" {
		return false, nil
	}
	if err != nil && !errors.As(err, &pgErr) {
		return false, err // not a database error: connection trouble, fail loudly
	}
	return true, nil
}

func TestEveryTableHasAnOwner(t *testing.T) {
	for _, tb := range tables(t, context.Background()) {
		if _, ok := owners[tb.schema]; !ok {
			t.Errorf("%s is in schema %q, which has no owning role; add it to owners", tb, tb.schema)
		}
	}
}

func TestOwnershipGrants(t *testing.T) {
	ctx := context.Background()
	all := tables(t, ctx)
	if len(all) == 0 {
		t.Fatal("no tables found; run the migrations first")
	}

	for _, role := range roles {
		t.Run(role, func(t *testing.T) {
			conn, err := pgx.Connect(ctx, dsn(role, rolePassword(role)))
			if err != nil {
				t.Fatalf("connect: %v", err)
			}
			defer conn.Close(ctx)

			for _, tb := range all {
				col := probeColumn[tb.String()]
				if col == "" {
					col = tb.firstColumn
				}
				probes := map[string]string{
					"INSERT": fmt.Sprintf("INSERT INTO %s DEFAULT VALUES", tb),
					"UPDATE": fmt.Sprintf("UPDATE %s SET %s = %s WHERE false", tb, col, col),
					"DELETE": fmt.Sprintf("DELETE FROM %s WHERE false", tb),
				}
				for op, stmt := range probes {
					want := owners[tb.schema] == role || extraWrites[role+" "+op+" "+tb.String()]
					got, err := allowed(ctx, conn, stmt)
					if err != nil {
						t.Fatalf("%s: %v", stmt, err)
					}
					if got != want {
						t.Errorf("%s %s on %s: allowed = %v, want %v", role, op, tb, got, want)
					}
				}
			}
		})
	}
}

// The worker's UPDATE grant is column-level: it must not be able to move a task to another file.
func TestWorkerCannotUpdateTaskIdentity(t *testing.T) {
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, dsn("worker_svc", rolePassword("worker_svc")))
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	defer conn.Close(ctx)
	for _, col := range []string{"file_id", "region", "binder_id", "folder_id"} {
		got, err := allowed(ctx, conn, fmt.Sprintf("UPDATE docbridge.tasks SET %s = %s WHERE false", col, col))
		if err != nil {
			t.Fatal(err)
		}
		if got {
			t.Errorf("worker_svc may update tasks.%s", col)
		}
	}
}

-- Local and dev seed data: two teams, nested folders in both regions, and mixed grants
-- (team and user grants, binder and folder grants, a folder-level override to 'none').
-- Every user's password is "password". Idempotent: safe to run more than once.

BEGIN;

INSERT INTO auth.users (id, email, display_name, password_hash) VALUES
  ('00000000-0000-4000-8000-000000000001', 'alice@example.com', 'Alice (legal admin)',   crypt('password', gen_salt('bf'))),
  ('00000000-0000-4000-8000-000000000002', 'bob@example.com',   'Bob (legal member)',    crypt('password', gen_salt('bf'))),
  ('00000000-0000-4000-8000-000000000003', 'carol@example.com', 'Carol (finance)',       crypt('password', gen_salt('bf'))),
  ('00000000-0000-4000-8000-000000000004', 'dave@example.com',  'Dave (no team)',        crypt('password', gen_salt('bf')))
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.teams (id, name) VALUES
  ('00000000-0000-4000-8000-0000000000a1', 'Legal'),
  ('00000000-0000-4000-8000-0000000000a2', 'Finance')
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.team_members (team_id, user_id, role) VALUES
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000001', 'admin'),
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-000000000002', 'member'),
  ('00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000003', 'member')
ON CONFLICT DO NOTHING;

-- Local client secret for the worker: "local-worker-secret".
INSERT INTO auth.service_clients (client_id, secret_hash, scopes) VALUES
  ('task-worker', crypt('local-worker-secret', gen_salt('bf')), '{documents:ingest}')
ON CONFLICT (client_id) DO NOTHING;

INSERT INTO platform.binders (id, name, region) VALUES
  ('10000000-0000-4000-8000-000000000001', 'Contracts EU', 'eu'),
  ('10000000-0000-4000-8000-000000000002', 'Invoices EU',  'eu'),
  ('10000000-0000-4000-8000-000000000003', 'Contracts US', 'us')
ON CONFLICT (id) DO NOTHING;

-- Contracts EU: 2024/{Q1,Q2/{Drafts,Signed}}, Archive
INSERT INTO platform.folders (id, binder_id, parent_id, name) VALUES
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', NULL, '2024'),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Q1'),
  ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', 'Q2'),
  ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000003', 'Drafts'),
  ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000003', 'Signed'),
  ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', NULL, 'Archive'),
  ('20000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000002', NULL, 'Suppliers'),
  ('20000000-0000-4000-8000-000000000012', '10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000011', 'ACME'),
  ('20000000-0000-4000-8000-000000000021', '10000000-0000-4000-8000-000000000003', NULL, 'Clients'),
  ('20000000-0000-4000-8000-000000000022', '10000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000021', 'Initech')
ON CONFLICT (id) DO NOTHING;

INSERT INTO platform.access_grants (binder_id, folder_id, principal_type, principal_id, level) VALUES
  -- Legal writes everywhere in Contracts EU, except Archive, which it can only read.
  ('10000000-0000-4000-8000-000000000001', NULL, 'team', '00000000-0000-4000-8000-0000000000a1', 'write'),
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000006', 'team', '00000000-0000-4000-8000-0000000000a1', 'read'),
  -- Bob is hidden from Signed although his team can write there.
  ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000005', 'user', '00000000-0000-4000-8000-000000000002', 'none'),
  -- Finance writes Invoices EU and reads Contracts US.
  ('10000000-0000-4000-8000-000000000002', NULL, 'team', '00000000-0000-4000-8000-0000000000a2', 'write'),
  ('10000000-0000-4000-8000-000000000003', NULL, 'team', '00000000-0000-4000-8000-0000000000a2', 'read'),
  -- Alice writes one US folder directly.
  ('10000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000022', 'user', '00000000-0000-4000-8000-000000000001', 'write'),
  -- Dave can read a single EU folder and nothing else.
  ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000012', 'user', '00000000-0000-4000-8000-000000000004', 'read')
ON CONFLICT DO NOTHING;

COMMIT;

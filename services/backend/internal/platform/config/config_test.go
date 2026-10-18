package config

import "testing"

func TestRequiredCollectsAllMissing(t *testing.T) {
	t.Setenv("PRESENT", "x")
	var e Env
	_ = e.Required("PRESENT")
	_ = e.Required("MISSING_A")
	_ = e.Required("MISSING_B")
	if err := e.Err(); err == nil || err.Error() != "missing required environment variables: [MISSING_A MISSING_B]" {
		t.Fatalf("err = %v", err)
	}
}

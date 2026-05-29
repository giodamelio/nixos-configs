package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestVerifyTypeValid(t *testing.T) {
	for _, ty := range []VerifyType{VerifyHMAC, VerifyHeaderSecret} {
		if !ty.valid() {
			t.Errorf("%q should be valid", ty)
		}
	}
	for _, ty := range []VerifyType{"", "sha1", "equality", "HMAC", "header_secret"} {
		if VerifyType(ty).valid() {
			t.Errorf("%q should be invalid", ty)
		}
	}
}

func writeConfig(t *testing.T, content string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(p, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadConfig_Valid(t *testing.T) {
	cfg, err := LoadConfig(writeConfig(t, `
[[hook]]
id = "h1"
  [[hook.verify]]
  type = "hmac"
  header = "X-Hub-Signature-256"
  secret_file = "/tmp/secret"
  [hook.actions.forward]
  url = "http://localhost:9000"
`))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(cfg.Hook) != 1 || len(cfg.Hook[0].Verify) != 1 {
		t.Fatalf("unexpected parse: %+v", cfg)
	}
	if got := cfg.Hook[0].Verify[0].Type; got != VerifyHMAC {
		t.Errorf("type = %q, want %q", got, VerifyHMAC)
	}
}

func TestLoadConfig_Invalid(t *testing.T) {
	cases := map[string]string{
		"missing id": `
[[hook]]
  [hook.actions.print]
`,
		"no action": `
[[hook]]
id = "h1"
`,
		"forward without url": `
[[hook]]
id = "h1"
  [hook.actions.forward]
`,
		"invalid verify type": `
[[hook]]
id = "h1"
  [[hook.verify]]
  type = "sha1"
  header = "X-Sig"
  secret_file = "/tmp/s"
  [hook.actions.print]
`,
		"verify missing header": `
[[hook]]
id = "h1"
  [[hook.verify]]
  type = "hmac"
  secret_file = "/tmp/s"
  [hook.actions.print]
`,
		"verify missing secret_file": `
[[hook]]
id = "h1"
  [[hook.verify]]
  type = "header-secret"
  header = "X-Sig"
  [hook.actions.print]
`,
	}
	for name, content := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadConfig(writeConfig(t, content)); err == nil {
				t.Error("expected validation error, got nil")
			}
		})
	}
}

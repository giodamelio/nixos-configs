package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeConfig(t *testing.T, body string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("writing config: %v", err)
	}
	return path
}

func TestLoadConfigValid(t *testing.T) {
	path := writeConfig(t, `
[gradient]
server = "https://gradient.example.com"
api_key_file = "/run/secrets/api_key"

[restate]
service_name = "gradient-deployer-carbon"

[slots.yesman]
project = "default/yesman"
profile = "/nix/var/nix/profiles/per-user/deploy/yesman/profile"
restart_unit = "yesman.service"
`)

	cfg, err := LoadConfig(path)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.Gradient.Server != "https://gradient.example.com" {
		t.Errorf("server = %q", cfg.Gradient.Server)
	}
	if cfg.Restate.ServiceName != "gradient-deployer-carbon" {
		t.Errorf("service_name = %q", cfg.Restate.ServiceName)
	}
	slot, ok := cfg.Slots["yesman"]
	if !ok {
		t.Fatal("missing yesman slot")
	}
	if slot.Project != "default/yesman" || slot.RestartUnit != "yesman.service" {
		t.Errorf("slot parsed wrong: %+v", slot)
	}
}

func TestLoadConfigMissingRequired(t *testing.T) {
	cases := map[string]string{
		"no server": `
[gradient]
api_key_file = "/x"
[restate]
service_name = "n"
`,
		"no api key": `
[gradient]
server = "https://g"
[restate]
service_name = "n"
`,
		"no service name": `
[gradient]
server = "https://g"
api_key_file = "/x"
`,
		"slot without project": `
[gradient]
server = "https://g"
api_key_file = "/x"
[restate]
service_name = "n"
[slots.app]
profile = "/p"
restart_unit = "app.service"
`,
	}

	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadConfig(writeConfig(t, body)); err == nil {
				t.Errorf("expected error for %q, got nil", name)
			}
		})
	}
}

func TestResolveAPIKey(t *testing.T) {
	dir := t.TempDir()
	apiKeyPath := filepath.Join(dir, "api_key")
	// Trailing newline must be trimmed.
	if err := os.WriteFile(apiKeyPath, []byte("grd_abc\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg := &Config{Gradient: GradientConfig{APIKeyFile: apiKeyPath}}
	key, err := ResolveAPIKey(cfg)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if key != "grd_abc" {
		t.Errorf("api key = %q", key)
	}
}

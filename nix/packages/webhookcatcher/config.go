package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/BurntSushi/toml"
)

type Config struct {
	Hook []HookConfig `toml:"hook"`
}

type HookConfig struct {
	ID      string         `toml:"id"`
	Verify  []VerifyConfig `toml:"verify"`
	Actions ActionsConfig  `toml:"actions"`
}

// VerifyType enumerates the supported request verification schemes.
type VerifyType string

const (
	// VerifyHMAC checks an HMAC-SHA256 signature of the raw request body,
	// keyed by the secret, against a header value. The header is expected to
	// be `sha256=<hex>` (GitHub's X-Hub-Signature-256 scheme).
	VerifyHMAC VerifyType = "hmac"
	// VerifyHeaderSecret checks a header value for exact equality with the
	// secret. Used by forges that send a static shared token (e.g. GitLab's
	// X-Gitlab-Token).
	VerifyHeaderSecret VerifyType = "header-secret"
	// VerifyBearer checks an `Authorization: Bearer <secret>` header: the
	// "Bearer " prefix is stripped and the remainder compared to the secret.
	// Used by senders that emit a bearer token (e.g. Gradient's send_web_request).
	VerifyBearer VerifyType = "bearer"
)

// validVerifyTypes is the set of accepted VerifyType values, used both for
// validation and to render the allowed list in error messages.
var validVerifyTypes = []VerifyType{VerifyHMAC, VerifyHeaderSecret, VerifyBearer}

func (t VerifyType) valid() bool {
	for _, v := range validVerifyTypes {
		if t == v {
			return true
		}
	}
	return false
}

type VerifyConfig struct {
	Type       VerifyType `toml:"type"`
	Header     string     `toml:"header"`
	SecretFile string     `toml:"secret_file"`
}

type ActionsConfig struct {
	Forward *ForwardAction `toml:"forward"`
	Print   *PrintAction   `toml:"print"`
}

type ForwardAction struct {
	URL string `toml:"url"`
}

type PrintAction struct{}

func LoadConfig(path string) (*Config, error) {
	var cfg Config
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return nil, fmt.Errorf("parsing config: %w", err)
	}

	for i, hook := range cfg.Hook {
		if hook.ID == "" {
			return nil, fmt.Errorf("hook[%d]: id is required", i)
		}
		if hook.Actions.Forward == nil && hook.Actions.Print == nil {
			return nil, fmt.Errorf("hook[%d] (%s): at least one action is required", i, hook.ID)
		}
		if hook.Actions.Forward != nil && hook.Actions.Forward.URL == "" {
			return nil, fmt.Errorf("hook[%d] (%s): forward.url is required", i, hook.ID)
		}
		for j, v := range hook.Verify {
			if !v.Type.valid() {
				return nil, fmt.Errorf("hook[%d] (%s): verify[%d]: invalid type %q (must be one of %v)", i, hook.ID, j, v.Type, validVerifyTypes)
			}
			if v.Header == "" || v.SecretFile == "" {
				return nil, fmt.Errorf("hook[%d] (%s): verify[%d]: header and secret_file are required", i, hook.ID, j)
			}
		}
	}

	return &cfg, nil
}

type ResolvedVerifier struct {
	Config VerifyConfig
	Secret string
}

type ResolvedHook struct {
	Config    HookConfig
	Verifiers []ResolvedVerifier
}

func ResolveHooks(cfg *Config) (map[string]*ResolvedHook, error) {
	hooks := make(map[string]*ResolvedHook, len(cfg.Hook))

	for _, hook := range cfg.Hook {
		resolved := &ResolvedHook{Config: hook}

		for _, v := range hook.Verify {
			data, err := os.ReadFile(v.SecretFile)
			if err != nil {
				return nil, fmt.Errorf("hook %s: reading secret file %s: %w", hook.ID, v.SecretFile, err)
			}
			resolved.Verifiers = append(resolved.Verifiers, ResolvedVerifier{
				Config: v,
				Secret: strings.TrimSpace(string(data)),
			})
		}

		hooks[hook.ID] = resolved
	}

	return hooks, nil
}

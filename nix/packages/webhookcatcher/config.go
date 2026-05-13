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
	ID      string        `toml:"id"`
	Auth    *AuthConfig   `toml:"auth"`
	Actions ActionsConfig `toml:"actions"`
}

type AuthConfig struct {
	Header     string `toml:"header"`
	SecretFile string `toml:"secret_file"`
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
		if hook.Auth != nil {
			if hook.Auth.Header == "" || hook.Auth.SecretFile == "" {
				return nil, fmt.Errorf("hook[%d] (%s): auth requires both header and secret_file", i, hook.ID)
			}
		}
	}

	return &cfg, nil
}

type ResolvedHook struct {
	Config HookConfig
	Secret string
}

func ResolveHooks(cfg *Config) (map[string]*ResolvedHook, error) {
	hooks := make(map[string]*ResolvedHook, len(cfg.Hook))

	for _, hook := range cfg.Hook {
		resolved := &ResolvedHook{Config: hook}

		if hook.Auth != nil {
			data, err := os.ReadFile(hook.Auth.SecretFile)
			if err != nil {
				return nil, fmt.Errorf("hook %s: reading secret file: %w", hook.ID, err)
			}
			resolved.Secret = strings.TrimSpace(string(data))
		}

		hooks[hook.ID] = resolved
	}

	return hooks, nil
}

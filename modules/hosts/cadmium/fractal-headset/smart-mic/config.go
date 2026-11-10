package main

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
	"github.com/fsnotify/fsnotify"
)

type notifyConfig struct {
	All  *bool `toml:"all"`
	Boom *bool `toml:"boom"`
	Mute *bool `toml:"mute"`
}

// enabled resolves whether a named event notifies: a set `all` overrides every
// event in either direction; otherwise the per-event setting wins; an unset
// event is off.
func (n notifyConfig) enabled(event string) bool {
	if n.All != nil {
		return *n.All
	}
	var p *bool
	switch event {
	case "boom":
		p = n.Boom
	case "mute":
		p = n.Mute
	}
	if p != nil {
		return *p
	}
	return false
}

type config struct {
	DesktopNotifications notifyConfig `toml:"desktop_notifications"`
}

const defaultConfig = `# smart-mic configuration.
# Desktop notifications fire on headset state transitions (never on startup).

[desktop_notifications]
# ` + "`all`" + ` overrides every event below when set: true = all on, false = all off.
# Leave it commented out to use the per-event settings.
# all = false

# Events the headset currently emits. Default: off.
boom = false
mute = false
`

// writeDefaultConfig creates path with every setting at its default. O_EXCL so
// a file that appeared in the meantime is never clobbered.
func writeDefaultConfig(path string) error {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.WriteString(defaultConfig); err != nil {
		return err
	}
	return nil
}

func configPath() (string, error) {
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "smart-mic", "config.toml"), nil
}

// loadConfig parses the TOML config. A missing file is a zero config (all
// notifications off) and found=false; a malformed file is an error so the
// caller can keep the previous config.
func loadConfig(path string) (cfg config, found bool, err error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return config{}, false, nil
	}
	if err != nil {
		return config{}, false, fmt.Errorf("read config: %w", err)
	}
	if err := toml.Unmarshal(data, &cfg); err != nil {
		return config{}, false, fmt.Errorf("parse config %s: %w", path, err)
	}
	return cfg, true, nil
}

// watchConfig reloads path on change and sends each new config on out. It
// watches the parent directory, not the file, so a save that replaces the file
// (write-temp-then-rename, as most editors do) is still seen. A reload that
// fails to parse keeps the previous config.
func watchConfig(path string, out chan<- config) error {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	dir := filepath.Dir(path)
	if err := w.Add(dir); err != nil {
		_ = w.Close()
		return fmt.Errorf("watch %s: %w", dir, err)
	}
	go func() {
		defer w.Close()
		for {
			select {
			case ev, ok := <-w.Events:
				if !ok {
					return
				}
				if filepath.Clean(ev.Name) != path {
					continue
				}
				if ev.Op&(fsnotify.Write|fsnotify.Create|fsnotify.Rename|fsnotify.Remove) == 0 {
					continue
				}
				cfg, found, err := loadConfig(path)
				if err != nil {
					slog.Warn("keeping previous config", "err", err)
					continue
				}
				slog.Info("config reloaded", "path", path, "exists", found)
				out <- cfg
			case err, ok := <-w.Errors:
				if !ok {
					return
				}
				slog.Error("config watcher", "err", err)
			}
		}
	}()
	return nil
}

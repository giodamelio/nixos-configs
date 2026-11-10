package main

import (
	"fmt"
	"log/slog"

	"github.com/godbus/dbus/v5"
)

// notifier posts desktop notifications over the session bus. A nil notifier
// (no session bus) is a no-op, so notifications stay non-fatal.
type notifier struct {
	obj dbus.BusObject
}

func newNotifier() (*notifier, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, fmt.Errorf("session bus: %w", err)
	}
	obj := conn.Object("org.freedesktop.Notifications", "/org/freedesktop/Notifications")
	return &notifier{obj: obj}, nil
}

func (n *notifier) notify(summary string) {
	if n == nil {
		return
	}
	call := n.obj.Call("org.freedesktop.Notifications.Notify", 0,
		"Smart Mic", uint32(0), "", summary, "",
		[]string{}, map[string]dbus.Variant{}, int32(-1))
	if call.Err != nil {
		slog.Warn("desktop notification failed", "err", call.Err)
	}
}

func boomMessage(up bool) string {
	if up {
		return "Boom up"
	}
	return "Boom down"
}

func muteMessage(muted bool) string {
	if muted {
		return "Mic muted"
	}
	return "Mic unmuted"
}

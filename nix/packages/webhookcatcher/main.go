package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintf(os.Stderr, "usage: webhookcatcher <config-path>\n")
		os.Exit(1)
	}

	cfg, err := LoadConfig(os.Args[1])
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	hooks, err := ResolveHooks(cfg)
	if err != nil {
		log.Fatalf("resolve error: %v", err)
	}

	handler := NewWebhookHandler(hooks)

	ln, err := socketFromSystemd()
	if err != nil {
		log.Fatalf("listen error: %v", err)
	}

	log.Printf("listening with %d hook(s)", len(hooks))
	if err := http.Serve(ln, handler); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func socketFromSystemd() (net.Listener, error) {
	nfds, _ := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	if nfds == 0 {
		return nil, fmt.Errorf("LISTEN_FDS not set; webhookcatcher requires systemd socket activation")
	}

	// File descriptor 3 is the first socket passed by systemd
	f := os.NewFile(3, "systemd-socket")
	ln, err := net.FileListener(f)
	f.Close()
	if err != nil {
		return nil, fmt.Errorf("accepting systemd socket: %w", err)
	}
	return ln, nil
}

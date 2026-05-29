package main

import (
	"context"
	"log/slog"
	"os"

	restate "github.com/restatedev/sdk-go"
	"github.com/restatedev/sdk-go/server"
)

// bindAddr is where the Restate service listens for invocations from the
// Restate server. Kept in sync with the NixOS module's registration endpoint.
const bindAddr = ":9080"

func main() {
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	slog.SetDefault(log)

	if len(os.Args) != 2 {
		log.Error("usage: gradient-deployer <config-path>")
		os.Exit(1)
	}

	cfg, err := LoadConfig(os.Args[1])
	if err != nil {
		log.Error("config error", "error", err)
		os.Exit(1)
	}
	apiKey, err := ResolveAPIKey(cfg)
	if err != nil {
		log.Error("secret error", "error", err)
		os.Exit(1)
	}

	slotNames := make([]string, 0, len(cfg.Slots))
	for name := range cfg.Slots {
		slotNames = append(slotNames, name)
	}
	log.Info("starting gradient-deployer",
		"config", os.Args[1],
		"service", cfg.Restate.ServiceName,
		"server", cfg.Gradient.Server,
		"slots", slotNames,
	)

	deployer := NewDeployer(cfg.Restate.ServiceName, NewGradientClient(cfg.Gradient.Server, apiKey), cfg.Slots)

	if err := server.NewRestate().
		Bind(restate.Reflect(deployer)).
		Start(context.Background(), bindAddr); err != nil {
		log.Error("restate server exited", "error", err)
		os.Exit(1)
	}
}

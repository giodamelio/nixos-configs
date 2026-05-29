package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os/exec"
	"path/filepath"
	"strings"

	restate "github.com/restatedev/sdk-go"
)

// Deployer is a Restate Virtual Object keyed by slot name. Restate provides:
//   - single-writer-per-slot (no two reconciles of the same slot overlap), so
//     we need no mutex;
//   - durable, automatically-retried execution of each step below, so we need
//     no hand-rolled retry/backoff and a crashed reconcile resumes mid-way.
type Deployer struct {
	name  string
	api   GradientAPI
	slots map[string]SlotConfig
}

func NewDeployer(name string, api GradientAPI, slots map[string]SlotConfig) *Deployer {
	return &Deployer{name: name, api: api, slots: slots}
}

// ServiceName is read by restate.Reflect to name the Virtual Object.
func (d *Deployer) ServiceName() string { return d.name }

// ReconcileResult is returned to the caller (e.g. the manual deploy wrapper).
type ReconcileResult struct {
	Slot     string `json:"slot"`
	Deployed bool   `json:"deployed"`
	Target   string `json:"target,omitempty"`
}

// Reconcile converges the slot (= object key) to the latest succeeded Gradient
// build. Every external effect is a durable step (restate.Run/RunVoid): Restate
// journals each one's outcome and, on failure, retries the handler from the
// last completed step.
//
// The input is the Gradient webhook payload (a json.RawMessage). We read its
// evaluation_id and deploy that exact evaluation; an empty/absent one — the
// manual gradient-deploy wrapper sends {}, the synthetic test-fire carries no
// evaluation_id — falls back to the project's latest evaluation. It's a
// json.RawMessage rather than restate.Void because every caller POSTs a JSON
// body, and a Void handler makes Restate's ingress reject any non-empty body
// ("Expected body and content-type to be empty"). The slot comes from the
// object key.
func (d *Deployer) Reconcile(ctx restate.ObjectContext, input json.RawMessage) (ReconcileResult, error) {
	slot := restate.Key(ctx)
	cfg, ok := d.slots[slot]
	if !ok {
		// Unrecoverable: retrying won't make an unknown slot exist.
		return ReconcileResult{}, restate.TerminalError(fmt.Errorf("unknown slot %q", slot))
	}
	result := ReconcileResult{Slot: slot}

	// The webhook body names the evaluation that just completed; deploy that one.
	evaluationID := parseEvaluationID(input, ctx.Log())

	// 1. Resolve the deploy target from Gradient (idempotent read).
	target, err := restate.Run(ctx, func(rc restate.RunContext) (string, error) {
		return resolveTarget(rc, d.api, cfg, evaluationID, rc.Log())
	}, restate.WithName("resolve target build"))
	if err != nil {
		return result, err
	}
	if target == "" {
		ctx.Log().Warn("no deployable build; skipping", "slot", slot)
		return result, nil
	}
	result.Target = target

	// 2. Compare against the profile's current target. Journaled so replays are
	//    deterministic; re-running steps 3-5 is idempotent anyway.
	current, err := restate.Run(ctx, func(rc restate.RunContext) (string, error) {
		return resolveProfile(cfg.Profile), nil
	}, restate.WithName("read current profile"))
	if err != nil {
		return result, err
	}
	if current == target {
		ctx.Log().Info("up-to-date; nothing to do", "slot", slot, "target", target)
		return result, nil
	}

	ctx.Log().Info("deploying", "slot", slot, "target", target, "current", current)

	// 3. Realize the closure (Restate retries on transient cache-availability failures).
	if err := restate.RunVoid(ctx, func(rc restate.RunContext) error {
		return run(rc, "nix-store", "--realise", target)
	}, restate.WithName("realize closure")); err != nil {
		return result, fmt.Errorf("realize %s: %w", target, err)
	}

	// 4. Point the profile at the new build.
	if err := restate.RunVoid(ctx, func(rc restate.RunContext) error {
		return run(rc, "nix-env", "--profile", cfg.Profile, "--set", target)
	}, restate.WithName("set profile")); err != nil {
		return result, fmt.Errorf("set profile %s: %w", cfg.Profile, err)
	}

	// 5. Restart the unit.
	if err := restate.RunVoid(ctx, func(rc restate.RunContext) error {
		return run(rc, "systemctl", "--no-block", "restart", cfg.RestartUnit)
	}, restate.WithName("restart unit")); err != nil {
		return result, fmt.Errorf("restart %s: %w", cfg.RestartUnit, err)
	}

	ctx.Log().Info("deployed", "slot", slot, "target", target, "unit", cfg.RestartUnit)
	result.Deployed = true
	return result, nil
}

// parseEvaluationID pulls the optional Gradient evaluation_id out of the webhook
// body. Empty result means "use the project's latest evaluation": the manual
// deploy wrapper POSTs {}, the synthetic test-fire payload has no evaluation_id,
// and an unparseable body shouldn't be fatal — a reconcile against latest is a
// safe fallback.
func parseEvaluationID(body json.RawMessage, log *slog.Logger) string {
	if len(body) == 0 {
		return ""
	}
	var p struct {
		EvaluationID string `json:"evaluation_id"`
	}
	if err := json.Unmarshal(body, &p); err != nil {
		log.Warn("could not parse webhook body; using latest evaluation", "err", err)
		return ""
	}
	return p.EvaluationID
}

// resolveTarget asks Gradient for the entry-point builds of the given evaluation
// (or the latest when evaluationID is empty) and returns the first deployable
// one's output path. Returns "" (not an error) when there is nothing deployable
// yet, so a still-building or empty project is a skip, not a failure.
func resolveTarget(ctx context.Context, api GradientAPI, cfg SlotConfig, evaluationID string, log *slog.Logger) (string, error) {
	buildIDs, err := api.EntryPoints(ctx, cfg.Project, evaluationID)
	if err != nil {
		return "", fmt.Errorf("entry points: %w", err)
	}
	if len(buildIDs) == 0 {
		return "", nil
	}

	for _, id := range buildIDs {
		b, err := api.Build(ctx, id)
		if err != nil {
			return "", fmt.Errorf("build %s: %w", id, err)
		}
		if !buildDeployable(b.Status) {
			log.Warn("entry-point build not deployable; skipping", "build", id, "status", b.Status)
			continue
		}
		if b.Out == "" {
			log.Warn("deployable build has no output path; skipping", "build", id)
			continue
		}
		return b.Out, nil
	}
	return "", nil
}

// buildDeployable reports whether a Gradient BuildStatus is a terminal success.
// "Completed" (the build ran) and "Substituted" (its outputs were already in the
// cache, so no build ran) both mean the output path is realizable; every other
// status is in-progress or a failure.
func buildDeployable(status string) bool {
	return status == "Completed" || status == "Substituted"
}

// resolveProfile fully resolves a profile symlink to its /nix/store target, or
// "" if the profile does not exist yet (nothing deployed).
func resolveProfile(profile string) string {
	resolved, err := filepath.EvalSymlinks(profile)
	if err != nil {
		return ""
	}
	return resolved
}

// run executes a command, folding any output into the returned error for context.
func run(ctx context.Context, name string, args ...string) error {
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w: %s", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

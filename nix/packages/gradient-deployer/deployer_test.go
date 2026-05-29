package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"testing"
)

// fakeAPI is an in-memory GradientAPI for testing resolveTarget's selection logic.
type fakeAPI struct {
	entryPoints map[string][]string
	builds      map[string]*Build
	gotEvalID   string // records the evaluation_id passed to the last EntryPoints call
}

func (f *fakeAPI) Health(context.Context) error { return nil }

func (f *fakeAPI) EntryPoints(_ context.Context, project, evaluationID string) ([]string, error) {
	f.gotEvalID = evaluationID
	ids, ok := f.entryPoints[project]
	if !ok {
		return nil, fmt.Errorf("no project %s", project)
	}
	return ids, nil
}

func (f *fakeAPI) Build(_ context.Context, id string) (*Build, error) {
	b, ok := f.builds[id]
	if !ok {
		return nil, fmt.Errorf("no build %s", id)
	}
	return b, nil
}

func discardLog() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestResolveTargetCompleted(t *testing.T) {
	api := &fakeAPI{
		entryPoints: map[string][]string{"default/yesman": {"b1"}},
		builds: map[string]*Build{
			"b1": {Status: "Completed", Out: "/nix/store/aaa-yesman"},
		},
	}

	got, err := resolveTarget(context.Background(), api, SlotConfig{Project: "default/yesman"}, "", discardLog())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "/nix/store/aaa-yesman" {
		t.Errorf("target = %q", got)
	}
}

func TestResolveTargetSkipsToSubstituted(t *testing.T) {
	// First entry point is still building, second is a cache hit (Substituted) —
	// both Completed and Substituted count as deployable, so pick the second.
	api := &fakeAPI{
		entryPoints: map[string][]string{"default/app": {"bad", "good"}},
		builds: map[string]*Build{
			"bad":  {Status: "Building", Out: ""},
			"good": {Status: "Substituted", Out: "/nix/store/bbb-app"},
		},
	}

	got, err := resolveTarget(context.Background(), api, SlotConfig{Project: "default/app"}, "", discardLog())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "/nix/store/bbb-app" {
		t.Errorf("target = %q", got)
	}
}

func TestResolveTargetNoEntryPoints(t *testing.T) {
	// Project exists but the evaluation has no entry points.
	api := &fakeAPI{entryPoints: map[string][]string{"default/app": {}}}

	got, err := resolveTarget(context.Background(), api, SlotConfig{Project: "default/app"}, "", discardLog())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "" {
		t.Errorf("expected empty target, got %q", got)
	}
}

func TestResolveTargetNoneDeployable(t *testing.T) {
	api := &fakeAPI{
		entryPoints: map[string][]string{"default/app": {"b1"}},
		builds: map[string]*Build{
			"b1": {Status: "FailedPermanent", Out: ""},
		},
	}

	got, err := resolveTarget(context.Background(), api, SlotConfig{Project: "default/app"}, "", discardLog())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "" {
		t.Errorf("expected empty target, got %q", got)
	}
}

func TestResolveTargetAPIError(t *testing.T) {
	api := &fakeAPI{entryPoints: map[string][]string{}}

	if _, err := resolveTarget(context.Background(), api, SlotConfig{Project: "missing"}, "", discardLog()); err == nil {
		t.Error("expected error for missing project, got nil")
	}
}

func TestResolveTargetForwardsEvaluationID(t *testing.T) {
	api := &fakeAPI{
		entryPoints: map[string][]string{"default/yesman": {"b1"}},
		builds:      map[string]*Build{"b1": {Status: "Completed", Out: "/nix/store/aaa"}},
	}

	if _, err := resolveTarget(context.Background(), api, SlotConfig{Project: "default/yesman"}, "eval-123", discardLog()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if api.gotEvalID != "eval-123" {
		t.Errorf("evaluation_id passed to EntryPoints = %q, want %q", api.gotEvalID, "eval-123")
	}
}

func TestParseEvaluationID(t *testing.T) {
	cases := []struct {
		name string
		body string
		want string
	}{
		{"real payload", `{"evaluation_id":"019eaab3","project_id":"x","status":"evaluation.completed"}`, "019eaab3"},
		{"empty body", ``, ""},
		{"empty object", `{}`, ""},
		{"synthetic test-fire", `{"id":"000","event":"evaluation.completed","synthetic":true}`, ""},
		{"unparseable", `not json`, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := parseEvaluationID(json.RawMessage(c.body), discardLog()); got != c.want {
				t.Errorf("parseEvaluationID(%q) = %q, want %q", c.body, got, c.want)
			}
		})
	}
}

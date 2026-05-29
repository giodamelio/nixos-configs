package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// GradientAPI is the slice of the Gradient HTTP API the reconciler needs. It is
// an interface so reconcile logic can be unit-tested against a fake.
type GradientAPI interface {
	Health(ctx context.Context) error
	// EntryPoints returns the root-build IDs of the given evaluation, or of the
	// project's latest evaluation when evaluationID is empty.
	EntryPoints(ctx context.Context, project, evaluationID string) ([]string, error)
	Build(ctx context.Context, id string) (*Build, error)
}

// Build is the subset of GET /builds/<id> we use. A build is deployable when its
// status is a terminal success — "Completed" (a build ran) or "Substituted"
// (outputs were already present from the cache); see the Gradient BuildStatus
// enum. Other states are in-progress or failures.
type Build struct {
	Status string
	Out    string // the "out" output store path (message.output.out)
}

// GradientClient talks to a real Gradient instance. The JSON shapes mirror what
// the upstream gradient-deploy.nix module relies on.
type GradientClient struct {
	server string
	apiKey string
	http   *http.Client
}

func NewGradientClient(server, apiKey string) *GradientClient {
	return &GradientClient{
		server: strings.TrimRight(server, "/"),
		apiKey: apiKey,
		http:   &http.Client{Timeout: 15 * time.Second},
	}
}

// Health hits the unauthenticated health endpoint to give a clear "server
// unreachable" signal before attempting per-slot work.
func (c *GradientClient) Health(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.server+"/api/v1/health", nil)
	if err != nil {
		return err
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("health returned %d", resp.StatusCode)
	}
	return nil
}

// EntryPoints lists the root builds (entry points) of an evaluation and returns
// their build IDs. With evaluationID set it targets that specific evaluation
// (?evaluation_id=); empty falls back to the project's latest evaluation.
// GET /projects/<org>/<project>/entry-points is BaseResponse-wrapped with a
// `message` array of entry-point summaries; we only need each build_id.
//
// Note this is a separate endpoint from /details — the latter carries
// `last_evaluations`, NOT entry points, so reading entry points off it always
// yields nothing.
func (c *GradientClient) EntryPoints(ctx context.Context, project, evaluationID string) ([]string, error) {
	path := "/api/v1/projects/" + project + "/entry-points"
	if evaluationID != "" {
		path += "?evaluation_id=" + url.QueryEscape(evaluationID)
	}

	var r struct {
		Message []struct {
			BuildID string `json:"build_id"`
		} `json:"message"`
	}
	if err := c.get(ctx, path, &r); err != nil {
		return nil, err
	}

	ids := make([]string, 0, len(r.Message))
	for _, ep := range r.Message {
		if ep.BuildID != "" {
			ids = append(ids, ep.BuildID)
		}
	}
	return ids, nil
}

func (c *GradientClient) Build(ctx context.Context, id string) (*Build, error) {
	var r struct {
		Message struct {
			Status string `json:"status"`
			Output struct {
				Out string `json:"out"`
			} `json:"output"`
		} `json:"message"`
	}
	if err := c.get(ctx, "/api/v1/builds/"+id, &r); err != nil {
		return nil, err
	}
	return &Build{Status: r.Message.Status, Out: r.Message.Output.Out}, nil
}

// get performs an authenticated GET and decodes the JSON body into out.
func (c *GradientClient) get(ctx context.Context, path string, out any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.server+path, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %s returned %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("decoding %s response: %w", path, err)
	}
	return nil
}

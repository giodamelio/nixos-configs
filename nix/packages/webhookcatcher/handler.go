package main

import (
	"bytes"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
)

type WebhookHandler struct {
	hooks map[string]*ResolvedHook
}

func NewWebhookHandler(hooks map[string]*ResolvedHook) *WebhookHandler {
	return &WebhookHandler{hooks: hooks}
}

func (h *WebhookHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	id := strings.TrimPrefix(r.URL.Path, "/")

	hook, ok := h.hooks[id]
	if !ok {
		http.NotFound(w, r)
		return
	}

	if hook.Config.Auth != nil {
		headerVal := r.Header.Get(hook.Config.Auth.Header)
		if headerVal != hook.Secret {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read body", http.StatusInternalServerError)
		return
	}

	if hook.Config.Actions.Print != nil {
		executePrint(r, body)
	}

	if hook.Config.Actions.Forward != nil {
		status, respBody, err := executeForward(hook.Config.Actions.Forward.URL, r, body)
		if err != nil {
			log.Printf("hook %s: forward error: %v", hook.Config.ID, err)
			http.Error(w, "forward failed", http.StatusBadGateway)
			return
		}
		w.WriteHeader(status)
		w.Write(respBody)
		return
	}

	w.WriteHeader(http.StatusOK)
}

func executePrint(r *http.Request, body []byte) {
	fmt.Printf("--- Webhook Request ---\n")
	fmt.Printf("%s %s\n", r.Method, r.URL.Path)
	for name, values := range r.Header {
		for _, v := range values {
			fmt.Printf("%s: %s\n", name, v)
		}
	}
	fmt.Printf("\n%s\n", string(body))
	fmt.Printf("--- End ---\n\n")
}

func executeForward(url string, r *http.Request, body []byte) (int, []byte, error) {
	req, err := http.NewRequest(r.Method, url, bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}

	for name, values := range r.Header {
		for _, v := range values {
			req.Header.Add(name, v)
		}
	}

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, nil, err
	}

	return resp.StatusCode, respBody, nil
}

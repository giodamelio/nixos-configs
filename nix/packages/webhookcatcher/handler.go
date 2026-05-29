package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
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

	// Read the body up front: HMAC verification needs it, and the forward
	// action replays it. Both reuse this single copy.
	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "failed to read body", http.StatusInternalServerError)
		return
	}

	// All verifiers must pass (AND).
	for _, v := range hook.Verifiers {
		if !verify(v, r, body) {
			log.Printf("hook %s: verification failed (%s on header %s)", hook.Config.ID, v.Config.Type, v.Config.Header)
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
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

func verify(v ResolvedVerifier, r *http.Request, body []byte) bool {
	headerVal := r.Header.Get(v.Config.Header)
	switch v.Config.Type {
	case VerifyHeaderSecret:
		return subtle.ConstantTimeCompare([]byte(headerVal), []byte(v.Secret)) == 1
	case VerifyBearer:
		const prefix = "Bearer "
		if !strings.HasPrefix(headerVal, prefix) {
			return false
		}
		token := strings.TrimPrefix(headerVal, prefix)
		return subtle.ConstantTimeCompare([]byte(token), []byte(v.Secret)) == 1
	case VerifyHMAC:
		return verifyHMAC(v.Secret, headerVal, body)
	default:
		// Unreachable: LoadConfig rejects unknown verify types.
		return false
	}
}

// verifyHMAC checks an `sha256=<hex>` header against HMAC-SHA256 of the body.
func verifyHMAC(secret, headerVal string, body []byte) bool {
	const prefix = "sha256="
	if !strings.HasPrefix(headerVal, prefix) {
		return false
	}
	got, err := hex.DecodeString(strings.TrimPrefix(headerVal, prefix))
	if err != nil {
		return false
	}
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	return hmac.Equal(got, mac.Sum(nil))
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

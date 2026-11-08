package main

import (
	"bytes"
	"encoding/json"
	"io"
	"mime"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/mail"
	"strings"
	"testing"
)

var testCfg = config{
	domain: "agent-dms.example",
	owner:  "owner@example.org",
	login:  "approvals@agent-dms.example",
}

type sent struct {
	to      string
	message []byte
}

func newTestServer(t *testing.T) (*server, *[]sent) {
	t.Helper()
	var out []sent
	s := &server{
		cfg: testCfg,
		send: func(_ config, to string, message []byte) error {
			out = append(out, sent{to, message})
			return nil
		},
		spawn: func(f func()) { f() },
	}
	return s, &out
}

func hookBody(t *testing.T, to []string, headers [][]string, contents string) io.Reader {
	t.Helper()
	req := map[string]any{
		"context": map[string]any{
			"stage": "data",
			"sasl":  map[string]any{"login": "proj@agent-dms.example"},
			"queue": map[string]any{"id": "4b5a8c489800400"},
		},
		"envelope": map[string]any{
			"from": map[string]any{"address": "proj@agent-dms.example"},
			"to": func() []map[string]any {
				var r []map[string]any
				for _, a := range to {
					r = append(r, map[string]any{"address": a})
				}
				return r
			}(),
		},
		"message": map[string]any{"headers": headers, "contents": contents, "size": len(contents)},
	}
	b, err := json.Marshal(req)
	if err != nil {
		t.Fatal(err)
	}
	return bytes.NewReader(b)
}

var plainHeaders = [][]string{
	{"From", " proj <proj@agent-dms.example>\r\n"},
	{"To", " someone@elsewhere.example\r\n"},
	{"Subject", " Hello <there>\r\n"},
	{"Message-ID", " <abc@agent-dms.example>\r\n"},
}

func post(t *testing.T, s *server, body io.Reader) string {
	t.Helper()
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/", body))
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	return rec.Body.String()
}

func parts(t *testing.T, raw []byte) (subject, text, html string) {
	t.Helper()
	msg, err := mail.ReadMessage(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	subject, err = new(mime.WordDecoder).DecodeHeader(msg.Header.Get("Subject"))
	if err != nil {
		t.Fatal(err)
	}
	_, params, err := mime.ParseMediaType(msg.Header.Get("Content-Type"))
	if err != nil {
		t.Fatal(err)
	}
	mr := multipart.NewReader(msg.Body, params["boundary"])
	for {
		p, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(p)
		if strings.HasPrefix(p.Header.Get("Content-Type"), "text/html") {
			html = string(b)
		} else {
			text = string(b)
		}
	}
	return subject, text, html
}

func TestOutsideRecipientSendsRequest(t *testing.T) {
	s, out := newTestServer(t)
	body := post(t, s, hookBody(t,
		[]string{"someone@elsewhere.example", "other@agent-dms.example", "owner@example.org"},
		plainHeaders, "Please <b>approve</b> me.\r\n"))
	if body != `{"action":"accept"}` {
		t.Fatalf("response %q", body)
	}
	if len(*out) != 1 || (*out)[0].to != testCfg.owner {
		t.Fatalf("sent %+v", *out)
	}
	subject, text, html := parts(t, (*out)[0].message)
	if !strings.Contains(subject, "someone@elsewhere.example") || !strings.Contains(subject, "Hello <there>") {
		t.Errorf("subject %q", subject)
	}
	for _, want := range []string{"agent-dms approve 4b5a8c489800400", "Please <b>approve</b> me.", "other@agent-dms.example, owner@example.org"} {
		if !strings.Contains(text, want) {
			t.Errorf("text part missing %q:\n%s", want, text)
		}
	}
	if strings.Contains(html, "<b>approve</b>") || !strings.Contains(html, "&lt;b&gt;approve&lt;/b&gt;") {
		t.Errorf("HTML part doesn't escape the agent's text:\n%s", html)
	}
	if !strings.Contains(html, "agent-dms reject 4b5a8c489800400") {
		t.Errorf("HTML part missing the reject command")
	}
}

func TestLocalAndOwnerOnlySendsNothing(t *testing.T) {
	s, out := newTestServer(t)
	post(t, s, hookBody(t, []string{"Other@Agent-DMS.example", "OWNER@example.org"}, plainHeaders, "hi\r\n"))
	if len(*out) != 0 {
		t.Fatalf("sent %d requests for mail that isn't held", len(*out))
	}
}

func TestMultipartBodyAndAttachments(t *testing.T) {
	contents := strings.Join([]string{
		"--b1",
		"Content-Type: multipart/alternative; boundary=b2",
		"",
		"--b2",
		"Content-Type: text/plain; charset=utf-8",
		"Content-Transfer-Encoding: base64",
		"",
		"cGxhaW4gYm9keQ==",
		"--b2",
		"Content-Type: text/html",
		"",
		"<p>html body</p>",
		"--b2--",
		"--b1",
		"Content-Type: application/pdf; name=report.pdf",
		"Content-Disposition: attachment; filename=report.pdf",
		"Content-Transfer-Encoding: base64",
		"",
		"JVBERg==",
		"--b1--",
		"",
	}, "\r\n")
	headers := append([][]string{{"Content-Type", " multipart/mixed; boundary=b1\r\n"}, {"MIME-Version", " 1.0\r\n"}}, plainHeaders...)
	var n notification
	n.parse(headers, contents)
	if n.Body != "plain body" {
		t.Errorf("body %q", n.Body)
	}
	if len(n.Attachments) != 1 || n.Attachments[0] != "report.pdf" {
		t.Errorf("attachments %v", n.Attachments)
	}
	if n.Subject != "Hello <there>" {
		t.Errorf("subject %q", n.Subject)
	}
}

func TestHTMLOnlyBodyIsShownAsSource(t *testing.T) {
	headers := append([][]string{{"Content-Type", " text/html\r\n"}}, plainHeaders...)
	var n notification
	n.parse(headers, "<p>only html</p>\r\n")
	if n.Body != "<p>only html</p>\r\n" || n.BodyNote == "" {
		t.Errorf("body %q note %q", n.Body, n.BodyNote)
	}
}

func TestNonDataStageIgnored(t *testing.T) {
	s, out := newTestServer(t)
	post(t, s, strings.NewReader(`{"context":{"stage":"rcpt"},"envelope":{"from":{"address":"a@b.c"},"to":[{"address":"x@y.z"}]}}`))
	if len(*out) != 0 {
		t.Fatal("sent a request outside DATA")
	}
}

package main

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	htmltemplate "html/template"
	"io"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net/mail"
	"net/textproto"
	"strings"
	texttemplate "text/template"
	"time"
)

const maxBodyText = 64 << 10

type header struct {
	Name, Value string
}

type notification struct {
	QueueID      string
	SubmittedBy  string
	EnvelopeFrom string
	Held         []string
	Immediate    []string
	Headers      []header
	Subject      string
	Body         string
	BodyNote     string
	Attachments  []string
}

var shownHeaders = []string{"From", "Reply-To", "To", "Cc", "Subject", "Date", "Message-ID"}

// parse reads the message as the hook received it: raw header values with
// their leading space and CRLF, and the body after the blank line.
func (n *notification) parse(rawHeaders [][]string, contents string) {
	var raw strings.Builder
	for _, h := range rawHeaders {
		if len(h) != 2 {
			continue
		}
		raw.WriteString(h[0] + ":" + h[1])
	}
	raw.WriteString("\r\n")
	raw.WriteString(contents)

	msg, err := mail.ReadMessage(strings.NewReader(raw.String()))
	if err != nil {
		n.BodyNote = fmt.Sprintf("The message could not be parsed (%v); approve prints it raw.", err)
		return
	}
	dec := new(mime.WordDecoder)
	for _, name := range shownHeaders {
		value := msg.Header.Get(name)
		if value == "" {
			continue
		}
		if decoded, err := dec.DecodeHeader(value); err == nil {
			value = decoded
		}
		n.Headers = append(n.Headers, header{name, value})
		if name == "Subject" {
			n.Subject = value
		}
	}

	var plain, html string
	n.walk(textproto.MIMEHeader(msg.Header), msg.Body, &plain, &html)
	switch {
	case plain != "":
		n.Body = plain
	case html != "":
		n.Body = html
		n.BodyNote = "The message has no plain-text part; this is its HTML source."
	default:
		n.BodyNote = "The message has no text part."
	}
	if len(n.Body) > maxBodyText {
		n.Body = n.Body[:maxBodyText]
		n.BodyNote = "The text is cut off here; approve prints the whole message."
	}
}

func (n *notification) walk(h textproto.MIMEHeader, body io.Reader, plain, html *string) {
	mediaType, params, err := mime.ParseMediaType(h.Get("Content-Type"))
	if err != nil {
		mediaType = "text/plain"
	}
	if strings.HasPrefix(mediaType, "multipart/") {
		mr := multipart.NewReader(body, params["boundary"])
		for {
			part, err := mr.NextPart()
			if err != nil {
				return
			}
			n.walk(part.Header, part, plain, html)
		}
	}

	disposition, dparams, _ := mime.ParseMediaType(h.Get("Content-Disposition"))
	filename := dparams["filename"]
	if filename == "" {
		filename = params["name"]
	}
	if disposition == "attachment" || filename != "" {
		if filename == "" {
			filename = "(unnamed " + mediaType + ")"
		}
		n.Attachments = append(n.Attachments, filename)
		return
	}

	// multipart.Part already undoes quoted-printable; the top-level body and
	// base64 parts are left to us.
	switch strings.ToLower(h.Get("Content-Transfer-Encoding")) {
	case "base64":
		body = base64.NewDecoder(base64.StdEncoding, body)
	case "quoted-printable":
		body = quotedprintable.NewReader(body)
	}
	data, err := io.ReadAll(io.LimitReader(body, maxBodyText+1))
	if err != nil {
		return
	}
	switch mediaType {
	case "text/plain":
		if *plain == "" {
			*plain = string(data)
		}
	case "text/html":
		if *html == "" {
			*html = string(data)
		}
	}
}

func (n *notification) build(cfg config) ([]byte, error) {
	var text, html bytes.Buffer
	if err := textTmpl.Execute(&text, n); err != nil {
		return nil, fmt.Errorf("rendering the text part: %w", err)
	}
	if err := htmlTmpl.Execute(&html, n); err != nil {
		return nil, fmt.Errorf("rendering the HTML part: %w", err)
	}

	var msg bytes.Buffer
	mw := multipart.NewWriter(&msg)
	subject := fmt.Sprintf("[agent-dms] Approve: %s -> %s", n.EnvelopeFrom, strings.Join(n.Held, ", "))
	if n.Subject != "" {
		subject += ": " + n.Subject
	}
	id := make([]byte, 12)
	if _, err := rand.Read(id); err != nil {
		return nil, fmt.Errorf("generating a Message-ID: %w", err)
	}
	fmt.Fprintf(&msg, "From: agent-dms approvals <%s>\r\n", cfg.login)
	fmt.Fprintf(&msg, "To: <%s>\r\n", cfg.owner)
	fmt.Fprintf(&msg, "Subject: %s\r\n", mime.QEncoding.Encode("utf-8", subject))
	fmt.Fprintf(&msg, "Date: %s\r\n", time.Now().Format(time.RFC1123Z))
	fmt.Fprintf(&msg, "Message-ID: <%s@%s>\r\n", hex.EncodeToString(id), cfg.domain)
	msg.WriteString("Auto-Submitted: auto-generated\r\n")
	msg.WriteString("MIME-Version: 1.0\r\n")
	fmt.Fprintf(&msg, "Content-Type: multipart/alternative; boundary=%s\r\n\r\n", mw.Boundary())

	for _, part := range []struct {
		contentType string
		body        []byte
	}{
		{"text/plain; charset=utf-8", text.Bytes()},
		{"text/html; charset=utf-8", html.Bytes()},
	} {
		w, err := mw.CreatePart(textproto.MIMEHeader{
			"Content-Type":              {part.contentType},
			"Content-Transfer-Encoding": {"quoted-printable"},
		})
		if err != nil {
			return nil, err
		}
		qp := quotedprintable.NewWriter(w)
		if _, err := qp.Write(part.body); err != nil {
			return nil, err
		}
		if err := qp.Close(); err != nil {
			return nil, err
		}
	}
	if err := mw.Close(); err != nil {
		return nil, err
	}
	return msg.Bytes(), nil
}

var textTmpl = texttemplate.Must(texttemplate.New("text").Parse(`{{.EnvelopeFrom}} wants to send mail outside agent-dms.

Stalwart is holding it for {{range $i, $a := .Held}}{{if $i}}, {{end}}{{$a}}{{end}}. Nothing has been sent to them. It waits in the queue until you approve or reject it, and expires after 7 days.
{{- if .Immediate}}
Already delivered to: {{range $i, $a := .Immediate}}{{if $i}}, {{end}}{{$a}}{{end}}
{{- end}}

Queue ID:      {{.QueueID}}
Submitted by:  {{.SubmittedBy}}
{{range .Headers}}
{{printf "%-14s" (print .Name ":")}} {{.Value}}{{end}}
{{- if .Attachments}}
Attachments:   {{range $i, $a := .Attachments}}{{if $i}}, {{end}}{{$a}}{{end}}
{{- end}}

----- message text -----
{{.Body}}
----- end -----
{{- if .BodyNote}}
({{.BodyNote}})
{{- end}}

Run these on the host, outside the jail.

Approve:

    agent-dms approve {{.QueueID}}

Reject:

    agent-dms reject {{.QueueID}}

Review first (prints Stalwart's queued copy, then y sends, n cancels):

    agent-dms review {{.QueueID}}

Stalwart's queued copy, not this email, is what gets sent.
`))

var htmlTmpl = htmltemplate.Must(htmltemplate.New("html").Parse(`<!DOCTYPE html>
<html><body style="margin:0;padding:24px;background:#f5f5f4;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;color:#1c1917;">
<div style="max-width:720px;margin:0 auto;background:#ffffff;border:1px solid #e7e5e4;border-radius:8px;padding:24px;">
<h1 style="margin:0 0 8px;font-size:20px;">Agent mail waiting for your approval</h1>
<p style="margin:0 0 16px;line-height:1.5;"><strong>{{.EnvelopeFrom}}</strong> wants to send mail outside agent-dms. Stalwart is holding it for
{{range $i, $a := .Held}}{{if $i}}, {{end}}<strong>{{$a}}</strong>{{end}}; nothing has been sent to them. It waits in the queue until you approve or reject it, and expires after 7 days.</p>
{{if .Immediate}}<p style="margin:0 0 16px;line-height:1.5;color:#57534e;">Already delivered to {{range $i, $a := .Immediate}}{{if $i}}, {{end}}{{$a}}{{end}}.</p>{{end}}

<table style="border-collapse:collapse;width:100%;margin:0 0 20px;font-size:14px;">
<tr><td style="padding:4px 12px 4px 0;color:#78716c;white-space:nowrap;vertical-align:top;">Queue ID</td><td style="padding:4px 0;font-family:ui-monospace,Menlo,Consolas,monospace;">{{.QueueID}}</td></tr>
<tr><td style="padding:4px 12px 4px 0;color:#78716c;white-space:nowrap;vertical-align:top;">Submitted by</td><td style="padding:4px 0;">{{.SubmittedBy}}</td></tr>
{{range .Headers}}<tr><td style="padding:4px 12px 4px 0;color:#78716c;white-space:nowrap;vertical-align:top;">{{.Name}}</td><td style="padding:4px 0;word-break:break-word;">{{.Value}}</td></tr>
{{end}}{{if .Attachments}}<tr><td style="padding:4px 12px 4px 0;color:#78716c;white-space:nowrap;vertical-align:top;">Attachments</td><td style="padding:4px 0;">{{range $i, $a := .Attachments}}{{if $i}}, {{end}}{{$a}}{{end}}</td></tr>{{end}}
</table>

<blockquote style="margin:0 0 8px;padding:12px 16px;border-left:4px solid #a8a29e;background:#fafaf9;">
<pre style="margin:0;white-space:pre-wrap;word-break:break-word;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;line-height:1.45;">{{.Body}}</pre>
</blockquote>
{{if .BodyNote}}<p style="margin:0 0 20px;font-size:13px;color:#78716c;">{{.BodyNote}}</p>{{else}}<div style="height:12px;"></div>{{end}}

<p style="margin:0 0 12px;line-height:1.5;">Run these on the host, outside the jail.</p>
<h2 style="margin:0 0 8px;font-size:16px;">Approve</h2>
<pre style="margin:0 0 16px;padding:12px;background:#ecfdf5;border:1px solid #a7f3d0;border-radius:6px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:14px;-webkit-user-select:all;user-select:all;">agent-dms approve {{.QueueID}}</pre>
<h2 style="margin:0 0 8px;font-size:16px;">Reject</h2>
<pre style="margin:0 0 16px;padding:12px;background:#fef2f2;border:1px solid #fecaca;border-radius:6px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:14px;-webkit-user-select:all;user-select:all;">agent-dms reject {{.QueueID}}</pre>
<h2 style="margin:0 0 8px;font-size:16px;">Review first</h2>
<pre style="margin:0 0 8px;padding:12px;background:#f5f5f4;border:1px solid #e7e5e4;border-radius:6px;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:14px;-webkit-user-select:all;user-select:all;">agent-dms review {{.QueueID}}</pre>
<p style="margin:0 0 16px;font-size:13px;color:#78716c;line-height:1.5;">Prints Stalwart's queued copy, then y sends and n cancels.</p>
<p style="margin:0;font-size:13px;color:#78716c;line-height:1.5;">Stalwart's queued copy, not this email, is what gets sent.</p>
</div>
</body></html>
`))

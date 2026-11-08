// Stalwart MTA hook that mails the owner an approval request; the hold itself
// is Stalwart's outbound routing, so this never changes the message.
package main

import (
	"crypto/tls"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"net/smtp"
	"os"
	"strings"
)

type config struct {
	domain       string
	owner        string
	login        string
	password     string
	smtpAddr     string
	smtpHostname string
}

type hookRequest struct {
	Context struct {
		Stage string `json:"stage"`
		SASL  *struct {
			Login string `json:"login"`
		} `json:"sasl"`
		Queue *struct {
			ID string `json:"id"`
		} `json:"queue"`
	} `json:"context"`
	Envelope struct {
		From struct {
			Address string `json:"address"`
		} `json:"from"`
		To []struct {
			Address string `json:"address"`
		} `json:"to"`
	} `json:"envelope"`
	Message *struct {
		Headers  [][]string `json:"headers"`
		Contents string     `json:"contents"`
	} `json:"message"`
}

type sendFunc func(cfg config, to string, message []byte) error

type server struct {
	cfg  config
	send sendFunc
	// Notifications go out off the request path, so the hook answers Stalwart
	// at once; tests swap this for a synchronous call.
	spawn func(func())
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8092", "address the hook listens on")
	domain := flag.String("domain", "", "the agent-dms mail domain")
	owner := flag.String("owner", "", "address approval requests go to, and whose mail is never held")
	login := flag.String("login", "", "Stalwart account the requests are sent from")
	passwordFile := flag.String("password-file", "", "file holding that account's app password")
	smtpAddr := flag.String("smtp", "127.0.0.1:465", "Stalwart's implicit-TLS submission address")
	flag.Parse()

	logger := slog.New(slog.NewTextHandler(os.Stderr, nil))
	slog.SetDefault(logger)

	for name, value := range map[string]string{"domain": *domain, "owner": *owner, "login": *login, "password-file": *passwordFile} {
		if value == "" {
			fail("missing required flag", "flag", name)
		}
	}
	password, err := os.ReadFile(*passwordFile)
	if err != nil {
		fail("reading the password file", "error", err)
	}
	cfg := config{
		domain:       strings.ToLower(*domain),
		owner:        strings.ToLower(*owner),
		login:        *login,
		password:     strings.TrimSpace(string(password)),
		smtpAddr:     *smtpAddr,
		smtpHostname: *domain,
	}
	if cfg.password == "" {
		fail("the password file is empty", "path", *passwordFile)
	}

	s := &server{cfg: cfg, send: sendSMTP, spawn: func(f func()) { go f() }}
	slog.Info("listening", "address", *listen)
	if err := http.ListenAndServe(*listen, s); err != nil {
		fail("serving", "error", err)
	}
}

func fail(msg string, args ...any) {
	slog.Error(msg, args...)
	os.Exit(1)
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	var req hookRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<20)).Decode(&req); err != nil {
		slog.Error("decoding hook request", "error", err)
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	s.handle(&req)
	w.Header().Set("Content-Type", "application/json")
	_, _ = w.Write([]byte(`{"action":"accept"}`))
}

func (s *server) handle(req *hookRequest) {
	if req.Context.Stage != "data" || req.Message == nil {
		return
	}
	held, immediate := s.split(req)
	if len(held) == 0 {
		return
	}
	n := notification{
		EnvelopeFrom: req.Envelope.From.Address,
		Held:         held,
		Immediate:    immediate,
	}
	if req.Context.Queue != nil {
		n.QueueID = req.Context.Queue.ID
	}
	if req.Context.SASL != nil {
		n.SubmittedBy = req.Context.SASL.Login
	}
	if n.QueueID == "" {
		slog.Error("hook request has no queue id; the approval request would have no command", "from", n.EnvelopeFrom)
	}
	n.parse(req.Message.Headers, req.Message.Contents)
	log := slog.With("queue_id", n.QueueID, "from", n.EnvelopeFrom, "held", held)
	log.Info("holding for approval")
	s.spawn(func() {
		message, err := n.build(s.cfg)
		if err != nil {
			log.Error("building approval request", "error", err)
			return
		}
		if err := s.send(s.cfg, s.cfg.owner, message); err != nil {
			log.Error("sending approval request", "error", err)
			return
		}
		log.Info("sent approval request", "to", s.cfg.owner)
	})
}

// split mirrors the MtaOutboundStrategy route: local domains and the owner are
// delivered at once, everything else waits.
func (s *server) split(req *hookRequest) (held, immediate []string) {
	for _, rcpt := range req.Envelope.To {
		address := strings.ToLower(rcpt.Address)
		if address == s.cfg.owner || strings.HasSuffix(address, "@"+s.cfg.domain) {
			immediate = append(immediate, address)
		} else {
			held = append(held, address)
		}
	}
	return held, immediate
}

func sendSMTP(cfg config, to string, message []byte) error {
	conn, err := tls.Dial("tcp", cfg.smtpAddr, &tls.Config{ServerName: cfg.smtpHostname})
	if err != nil {
		return fmt.Errorf("connecting to %s: %w", cfg.smtpAddr, err)
	}
	host, _, _ := net.SplitHostPort(cfg.smtpAddr)
	c, err := smtp.NewClient(conn, host)
	if err != nil {
		return fmt.Errorf("starting SMTP: %w", err)
	}
	defer c.Close()
	if err := c.Auth(smtp.PlainAuth("", cfg.login, cfg.password, host)); err != nil {
		return fmt.Errorf("logging in as %s: %w", cfg.login, err)
	}
	if err := c.Mail(cfg.login); err != nil {
		return fmt.Errorf("MAIL FROM: %w", err)
	}
	if err := c.Rcpt(to); err != nil {
		return fmt.Errorf("RCPT TO %s: %w", to, err)
	}
	wc, err := c.Data()
	if err != nil {
		return fmt.Errorf("DATA: %w", err)
	}
	if _, err := wc.Write(message); err != nil {
		return errors.Join(fmt.Errorf("writing the message: %w", err), wc.Close())
	}
	if err := wc.Close(); err != nil {
		return fmt.Errorf("finishing DATA: %w", err)
	}
	return c.Quit()
}

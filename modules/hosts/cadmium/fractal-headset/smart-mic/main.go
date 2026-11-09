package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	smartMicName  = "smart-mic"
	captureName   = "smart-mic-capture"
	nodeType      = "PipeWire:Interface:Node"
	dongleProduct = 0x0001
	replyTimeout  = time.Second
	rescanEvery   = time.Second
	metadataLimit = 5 * time.Second
	mutedByte     = 5
	boomUpByte    = 14
)

var statusQuery = []byte{0x02, 0xf1, 0x21}

type dumpObject struct {
	ID   uint32          `json:"id"`
	Type string          `json:"type"`
	Info json.RawMessage `json:"info"`
}

type nodeInfo struct {
	State string         `json:"state"`
	Props map[string]any `json:"props"`
}

type hidState struct {
	available bool
	boomUp    bool
	muted     bool
}

func main() {
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, nil)))

	headset := flag.String("headset", "", "node.name of the headset mic")
	webcam := flag.String("webcam", "", "node.name of the webcam mic")
	pollEvery := flag.Duration("poll", 100*time.Millisecond, "HID poll interval while smart-mic is running")
	vendorFlag := flag.String("vendor", "36bc", "USB vendor ID of the headset dongle (hex)")
	flag.Parse()

	if *headset == "" || *webcam == "" {
		slog.Error("-headset and -webcam are required", "headset", *headset, "webcam", *webcam)
		os.Exit(2)
	}
	if *pollEvery <= 0 {
		slog.Error("-poll must be positive", "poll", *pollEvery)
		os.Exit(2)
	}
	vendor, err := strconv.ParseUint(*vendorFlag, 16, 16)
	if err != nil {
		slog.Error("-vendor is not a 16-bit hex ID", "vendor", *vendorFlag, "err", err)
		os.Exit(2)
	}

	c := &controller{
		headset:   *headset,
		webcam:    *webcam,
		pollEvery: *pollEvery,
		hidID:     fmt.Sprintf("HID_ID=0003:%08X:%08X", vendor, dongleProduct),
		nodes:     map[uint32]string{},
	}
	os.Exit(c.run())
}

type controller struct {
	headset   string
	webcam    string
	pollEvery time.Duration
	hidID     string

	nodes         map[uint32]string
	smartMicState string
	captureID     uint32
	haveCapture   bool
	headsetSeen   bool
	webcamSeen    bool

	// Empty means unknown, which forces the next decision to write the metadata.
	target  string
	poller  *poller
	hid     hidState
	haveHID bool
	blocked string
}

func (c *controller) run() int {
	cmd := exec.Command("pw-dump", "--monitor", "--no-colors")
	cmd.Stderr = os.Stderr
	// Don't leave an orphaned pw-dump behind when run outside systemd's cgroup cleanup.
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		slog.Error("pw-dump stdout pipe", "err", err)
		return 1
	}
	if err := cmd.Start(); err != nil {
		slog.Error("start pw-dump", "err", err)
		return 1
	}

	batches := make(chan []dumpObject)
	dumpErr := make(chan error, 1)
	go func() { dumpErr <- readDump(stdout, batches) }()

	for {
		var states <-chan hidState
		if c.poller != nil {
			states = c.poller.states
		}
		select {
		case batch := <-batches:
			if err := c.handleBatch(batch); err != nil {
				slog.Error("bad pw-dump object", "err", err)
				_ = cmd.Process.Kill()
				return 1
			}
		case st := <-states:
			c.handleHID(st)
		case err := <-dumpErr:
			slog.Error("pw-dump stream ended", "decode_err", err, "exit", cmd.Wait())
			return 1
		}
	}
}

// pw-dump --monitor writes one JSON array per update; the first holds every object.
func readDump(r io.Reader, out chan<- []dumpObject) error {
	dec := json.NewDecoder(r)
	for {
		var batch []dumpObject
		if err := dec.Decode(&batch); err != nil {
			return err
		}
		out <- batch
	}
}

func (c *controller) handleBatch(batch []dumpObject) error {
	newState := c.smartMicState
	captureChanged := false

	for _, obj := range batch {
		// Removals are emitted as {"id": N, "info": null} with no type.
		if obj.Type == "" {
			name, ok := c.nodes[obj.ID]
			if !ok {
				continue
			}
			delete(c.nodes, obj.ID)
			switch name {
			case smartMicName:
				newState = ""
			case captureName:
				if c.haveCapture && c.captureID == obj.ID {
					c.haveCapture = false
					captureChanged = true
				}
			}
			continue
		}
		if obj.Type != nodeType {
			continue
		}

		var info nodeInfo
		if err := json.Unmarshal(obj.Info, &info); err != nil {
			return fmt.Errorf("node %d info: %w", obj.ID, err)
		}
		name, _ := info.Props["node.name"].(string)
		if name == "" {
			continue
		}
		c.nodes[obj.ID] = name
		switch name {
		case smartMicName:
			newState = info.State
		case captureName:
			if !c.haveCapture || c.captureID != obj.ID {
				c.captureID = obj.ID
				c.haveCapture = true
				captureChanged = true
			}
		}
	}

	if captureChanged {
		// A new capture node starts from its configured target, not our last switch.
		c.target = ""
		if c.haveCapture {
			slog.Info("smart-mic-capture found", "id", c.captureID)
		} else {
			slog.Warn("smart-mic-capture lost")
		}
	}

	headsetSeen, webcamSeen := c.nodePresent(c.headset), c.nodePresent(c.webcam)
	presenceChanged := headsetSeen != c.headsetSeen || webcamSeen != c.webcamSeen
	if headsetSeen != c.headsetSeen {
		slog.Info("headset node", "present", headsetSeen, "node", c.headset)
	}
	if webcamSeen != c.webcamSeen {
		slog.Info("webcam node", "present", webcamSeen, "node", c.webcam)
	}
	c.headsetSeen, c.webcamSeen = headsetSeen, webcamSeen

	wasRunning := c.smartMicState == "running"
	c.smartMicState = newState
	isRunning := newState == "running"
	switch {
	case isRunning && !wasRunning:
		slog.Info("smart-mic active")
		c.poller = startPoller(c.hidID, c.pollEvery)
	case !isRunning && wasRunning:
		slog.Info("smart-mic idle", "state", newState)
		c.poller.halt()
		c.poller = nil
		c.haveHID = false
		c.blocked = ""
	case isRunning && (captureChanged || presenceChanged):
		c.decide()
	}
	return nil
}

func (c *controller) nodePresent(name string) bool {
	for _, n := range c.nodes {
		if n == name {
			return true
		}
	}
	return false
}

func (c *controller) handleHID(st hidState) {
	prev, hadPrev := c.hid, c.haveHID && c.hid.available
	c.hid, c.haveHID = st, true
	if st.available {
		if !hadPrev || prev.boomUp != st.boomUp {
			slog.Info("boom", "up", st.boomUp)
		}
		if !hadPrev || prev.muted != st.muted {
			slog.Info("mic", "muted", st.muted)
		}
	}
	if hadPrev && prev == st {
		return
	}
	c.decide()
}

func (c *controller) decide() {
	if !c.haveHID {
		return
	}
	want := c.webcam
	// A button mute with the boom down stays on the headset: that silence is intended.
	if c.hid.available && !c.hid.boomUp {
		want = c.headset
	}
	if want == c.target {
		c.blocked = ""
		return
	}
	if !c.haveCapture {
		c.block("cannot switch: smart-mic-capture node not found", want)
		return
	}
	if !c.nodePresent(want) {
		c.block("cannot switch: wanted source node missing, leaving target", want)
		return
	}
	if err := setTarget(c.captureID, want); err != nil {
		slog.Error("switch failed", "target", want, "err", err)
		return
	}
	slog.Info("switch", "target", want)
	c.target = want
	c.blocked = ""
}

// Logs a blocked switch once per reason instead of on every poll.
func (c *controller) block(reason, want string) {
	key := reason + "\x00" + want
	if c.blocked == key {
		return
	}
	c.blocked = key
	slog.Warn(reason, "want", want)
}

func setTarget(captureID uint32, nodeName string) error {
	ctx, cancel := context.WithTimeout(context.Background(), metadataLimit)
	defer cancel()
	out, err := exec.CommandContext(ctx, "pw-metadata", strconv.FormatUint(uint64(captureID), 10), "target.object", nodeName).CombinedOutput()
	if err != nil {
		return fmt.Errorf("pw-metadata: %w: %s", err, bytes.TrimSpace(out))
	}
	// pw-metadata exits 0 without setting anything when the "default" metadata object is absent.
	if !bytes.Contains(out, []byte("set property:")) {
		return fmt.Errorf("pw-metadata did not set the property: %s", bytes.TrimSpace(out))
	}
	return nil
}

type poller struct {
	stop   chan struct{}
	states chan hidState
}

func startPoller(hidID string, every time.Duration) *poller {
	p := &poller{stop: make(chan struct{}), states: make(chan hidState)}
	go p.run(hidID, every)
	return p
}

func (p *poller) halt() { close(p.stop) }

func (p *poller) run(hidID string, every time.Duration) {
	var dev *os.File
	devPath := ""
	defer func() {
		if dev != nil {
			if err := dev.Close(); err != nil {
				slog.Error("close hidraw", "path", devPath, "err", err)
			}
		}
	}()

	lastErr := ""
	reportedMissing := false
	unavailable := func(err error) bool {
		if err.Error() != lastErr {
			slog.Error("hidraw unavailable, using webcam", "err", err)
			lastErr = err.Error()
		}
		if !reportedMissing {
			reportedMissing = true
			if !p.send(hidState{}) {
				return false
			}
		}
		return p.sleep(rescanEvery)
	}

	for {
		if dev == nil {
			path, err := findHidraw(hidID)
			if err != nil {
				if !unavailable(err) {
					return
				}
				continue
			}
			f, err := os.OpenFile(path, os.O_RDWR, 0)
			if err != nil {
				if !unavailable(err) {
					return
				}
				continue
			}
			dev, devPath = f, path
			lastErr, reportedMissing = "", false
			slog.Info("device found", "path", path)
		}

		st, err := query(dev)
		if err != nil {
			if cerr := dev.Close(); cerr != nil {
				slog.Error("close hidraw", "path", devPath, "err", cerr)
			}
			slog.Warn("device lost", "path", devPath)
			dev, devPath = nil, ""
			if !unavailable(fmt.Errorf("poll: %w", err)) {
				return
			}
			continue
		}
		if !p.send(st) || !p.sleep(every) {
			return
		}
	}
}

func (p *poller) send(st hidState) bool {
	select {
	case p.states <- st:
		return true
	case <-p.stop:
		return false
	}
}

func (p *poller) sleep(d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return true
	case <-p.stop:
		return false
	}
}

func findHidraw(hidID string) (string, error) {
	uevents, err := filepath.Glob("/sys/class/hidraw/*/device/uevent")
	if err != nil {
		return "", fmt.Errorf("glob hidraw: %w", err)
	}
	var matches []string
	for _, path := range uevents {
		data, err := os.ReadFile(path)
		if err != nil {
			return "", fmt.Errorf("read %s: %w", path, err)
		}
		for _, line := range strings.Split(string(data), "\n") {
			if strings.EqualFold(line, hidID) {
				matches = append(matches, "/dev/"+filepath.Base(filepath.Dir(filepath.Dir(path))))
				break
			}
		}
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("no hidraw node with %s", hidID)
	case 1:
		return matches[0], nil
	default:
		return "", fmt.Errorf("multiple hidraw nodes with %s: %v", hidID, matches)
	}
}

func query(dev *os.File) (hidState, error) {
	if err := dev.SetDeadline(time.Now().Add(replyTimeout)); err != nil {
		return hidState{}, fmt.Errorf("set deadline: %w", err)
	}
	if _, err := dev.Write(statusQuery); err != nil {
		return hidState{}, fmt.Errorf("write status query: %w", err)
	}
	buf := make([]byte, 64)
	for {
		n, err := dev.Read(buf)
		if errors.Is(err, os.ErrDeadlineExceeded) {
			return hidState{}, fmt.Errorf("no status reply within %s", replyTimeout)
		}
		if err != nil {
			return hidState{}, fmt.Errorf("read reply: %w", err)
		}
		reply := buf[:n]
		// Other reports (e.g. the vendor configurer's own polling) share this fd.
		if !bytes.HasPrefix(reply, statusQuery) {
			continue
		}
		if n <= boomUpByte {
			return hidState{}, fmt.Errorf("status reply too short: %d bytes", n)
		}
		boomUp, err := flagByte(reply[boomUpByte], "boom")
		if err != nil {
			return hidState{}, err
		}
		muted, err := flagByte(reply[mutedByte], "mute")
		if err != nil {
			return hidState{}, err
		}
		return hidState{available: true, boomUp: boomUp, muted: muted}, nil
	}
}

func flagByte(b byte, what string) (bool, error) {
	switch b {
	case 0x00:
		return false, nil
	case 0x01:
		return true, nil
	default:
		return false, fmt.Errorf("unexpected %s byte 0x%02x", what, b)
	}
}

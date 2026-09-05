// Package watchfacade contains the process lifecycle needed by Haxe-authored
// polling commands. It owns only timers and OS signals; command and rendering
// policy remain in Haxe.
package watchfacade

import (
	"os"
	"os/signal"
	"syscall"
	"time"
)

// Control reports either a poll tick or a request to stop watching.
type Control struct {
	interval time.Duration
	signals  chan os.Signal
	ticker   *time.Ticker
}

// NewControl creates an inert lifecycle value. Start owns resource activation.
func NewControl() *Control {
	return &Control{interval: 2 * time.Second}
}

func newControlWithInterval(interval time.Duration) *Control {
	return &Control{interval: interval}
}

// Start begins interrupt delivery and polling. Repeated calls are harmless.
func (c *Control) Start() {
	if c.ticker != nil {
		return
	}
	c.signals = make(chan os.Signal, 1)
	signal.Notify(c.signals, os.Interrupt, syscall.SIGTERM)
	c.ticker = time.NewTicker(c.interval)
}

// WaitForStop blocks until the next poll tick or process stop signal.
func (c *Control) WaitForStop() bool {
	if c.ticker == nil {
		return true
	}
	select {
	case <-c.signals:
		return true
	case <-c.ticker.C:
		return false
	}
}

// Close releases signal and timer resources. Repeated calls are harmless.
func (c *Control) Close() {
	if c.ticker == nil {
		return
	}
	signal.Stop(c.signals)
	c.ticker.Stop()
	c.ticker = nil
	c.signals = nil
}

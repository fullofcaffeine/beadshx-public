package watchfacade

import (
	"testing"
	"time"
)

func TestControlReportsTickAndClosesIdempotently(t *testing.T) {
	control := newControlWithInterval(time.Millisecond)
	control.Start()
	control.Start()
	if control.WaitForStop() {
		t.Fatal("timer tick reported a stop signal")
	}
	control.Close()
	control.Close()
	if !control.WaitForStop() {
		t.Fatal("closed control did not stop")
	}
}

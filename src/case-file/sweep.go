package main

import (
	"flag"
	"fmt"
	"io"
	"net/http"
	"time"
)

// runSweep is the promotion gate's Job. It sends every size, as a download
// and an upload, several times each (so requests land on API pods on every
// node), and exits non-zero if any request fails. On failure it prints
// frontdesk's error, which includes the upstream hop's TCP retransmits.
func runSweep(args []string, out io.Writer) error {
	fs := flag.NewFlagSet("sweep", flag.ExitOnError)
	target := fs.String("target", "http://frontdesk:8080", "frontdesk base URL")
	sizeList := fs.String("sizes", "1K,16K,64K,256K,1M,4M", "payload sizes")
	attempts := fs.Int("attempts", 4, "requests per size and method")
	timeout := fs.Duration("timeout", 6*time.Second, "per-request timeout")
	_ = fs.Parse(args)

	sizes, err := parseSizes(*sizeList)
	if err != nil {
		return err
	}
	failed, total := 0, 0
	for _, size := range sizes {
		for _, method := range []string{http.MethodGet, http.MethodPost} {
			for a := 1; a <= *attempts; a++ {
				r := probe(*target, method, size, *timeout)
				total++
				status := "PASS"
				detail := "node=" + r.node
				if r.err != nil {
					status, detail = "FAIL", r.err.Error()
					failed++
				}
				_, _ = fmt.Fprintf(out, "%s %-4s %5s  attempt %d/%d  %6dms  %s\n",
					status, method, formatSize(size), a, *attempts, r.duration.Milliseconds(), detail)
			}
		}
	}
	_, _ = fmt.Fprintf(out, "RESULT %d/%d requests passed\n", total-failed, total)
	if failed > 0 {
		return fmt.Errorf("%d of %d requests failed", failed, total)
	}
	return nil
}

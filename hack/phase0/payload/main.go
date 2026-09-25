// payload is a Phase 0 test tool: "serve" returns or accepts N bytes,
// "sweep" requests a range of sizes and reports which ones complete.
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"
)

var sizes = []int{1 << 10, 16 << 10, 64 << 10, 256 << 10, 1 << 20, 4 << 20}

func serve(addr string) {
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { io.WriteString(w, "ok") })
	http.HandleFunc("/bytes", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost {
			n, err := io.Copy(io.Discard, r.Body)
			if err != nil {
				http.Error(w, err.Error(), http.StatusBadRequest)
				return
			}
			fmt.Fprintf(w, "%d", n)
			return
		}
		n, err := strconv.Atoi(r.URL.Query().Get("size"))
		if err != nil || n < 0 {
			http.Error(w, "bad size", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Length", strconv.Itoa(n))
		w.Write(bytes.Repeat([]byte{'x'}, n))
	})
	log.Fatal(http.ListenAndServe(addr, nil))
}

func sweep(target string, timeout time.Duration, only string) bool {
	ok := true
	check := func(method string, size int) {
		// A fresh connection per request, so every check does its own handshake.
		c := &http.Client{Timeout: timeout, Transport: &http.Transport{DisableKeepAlives: true}}
		start := time.Now()
		var resp *http.Response
		var err error
		if method == http.MethodGet {
			resp, err = c.Get(fmt.Sprintf("%s/bytes?size=%d", target, size))
		} else {
			resp, err = c.Post(target+"/bytes", "application/octet-stream", bytes.NewReader(bytes.Repeat([]byte{'x'}, size)))
		}
		result := "PASS"
		if err == nil {
			_, err = io.Copy(io.Discard, resp.Body)
			resp.Body.Close()
		}
		if err != nil {
			result, ok = "FAIL", false
		}
		fmt.Printf("%-4s %-5s %8d bytes  %6dms  %v\n", result, method, size, time.Since(start).Milliseconds(), errString(err))
	}
	check(http.MethodGet, 64) // healthz-sized request
	for _, s := range sizes {
		if only != "post" {
			check(http.MethodGet, s)
		}
		if only != "get" {
			check(http.MethodPost, s)
		}
	}
	return ok
}

func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: payload serve|sweep [flags]")
	}
	fs := flag.NewFlagSet(os.Args[1], flag.ExitOnError)
	addr := fs.String("addr", ":8080", "listen address (serve)")
	target := fs.String("target", "http://localhost:8080", "base URL (sweep)")
	timeout := fs.Duration("timeout", 5*time.Second, "per-request timeout (sweep)")
	only := fs.String("only", "", "run only \"get\" or \"post\" checks (sweep)")
	fs.Parse(os.Args[2:])
	switch os.Args[1] {
	case "serve":
		serve(*addr)
	case "sweep":
		if !sweep(*target, *timeout, *only) {
			os.Exit(1)
		}
	default:
		log.Fatalf("unknown mode %q", os.Args[1])
	}
}

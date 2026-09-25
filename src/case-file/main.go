// Command case-file is the demo app for "The Case of the Green Dashboard".
// One binary, one image, five roles:
//
//	evidence-locker  the API: returns and accepts payloads of any size
//	frontdesk        the frontend: proxies /api/* to evidence-locker pods
//	informant        a continuous prober that plays the city's users
//	sweep            a one-shot payload sweep, run as the promotion gate's Job
//	tuner            node-tuner: sets a node's underlay MTU (the culprit's vehicle)
package main

import (
	"fmt"
	"log/slog"
	"os"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stderr, nil)).With("version", version))

	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	mode, args := os.Args[1], os.Args[2:]
	var err error
	switch mode {
	case "evidence-locker":
		err = runEvidenceLocker(args)
	case "frontdesk":
		err = runFrontdesk(args)
	case "informant":
		err = runInformant(args)
	case "sweep":
		err = runSweep(args, os.Stdout)
	case "tuner":
		err = runTuner(args)
	case "version":
		fmt.Println(version)
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		slog.Error("exiting", "mode", mode, "err", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: case-file evidence-locker|frontdesk|informant|sweep|tuner|version [flags]")
}

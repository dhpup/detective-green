package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
)

// tuner is node-tuner: it declares a node's underlay MTU and keeps it there.
// It runs as a DaemonSet with hostNetwork and only the NET_ADMIN capability,
// one DaemonSet per node pool, so changing one pool's MTU is a one-line diff.
func runTuner(args []string) error {
	fs := flag.NewFlagSet("tuner", flag.ExitOnError)
	listen := fs.String("listen", ":9102", "health/metrics listen address")
	iface := fs.String("interface", "eth0", "interface to manage")
	mtu := fs.Int("mtu", 1500, "MTU to set")
	interval := fs.Duration("interval", 30*time.Second, "how often to re-check the MTU")
	_ = fs.Parse(args)
	if *mtu < 576 || *mtu > 9216 {
		return fmt.Errorf("mtu %d out of range 576-9216", *mtu)
	}

	reg := prometheus.NewRegistry()
	gauge := prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "case_file", Name: "tuner_interface_mtu", Help: "Current MTU of the managed interface.",
		ConstLabels: prometheus.Labels{"interface": *iface},
	})
	reg.MustRegister(gauge)

	reconcile := func() {
		ifc, err := net.InterfaceByName(*iface)
		if err != nil {
			slog.Error("interface lookup failed", "interface", *iface, "err", err)
			return
		}
		if ifc.MTU != *mtu {
			if err := setMTU(*iface, *mtu); err != nil {
				slog.Error("set MTU failed", "interface", *iface, "mtu", *mtu, "err", err)
				return
			}
			slog.Info("MTU changed", "interface", *iface, "from", ifc.MTU, "to", *mtu)
		}
		gauge.Set(float64(*mtu))
	}
	reconcile()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() {
		t := time.NewTicker(*interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				reconcile()
			}
		}
	}()
	return serve(*listen, http.NewServeMux(), reg)
}

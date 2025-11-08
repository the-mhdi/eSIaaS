package main

import (
	"flag"
	"log"

	"github.com/the-mhdi/eSIaaS/core/node"
	"github.com/the-mhdi/eSIaaS/core/p2p"
	"github.com/the-mhdi/eSIaaS/pkg/config"
	"github.com/the-mhdi/eSIaaS/pkg/logger"
	"go.uber.org/zap"
)

func main() {
	configPath := flag.String("config", "./config.yaml", "path to config file")
	flag.Parse()

	cfg, err := config.LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	logr, err := logger.New(cfg.Node.LogLevel)
	if err != nil {
		log.Fatalf("failed to initialize logger: %v", err)
	}
	defer logr.Sync()

	n := node.New(cfg, logr)

	// --- Add P2P subsystem ---
	p2pSvc, err := p2p.New(n.Context(), logr, cfg.P2P.ListenPort, cfg.P2P.Bootstrap)
	if err != nil {
		logr.Fatal("Failed to init P2P", zap.Error(err))
	}
	n.RegisterService(p2pSvc)

	// Future: add DHT as a service using p2p host
	// dhtSvc, _ := dht.New(n.Context(), logr, p2pSvc.Host())
	// n.RegisterService(dhtSvc)

	if err := n.Start(); err != nil {
		logr.Fatal("Node failed to start", zap.Error(err))
	}

	select {
	case <-n.Context().Done():

	} // Block forever (until signal)
}

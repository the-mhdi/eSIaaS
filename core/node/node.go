package node

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"go.uber.org/zap"

	"github.com/the-mhdi/eSIaaS/pkg/config"
)

type Node struct {
	cfg    *config.Config
	log    *zap.Logger
	ctx    context.Context
	cancel context.CancelFunc

	services []Service // Registered services
}

type Service interface {
	Start(ctx context.Context) error
	Stop() error
	Name() string
}

func New(cfg *config.Config, log *zap.Logger) *Node {
	ctx, cancel := context.WithCancel(context.Background())
	return &Node{
		cfg:    cfg,
		log:    log,
		ctx:    ctx,
		cancel: cancel,
	}
}

func (n *Node) RegisterService(s Service) {
	n.services = append(n.services, s)
}

func (n *Node) Start() error {
	n.log.Info("Starting provider node", zap.String("listen_addr", n.cfg.Node.ListenAddr))

	for _, s := range n.services {
		if err := s.Start(n.ctx); err != nil {
			return fmt.Errorf("failed to start service %s: %w", s.Name(), err)
		}
		n.log.Info("Started service", zap.String("name", s.Name()))
	}

	go n.handleInterrupt()
	return nil
}

func (n *Node) handleInterrupt() {
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	n.log.Info("Shutting down provider node...")
	n.Stop()
}

func (n *Node) Stop() {
	for _, s := range n.services {
		n.log.Info("Stopping service", zap.String("name", s.Name()))
		if err := s.Stop(); err != nil {
			n.log.Warn("Error stopping service", zap.String("name", s.Name()), zap.Error(err))
		}
	}
	n.cancel()

	n.log.Info("Node shutdown complete")
}

func (n *Node) Context() context.Context {
	return n.ctx
}

package dht

import (
	"context"
	"fmt"

	libdht "github.com/libp2p/go-libp2p-kad-dht"
	host "github.com/libp2p/go-libp2p/core/host"
	"go.uber.org/zap"
)

type DHTService struct {
	log    *zap.Logger
	host   host.Host
	dht    *libdht.IpfsDHT
	ctx    context.Context
	cancel context.CancelFunc
}

func New(ctx context.Context, log *zap.Logger, h host.Host) (*DHTService, error) {
	dctx, cancel := context.WithCancel(ctx)
	kdht, err := libdht.New(dctx, h)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to create DHT: %w", err)
	}
	return &DHTService{
		log:    log,
		host:   h,
		dht:    kdht,
		ctx:    dctx,
		cancel: cancel,
	}, nil
}

func (d *DHTService) Name() string { return "dht" }

func (d *DHTService) Start(ctx context.Context) error {
	d.log.Info("Starting DHT service", zap.String("host", d.host.ID().String()))
	if err := d.dht.Bootstrap(d.ctx); err != nil {
		return fmt.Errorf("failed to bootstrap DHT: %w", err)
	}
	return nil
}

func (d *DHTService) Stop() error {
	d.log.Info("Stopping DHT service")
	d.cancel()
	return d.dht.Close()
}

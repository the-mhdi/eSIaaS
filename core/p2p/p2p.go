package p2p

import (
	"context"
	"encoding/json"
	"fmt"

	libp2p "github.com/libp2p/go-libp2p"
	dht "github.com/libp2p/go-libp2p-kad-dht"
	host "github.com/libp2p/go-libp2p/core/host"
	peer "github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
	"go.uber.org/zap"
)

type P2PService struct {
	ctx            context.Context
	log            *zap.Logger
	host           host.Host
	kdht           *dht.IpfsDHT
	cancel         context.CancelFunc
	bootstrapPeers []peer.AddrInfo
}

func New(ctx context.Context, log *zap.Logger, listenPort int, bootstrap []string) (*P2PService, error) {
	listenAddr, _ := ma.NewMultiaddr(fmt.Sprintf("/ip4/0.0.0.0/tcp/%d", listenPort))
	h, err := libp2p.New(libp2p.ListenAddrs(listenAddr))
	if err != nil {
		return nil, fmt.Errorf("failed to create libp2p host: %w", err)
	}

	kctx, cancel := context.WithCancel(ctx)
	kdht, err := dht.New(kctx, h)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("failed to create DHT: %w", err)
	}

	// Parse bootstrap peers
	var peers []peer.AddrInfo
	for _, addr := range bootstrap {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			log.Warn("invalid bootstrap address", zap.String("addr", addr))
			continue
		}
		pi, err := peer.AddrInfoFromP2pAddr(maddr)
		if err == nil {
			peers = append(peers, *pi)
		}
	}

	return &P2PService{
		ctx:            kctx,
		log:            log,
		host:           h,
		kdht:           kdht,
		cancel:         cancel,
		bootstrapPeers: peers,
	}, nil
}

func (p *P2PService) Name() string { return "p2p" }

func (p *P2PService) Start(ctx context.Context) error {
	p.log.Info("Starting P2P subsystem", zap.String("id", p.host.ID().String()))
	if err := p.kdht.Bootstrap(p.ctx); err != nil {
		return err
	}

	for _, bp := range p.bootstrapPeers {
		if err := p.host.Connect(p.ctx, bp); err != nil {
			p.log.Warn("Failed to connect bootstrap peer", zap.String("peer", bp.ID.String()), zap.Error(err))
		} else {
			p.log.Info("Connected bootstrap peer", zap.String("peer", bp.ID.String()))
		}
	}

	proto := NewProtocol(p.ctx, p.log, p.host)

	proto.RegisterHandler(MsgTypeServiceQuery, func(ctx context.Context, from peer.ID, msg *Message) {
		var q ServiceQuery
		json.Unmarshal(msg.Data, &q)

		providers, _ := p.kdht.GetValue(ctx, "service:"+q.ServiceID)
		_ = proto.SendMessage(ctx, from, MsgTypeServiceResponse, ServiceResponse{
			ServiceID: q.ServiceID,
			Providers: []string{string(providers)},
		})
	})

	proto.RegisterHandler(MsgTypePing, func(ctx context.Context, from peer.ID, msg *Message) {
		_ = proto.SendMessage(ctx, from, MsgTypePong, map[string]string{"ok": "true"})
	})

	go p.run()
	return nil
}

func (p *P2PService) run() {
	for {
		select {
		case <-p.ctx.Done():
			return
		}
	}
}

func (p *P2PService) Stop() error {
	p.log.Info("Stopping P2P subsystem")
	p.cancel()
	if err := p.host.Close(); err != nil {
		return err
	}
	return nil
}

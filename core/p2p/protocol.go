package p2p

import (
	"bufio"
	"context"
	"io"
	"strings"

	host "github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	peer "github.com/libp2p/go-libp2p/core/peer"
	protocol "github.com/libp2p/go-libp2p/core/protocol"
	"go.uber.org/zap"
)

const ProtocolID = protocol.ID("/provider-network/1.0.0")

type HandlerFunc func(ctx context.Context, from peer.ID, msg *Message)

type Protocol struct {
	ctx      context.Context
	log      *zap.Logger
	host     host.Host
	handlers map[MessageType]HandlerFunc
}

func NewProtocol(ctx context.Context, log *zap.Logger, h host.Host) *Protocol {
	p := &Protocol{
		ctx:      ctx,
		log:      log,
		host:     h,
		handlers: make(map[MessageType]HandlerFunc),
	}
	h.SetStreamHandler(ProtocolID, p.handleStream)
	return p
}

func (p *Protocol) RegisterHandler(msgType MessageType, handler HandlerFunc) {
	p.handlers[msgType] = handler
}

func (p *Protocol) SendMessage(ctx context.Context, to peer.ID, msgType MessageType, data any) error {
	s, err := p.host.NewStream(ctx, to, ProtocolID)
	if err != nil {
		return err
	}
	defer s.Close()

	payload, err := EncodeMessage(msgType, data)
	if err != nil {
		return err
	}

	_, err = s.Write(append(payload, '\n'))
	return err
}

func (p *Protocol) handleStream(s network.Stream) {
	defer s.Close()
	from := s.Conn().RemotePeer()
	reader := bufio.NewReader(s)

	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			if err != io.EOF && !strings.Contains(err.Error(), "closed") {
				p.log.Warn("stream read error", zap.Error(err))
			}
			return
		}

		msg, err := DecodeMessage(line)
		if err != nil {
			p.log.Warn("failed to decode message", zap.Error(err))
			continue
		}

		handler, ok := p.handlers[msg.Type]
		if ok {
			go handler(p.ctx, from, msg)
		} else {
			p.log.Debug("no handler for message", zap.String("type", string(msg.Type)))
		}
	}
}

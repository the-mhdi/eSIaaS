package docs

import (
	"github.com/ethereum/go-ethereum/p2p"
)

type node interface {
	Type() string //gateway / worker

}

//type Worker struct {
//
//}

type Gateway struct {
	config   *GatewayConfig
	Server   *p2p.Server
	endpoint *servers
}

func NewGateway(conf *GatewayConfig) (*Gateway, error) {
	node := &Gateway{
		config: conf,
		Server: &p2p.Server{},
	}

	return node, nil
}

func (g *Gateway) Start() error {
	g.Server.PrivateKey = g.config.NodeKey()

	return g.Server.Start()
}

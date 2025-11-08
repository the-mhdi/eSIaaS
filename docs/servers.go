package docs

import (
	"net"
	"sync"
)

type servers struct {
	http *httpServer
	tcp  *tcpServer
}

type httpServer struct {
	mu       sync.Mutex
	listener net.Listener // non-nil when server is running
	endpoint string
	host     string
	port     int
}

type tcpServer struct {
	mu       sync.Mutex
	listener net.Listener // non-nil when server is running
	endpoint string
	host     string
	port     int
}

package p2p

import (
	"encoding/json"
	"fmt"
)

type MessageType string

const (
	MsgTypePing            MessageType = "ping"
	MsgTypePong            MessageType = "pong"
	MsgTypeServiceAnnounce MessageType = "service_announce"
	MsgTypeServiceQuery    MessageType = "service_query"
	MsgTypeServiceResponse MessageType = "service_response"
)

type Message struct {
	Type MessageType     `json:"type"`
	Data json.RawMessage `json:"data"`
}

// Example payloads
type ServiceAnnounce struct {
	ServiceID string   `json:"service_id"`
	Addresses []string `json:"addresses"`
}

type ServiceQuery struct {
	ServiceID string `json:"service_id"`
}

type ServiceResponse struct {
	ServiceID string   `json:"service_id"`
	Providers []string `json:"providers"`
}

// Serialize
func EncodeMessage(msgType MessageType, data any) ([]byte, error) {
	b, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}
	envelope := Message{
		Type: msgType,
		Data: b,
	}
	return json.Marshal(envelope)
}

// Deserialize
func DecodeMessage(b []byte) (*Message, error) {
	var m Message
	if err := json.Unmarshal(b, &m); err != nil {
		return nil, fmt.Errorf("decode failed: %w", err)
	}
	return &m, nil
}

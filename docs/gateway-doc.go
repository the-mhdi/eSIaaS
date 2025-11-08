package docs

/*

User sends/receives arbitrary binary data (raw TCP).

Gateway Node is the only public endpoint.

Execution Node and containers are private.

Gateway must forward both directions transparently, like a reverse TCP proxy or VPN tunnel.

*******************************************************************************

************ gateways support to types of protocols for routing http and raw tcp with custom “handshake” message" ******************

for routing raw tcp connections: Flow is :

1. User requests a “connection ticket” from your Registry API:

{
  "gateway": "gateway.com:9000",
  "containerID": "game-server-A",
  "token": "signed-short-lived-jwt"
}


2.the client connects via TCP to the Gateway (always same port, e.g. 9000).

3. On connection start, the client sends a small header:

<len=32><containerID><len=256><authToken>\n


4. The Gateway reads those first bytes, validates the token, and looks up which Execution Node hosts that container.

5. Gateway connects to Execution Node and pipes the rest of the stream transparently.
******************************************************************************





1. keeps track of worker nodes in a distributed system.
2. allows adding and removing worker nodes.
3. maintainance and consensus over a trie of active worker nodes.
4. routes tasks to worker nodes based on their list of active containers, there's a algorithm to select the suitable worker node, node changes each time a new task is assigned.

	CHALLANGES:
	1. what if the note routed the request to a worker node A then another related request is routed to worker node B, how to maintain state across multiple worker nodes?
	2. how to ensure worker nodes are active and healthy and reputable?



*/

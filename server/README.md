## Minimal Authoritative Server (Node + WebSockets)

This is a **minimal dev skeleton**, not production-hardened.
- In-memory rooms/tokens (process restart resets everything)
- 2 players per room (A/B)
- WebSocket accepts `intent` messages and broadcasts `patch`/`state`
- Turn timer is server-owned (60s) and auto-ends turn on timeout

### Requirements
- Node.js (tested with modern Node)

### Run locally
From repo root:

```bash
cd server
npm install
npm run dev
```

Server defaults:
- HTTP: `http://localhost:8787`
- WS: `ws://localhost:8787/ws?token=...`

### Create + join a room

Create (Player A):

```bash
curl -s -X POST http://localhost:8787/room/create
```

Join (Player B):

```bash
curl -s -X POST http://localhost:8787/room/join \
  -H 'content-type: application/json' \
  -d '{"room_code":"K4J9Q2"}'
```

### Protocol
See `docs/networking-protocol.md`.

### What’s stubbed
- Real authoritative sim for `melee` / `ranged` (currently accepted and echoed as `_last_intent` patch only)
- Rich move validation (pathfinding, occupancy, terrain rules) — current slice allows any in-bounds move and patches `state.squads[]`
- Reconnect/backfill beyond sending an initial `state` snapshot on connect

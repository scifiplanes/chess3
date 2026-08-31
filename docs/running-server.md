## Running the Server Locally

The repo includes a minimal Node.js authoritative server in `server/`.

### Start

```bash
cd server
npm install
npm run dev
```

### Endpoints
- `POST /room/create` → `{ room_code, token, player }`
- `POST /room/join` with `{ room_code }` → `{ room_code, token, player }`
- WebSocket: `ws://localhost:8787/ws?token=...`

### Protocol spec
See `docs/networking-protocol.md`.

### Multiplayer vertical slice
See `docs/running-multiplayer.md` for running two Godot clients against the local server.

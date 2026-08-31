## Authoritative Networking Protocol (v0)

This game uses **server-authoritative** simulation over WebSockets.
- Clients send **intents** (what the player wants to do).
- Server validates and applies intents, then broadcasts **authoritative updates** as `patch` deltas (and occasional full `state` snapshots).

This spec is intentionally minimal and geared to the MVP.

### Transport
- **HTTP** (JSON): create/join rooms to obtain tokens.
- **WebSocket** (JSON): match socket for intents + state updates.

### Identity + rooms
- A match is identified by a `room_code` (short, shareable).
- Joining the WebSocket requires a **bearer token** issued by the server for that room.
- Only **two** players are allowed (Player A / Player B).

### Ordering, dedupe, determinism
- Each intent has a client-local monotonically increasing `seq` integer.
- Server replies with authoritative `server_seq` (monotonic per connection) and a `state_version` (monotonic per room).
- Server may reject intents with a structured error; rejected intents do not advance state.

### Common envelope
All WS messages are JSON objects with:
- `t`: string message type
- `room`: `room_code` (optional on some server->client messages; included in examples for clarity)
- `ts`: server timestamp (ms since epoch) on server->client messages

### HTTP endpoints (minimal)

#### `POST /room/create`
Request:
- (no body) or `{ "client": { ... } }` (ignored by server in v0)

Response:
```json
{
  "room_code": "K4J9Q2",
  "token": "tok_...playerA...",
  "player": "A"
}
```

#### `POST /room/join`
Request:
```json
{ "room_code": "K4J9Q2" }
```

Response:
```json
{
  "room_code": "K4J9Q2",
  "token": "tok_...playerB...",
  "player": "B"
}
```

Errors (both endpoints):
```json
{ "error": { "code": "ROOM_NOT_FOUND", "message": "..." } }
```

### WebSocket connect
Connect to:
- `ws://localhost:8787/ws?token=...`

On connect, the server sends a `hello` and then a `state` snapshot.

#### `hello` (server -> client)
```json
{
  "t": "hello",
  "room": "K4J9Q2",
  "ts": 1710000000000,
  "player": "A",
  "server_seq": 1,
  "state_version": 0
}
```

#### `state` snapshot (server -> client)
Sent on connect and may be resent for resync/reconnect.
```json
{
  "t": "state",
  "room": "K4J9Q2",
  "ts": 1710000000100,
  "server_seq": 2,
  "state_version": 0,
  "state": {
    "turn": 1,
    "active_player": "A",
    "phase": "action",
    "turn_ends_at_ms": 1710000060000,
    "board": { "w": 14, "h": 14 },
    "squads": [
      { "id": 1, "owner": "A", "cell": { "x": 2, "y": 2 } },
      { "id": 2, "owner": "A", "cell": { "x": 2, "y": 4 } },
      { "id": 3, "owner": "B", "cell": { "x": 11, "y": 11 } },
      { "id": 4, "owner": "B", "cell": { "x": 11, "y": 9 } }
    ],
    "control_points": []
  }
}
```

### Client -> server intents
All intents share:
- `t`: `intent`
- `seq`: client monotonic integer (per token/connection)
- `turn`: client’s view of `turn` (server rejects if mismatched)
- `intent`: intent payload object with `k` kind + fields

#### `intent` (client -> server)
```json
{
  "t": "intent",
  "seq": 12,
  "turn": 3,
  "intent": { "k": "end_turn" }
}
```

Supported `intent.k` (v0; matches Godot `NetworkClient.send_intent` + `ReplayDriver` names where applicable):

- `end_turn` — no extra fields.
- `move` — `{ "squad_id": number, "to": { "x", "y" } }` (in-bounds empty destination; server v0 does not run full pathing).
- `run` | `jump` | `blink` | `dash` | `pounce` — same payload as `move` (server updates that squad’s `cell` the same way as `move`).
- `switch` — `{ "caster_id", "squad_a", "squad_b" }` (numeric squad ids; server swaps the two squads’ cells if all are owned by the active player).
- `delayed` — `{ "effect": { ... } }` one scheduled effect object (same shape as `GameState.pending_effects[]` entries: `id`, `resolve_at_turn`, `kind`, `payload` with `cx`/`cy`/…). Optional `next_pending_id` (number).
- `plant` — `{ "hazard": { "cell": { "x", "y" }, "kind", "owner", "damage", "splash" } }` (appended to authoritative `board.hazards` list).
- `attack` — `{ "attacker_id", "defender_id", "kind" }` (client); **stub** on server (no HP change).
- `attack_obstacle` — `{ "attacker_id", "cell", "kind" }`; **stub** on server.
- `melee` | `ranged` — legacy names; **stub** on server (listed for older docs; prefer `attack` with `kind` in the client).

### Server -> client updates

#### `patch` (server -> clients)
Primary update mechanism; a list of operations applied to the last known state.

Operations are intentionally simple in v0:
- `set`: set a JSON-pointer-like path to a value
- `inc`: add integer to a path
- `push`: append to an array path

Example:
```json
{
  "t": "patch",
  "room": "K4J9Q2",
  "ts": 1710000000200,
  "server_seq": 5,
  "state_version": 4,
  "ops": [
    { "op": "set", "path": "/active_player", "value": "B" },
    { "op": "inc", "path": "/turn", "value": 1 },
    { "op": "set", "path": "/turn_ends_at_ms", "value": 1710000060200 }
  ]
}
```

The server may also send a `state` snapshot instead of a patch (e.g. for resync).

#### `error` (server -> client)
Used for rejected intents or protocol errors.
```json
{
  "t": "error",
  "ts": 1710000000300,
  "server_seq": 6,
  "ref_seq": 12,
  "error": { "code": "TURN_MISMATCH", "message": "Expected turn 4." }
}
```

### Turn timer (60s hard timeout)
- Server is the time source (`turn_ends_at_ms` in snapshots/patches).
- When time expires, the server applies `end_turn` automatically and broadcasts a `patch`.

### Notes / non-goals (v0)
- No reconnect token refresh; reconnect uses the same token.
- No persistence; rooms live in memory.
- No production security hardening.

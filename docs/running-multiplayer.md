## Multiplayer Vertical Slice (Godot + Node)

This repo now includes a minimal end-to-end slice:
- Godot client: HTTP create/join room → WebSocket connect → send intents → apply `state`/`patch`
- Node server: in-memory rooms + tokens + authoritative `end_turn` + authoritative `move`

### 1) Run the server

```bash
cd server
npm install
npm run dev
```

Default base URL: `http://localhost:8787`

### 2) Run two Godot clients

Networking mode is enabled via command line args on the Godot app:
- Player A (creates a room): `--net=create`
- Player B (joins a room): `--net=join:ROOMCODE`
- Optional: `--server=http://localhost:8787`

#### Player A
- Run the game with `--net=create`
- The HUD top bar will show `Room XXXXXX | You A`

#### Player B
- Copy the room code shown in Player A
- Run the game with `--net=join:ROOMCODE`
- The HUD top bar will show `Room XXXXXX | You B`

### 3) Test steps

- **End turn**: Press HUD `End Turn` on the active player window
  - Both clients should update turn + active player from server `patch`
- **Move**:
  - Click a squad to select it
  - Press HUD `Move`
  - Click any in-bounds cell (server slice currently allows any in-bounds move)
  - Both clients should see that squad move to the new cell (authoritative server `patch`)

### Notes / limitations (intentional for slice)
- Authoritative sim only covers `end_turn` and a simplified `move`
- `melee` / `ranged` intents are accepted but do not change state yet
- Board terrain/obstacles are still locally generated; server move validation does not consider them yet


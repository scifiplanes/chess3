import http from "node:http";
import crypto from "node:crypto";
import { WebSocketServer } from "ws";

const PORT = Number.parseInt(process.env.PORT ?? "8787", 10);
const TURN_MS = 60_000;

/** @typedef {"A"|"B"} Player */

function json(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => {
      data += chunk;
      if (data.length > 1_000_000) reject(new Error("body_too_large"));
    });
    req.on("end", () => {
      if (!data) return resolve({});
      try {
        resolve(JSON.parse(data));
      } catch {
        reject(new Error("invalid_json"));
      }
    });
  });
}

function randomCode() {
  // 6 chars, uppercase base32-ish, readable
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let out = "";
  for (let i = 0; i < 6; i++) out += alphabet[crypto.randomInt(0, alphabet.length)];
  return out;
}

function randomToken() {
  return `tok_${crypto.randomBytes(24).toString("base64url")}`;
}

function now() {
  return Date.now();
}

function err(code, message) {
  return { error: { code, message } };
}

/**
 * Room memory model (v0):
 * - in-memory only
 * - 2 players max (A/B)
 * - state is a small JSON object
 */
class Room {
  /** @param {string} code */
  constructor(code) {
    this.code = code;
    /** @type {Map<string, {player: Player}>} */
    this.tokens = new Map();
    /** @type {Map<Player, import("ws").WebSocket>} */
    this.sockets = new Map();

    this.stateVersion = 0;
    this.turnTimer = null;
    this.serverSeq = 0;

    this.state = {
      turn: 1,
      active_player: "A",
      phase: "action",
      turn_ends_at_ms: now() + TURN_MS,
      board: { w: 14, h: 14, hazards: [] },
      // Minimal authoritative slice state:
      // - squads are an array; patches address them by index
      // - each squad has numeric id to align with Godot offline ids
      squads: [
        { id: 1, owner: "A", cell: { x: 2, y: 2 } },
        { id: 2, owner: "A", cell: { x: 2, y: 4 } },
        { id: 3, owner: "B", cell: { x: 11, y: 11 } },
        { id: 4, owner: "B", cell: { x: 11, y: 9 } },
      ],
      control_points: [],
      pending_effects: [],
      next_pending_id: 1,
    };
  }

  /** @returns {Player|null} */
  nextOpenSeat() {
    const hasA = [...this.tokens.values()].some((t) => t.player === "A");
    const hasB = [...this.tokens.values()].some((t) => t.player === "B");
    if (!hasA) return "A";
    if (!hasB) return "B";
    return null;
  }

  /** @param {Player} player */
  issueToken(player) {
    const token = randomToken();
    this.tokens.set(token, { player });
    return token;
  }

  /** @param {string} token */
  playerForToken(token) {
    return this.tokens.get(token)?.player ?? null;
  }

  bumpVersion() {
    this.stateVersion += 1;
  }

  nextServerSeq() {
    this.serverSeq += 1;
    return this.serverSeq;
  }

  startTurnTimer() {
    if (this.turnTimer) clearTimeout(this.turnTimer);
    const deadline = now() + TURN_MS;
    this.state.turn_ends_at_ms = deadline;
    this.turnTimer = setTimeout(() => {
      this.applyEndTurn({ reason: "timeout" });
    }, TURN_MS);
  }

  /** @param {{reason:"intent"|"timeout"}} meta */
  applyEndTurn(meta) {
    this.state.turn += 1;
    this.state.active_player = this.state.active_player === "A" ? "B" : "A";
    this.bumpVersion();
    this.startTurnTimer();

    this.broadcastPatch([
      { op: "inc", path: "/turn", value: 1 },
      { op: "set", path: "/active_player", value: this.state.active_player },
      { op: "set", path: "/turn_ends_at_ms", value: this.state.turn_ends_at_ms },
      { op: "set", path: "/_last_end_turn_reason", value: meta.reason },
    ]);
  }

  /**
   * @param {Player} actor
   * @param {{squad_id:number,to:{x:number,y:number}}} payload
   * @returns {{ok:true, ops:any[]} | {ok:false, code:string, message:string}}
   */
  applyMove(actor, payload) {
    const squadId = Number.isInteger(payload?.squad_id) ? payload.squad_id : null;
    const toX = Number.isInteger(payload?.to?.x) ? payload.to.x : null;
    const toY = Number.isInteger(payload?.to?.y) ? payload.to.y : null;
    if (squadId === null || toX === null || toY === null) {
      return { ok: false, code: "BAD_MOVE", message: "Missing/invalid squad_id or to.{x,y}." };
    }

    const idx = this.state.squads.findIndex((s) => s?.id === squadId);
    if (idx === -1) return { ok: false, code: "SQUAD_NOT_FOUND", message: "Unknown squad_id." };
    const squad = this.state.squads[idx];
    if (squad.owner !== actor) return { ok: false, code: "NOT_YOUR_SQUAD", message: "Cannot move opponent squad." };

    const w = Number(this.state.board?.w ?? 14);
    const h = Number(this.state.board?.h ?? 14);
    if (toX < 0 || toY < 0 || toX >= w || toY >= h) {
      return { ok: false, code: "OUT_OF_BOUNDS", message: "Target cell out of bounds." };
    }

    // Minimal slice rule: allow any in-bounds move (no pathing/occupancy yet).
    squad.cell = { x: toX, y: toY };
    this.bumpVersion();

    return {
      ok: true,
      ops: [
        { op: "set", path: `/squads/${idx}/cell`, value: squad.cell },
        { op: "set", path: "/_last_move", value: { by: actor, squad_id: squadId, to: squad.cell } },
      ],
    };
  }

  /**
   * @param {Player} actor
   * @param {{caster_id:number,squad_a:number,squad_b:number}} payload
   */
  applySwitch(actor, payload) {
    const casterId = Number.isInteger(payload?.caster_id) ? payload.caster_id : null;
    const aId = Number.isInteger(payload?.squad_a) ? payload.squad_a : null;
    const bId = Number.isInteger(payload?.squad_b) ? payload.squad_b : null;
    if (casterId === null || aId === null || bId === null) {
      return { ok: false, code: "BAD_SWITCH", message: "Missing caster_id or squad_a/squad_b." };
    }
    const ixC = this.state.squads.findIndex((s) => s?.id === casterId);
    const ixA = this.state.squads.findIndex((s) => s?.id === aId);
    const ixB = this.state.squads.findIndex((s) => s?.id === bId);
    if (ixC === -1 || ixA === -1 || ixB === -1) {
      return { ok: false, code: "SQUAD_NOT_FOUND", message: "Unknown squad id in switch." };
    }
    const caster = this.state.squads[ixC];
    const sa = this.state.squads[ixA];
    const sb = this.state.squads[ixB];
    if (caster.owner !== actor || sa.owner !== actor || sb.owner !== actor) {
      return { ok: false, code: "NOT_YOUR_SQUAD", message: "Switch targets must be yours." };
    }
    const tmp = { ...sa.cell };
    sa.cell = { ...sb.cell };
    sb.cell = tmp;
    this.bumpVersion();
    return {
      ok: true,
      ops: [
        { op: "set", path: `/squads/${ixA}/cell`, value: sa.cell },
        { op: "set", path: `/squads/${ixB}/cell`, value: sb.cell },
      ],
    };
  }

  /** @param {any[]} ops */
  broadcastPatch(ops) {
    const msg = {
      t: "patch",
      room: this.code,
      ts: now(),
      server_seq: this.nextServerSeq(),
      state_version: this.stateVersion,
      ops,
    };
    const payload = JSON.stringify(msg);
    for (const ws of this.sockets.values()) {
      if (ws.readyState === ws.OPEN) ws.send(payload);
    }
  }

  /** @param {Player} player */
  sendHelloAndState(player) {
    const ws = this.sockets.get(player);
    if (!ws) return;

    const hello = {
      t: "hello",
      room: this.code,
      ts: now(),
      player,
      server_seq: this.nextServerSeq(),
      state_version: this.stateVersion,
    };
    ws.send(JSON.stringify(hello));

    const snapshot = {
      t: "state",
      room: this.code,
      ts: now(),
      server_seq: this.nextServerSeq(),
      state_version: this.stateVersion,
      state: this.state,
    };
    ws.send(JSON.stringify(snapshot));
  }
}

/** @type {Map<string, Room>} */
const rooms = new Map();

function createRoom() {
  for (let i = 0; i < 10; i++) {
    const code = randomCode();
    if (!rooms.has(code)) {
      const room = new Room(code);
      room.startTurnTimer();
      rooms.set(code, room);
      return room;
    }
  }
  throw new Error("failed_to_generate_room_code");
}

function parseUrl(req) {
  const u = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);
  return u;
}

const server = http.createServer(async (req, res) => {
  try {
    const u = parseUrl(req);

    if (req.method === "GET" && u.pathname === "/health") {
      return json(res, 200, { ok: true });
    }

    if (req.method === "POST" && u.pathname === "/room/create") {
      // Read body for forward compatibility (ignored)
      await readJson(req).catch(() => ({}));
      const room = createRoom();
      const token = room.issueToken("A");
      return json(res, 200, { room_code: room.code, token, player: "A" });
    }

    if (req.method === "POST" && u.pathname === "/room/join") {
      const body = await readJson(req);
      const roomCode = String(body.room_code ?? "").trim().toUpperCase();
      const room = rooms.get(roomCode);
      if (!room) return json(res, 404, err("ROOM_NOT_FOUND", "Room not found."));

      const seat = room.nextOpenSeat();
      if (!seat) return json(res, 409, err("ROOM_FULL", "Room already has 2 players."));

      const token = room.issueToken(seat);
      return json(res, 200, { room_code: room.code, token, player: seat });
    }

    return json(res, 404, err("NOT_FOUND", "Unknown endpoint."));
  } catch (e) {
    return json(res, 500, err("INTERNAL", e instanceof Error ? e.message : "internal_error"));
  }
});

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const u = parseUrl(req);
  if (u.pathname !== "/ws") {
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit("connection", ws, req, u);
  });
});

/** @param {import("ws").WebSocket} ws */
function safeSend(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

wss.on("connection", (ws, req, u) => {
  const token = u.searchParams.get("token") ?? "";
  let room = null;
  let player = null;
  for (const r of rooms.values()) {
    const p = r.playerForToken(token);
    if (p) {
      room = r;
      player = p;
      break;
    }
  }

  if (!room || !player) {
    safeSend(ws, { t: "error", ts: now(), server_seq: 0, error: { code: "BAD_TOKEN", message: "Invalid token." } });
    ws.close();
    return;
  }

  // Replace existing connection for that seat.
  room.sockets.set(player, ws);
  room.sendHelloAndState(player);

  ws.on("message", (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString("utf-8"));
    } catch {
      safeSend(ws, { t: "error", ts: now(), server_seq: room.nextServerSeq(), error: { code: "BAD_JSON", message: "Invalid JSON." } });
      return;
    }

    // Only one client->server message type in v0.
    if (msg?.t !== "intent") {
      safeSend(ws, {
        t: "error",
        ts: now(),
        server_seq: room.nextServerSeq(),
        error: { code: "BAD_MESSAGE", message: "Expected {t:'intent'}." },
      });
      return;
    }

    const refSeq = Number.isInteger(msg.seq) ? msg.seq : null;
    const turn = Number.isInteger(msg.turn) ? msg.turn : null;
    const intent = msg.intent ?? null;

    if (refSeq === null || turn === null || !intent || typeof intent.k !== "string") {
      safeSend(ws, {
        t: "error",
        ts: now(),
        server_seq: room.nextServerSeq(),
        ref_seq: refSeq ?? undefined,
        error: { code: "BAD_INTENT", message: "Missing/invalid seq, turn, or intent." },
      });
      return;
    }

    if (turn !== room.state.turn) {
      safeSend(ws, {
        t: "error",
        ts: now(),
        server_seq: room.nextServerSeq(),
        ref_seq: refSeq,
        error: { code: "TURN_MISMATCH", message: `Expected turn ${room.state.turn}.` },
      });
      return;
    }

    if (player !== room.state.active_player) {
      safeSend(ws, {
        t: "error",
        ts: now(),
        server_seq: room.nextServerSeq(),
        ref_seq: refSeq,
        error: { code: "NOT_YOUR_TURN", message: "Not your turn." },
      });
      return;
    }

    // Minimal intent handling (movement matches slice rules; combat still stubbed).
    switch (intent.k) {
      case "end_turn": {
        room.applyEndTurn({ reason: "intent" });
        return;
      }
      case "move":
      case "run":
      case "jump":
      case "blink":
      case "dash":
      case "pounce": {
        const res = room.applyMove(player, intent);
        if (!res.ok) {
          safeSend(ws, {
            t: "error",
            ts: now(),
            server_seq: room.nextServerSeq(),
            ref_seq: refSeq,
            error: { code: res.code, message: res.message },
          });
          return;
        }
        room.broadcastPatch(res.ops);
        return;
      }
      case "switch": {
        const res = room.applySwitch(player, intent);
        if (!res.ok) {
          safeSend(ws, {
            t: "error",
            ts: now(),
            server_seq: room.nextServerSeq(),
            ref_seq: refSeq,
            error: { code: res.code, message: res.message },
          });
          return;
        }
        room.broadcastPatch(res.ops);
        return;
      }
      case "delayed": {
        const eff = intent.effect;
        if (!eff || typeof eff !== "object") {
          safeSend(ws, {
            t: "error",
            ts: now(),
            server_seq: room.nextServerSeq(),
            ref_seq: refSeq,
            error: { code: "BAD_EFFECT", message: "delayed intent requires effect object." },
          });
          return;
        }
        if (!room.state.pending_effects) room.state.pending_effects = [];
        room.state.pending_effects.push(eff);
        if (Number.isInteger(intent.next_pending_id)) {
          room.state.next_pending_id = intent.next_pending_id;
        }
        room.bumpVersion();
        room.broadcastPatch([
          { op: "set", path: "/pending_effects", value: [...room.state.pending_effects] },
          { op: "set", path: "/next_pending_id", value: room.state.next_pending_id },
        ]);
        return;
      }
      case "plant": {
        const hz = intent.hazard;
        if (!hz || typeof hz !== "object") {
          safeSend(ws, {
            t: "error",
            ts: now(),
            server_seq: room.nextServerSeq(),
            ref_seq: refSeq,
            error: { code: "BAD_HAZARD", message: "plant intent requires hazard object." },
          });
          return;
        }
        if (!room.state.board.hazards) room.state.board.hazards = [];
        room.state.board.hazards.push(hz);
        room.bumpVersion();
        room.broadcastPatch([{ op: "set", path: "/board/hazards", value: [...room.state.board.hazards] }]);
        return;
      }
      case "attack":
      case "attack_obstacle": {
        room.bumpVersion();
        room.broadcastPatch([{ op: "set", path: "/_last_intent", value: { from: player, seq: refSeq, intent } }]);
        return;
      }
      case "melee":
      case "ranged": {
        // Still stubbed: accept but do not mutate sim state yet.
        room.bumpVersion();
        room.broadcastPatch([{ op: "set", path: "/_last_intent", value: { from: player, seq: refSeq, intent } }]);
        return;
      }
      default: {
        safeSend(ws, {
          t: "error",
          ts: now(),
          server_seq: room.nextServerSeq(),
          ref_seq: refSeq,
          error: { code: "UNKNOWN_INTENT", message: `Unknown intent kind '${intent.k}'.` },
        });
      }
    }
  });

  ws.on("close", () => {
    const cur = room.sockets.get(player);
    if (cur === ws) room.sockets.delete(player);
  });
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`[server] listening on http://localhost:${PORT}`);
  // eslint-disable-next-line no-console
  console.log(`[server] ws endpoint ws://localhost:${PORT}/ws?token=...`);
});


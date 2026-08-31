# Game Design (Concise)

## Vision
- **Core**: Turn-based tactics on a **3D voxel board** with **2D sprite squads**.
- **Feel**: Readable, snappy, deterministic tactics with light procedural variety.

## Prototype → New Game Mapping
- **Grid**: Keep square grid gameplay; render in 3D with voxel ground + voxel obstacles.
- **Entities**: Replace “creatures” with **Squads** composed of **Units**.
- **UI loop**: Select squad/unit → choose action → select target → resolve → end turn.

## Core Rules (MVP)
- **Players**: 2 players, alternating turns.
- **Determinism**: No RNG in combat/movement resolution; randomness only in draft/offers (if used).
- **Turn structure** (candidate from prototype):
  - Offer phase → placement/upgrade phase → action phase → end turn (tick cooldowns/effects, resolve delayed effects).
- **MVP (current implementation)**:
  - **Offer phase (offline, minimal)**:
    - At the start of each turn, the active player gets a **3-card offer** (+ Skip).
    - Player plays **1 card** (spawn or reinforce) or **skips**, then proceeds with normal actions.
    - Offer card targeting **defaults to spawn** when spawn is legal; it switches to **reinforce** when reinforce is legal **and** spawn isn’t, **or** when you’ve selected an owned squad in a **reinforceable zone** (home deployment band or CP) that can legally reinforce that card.
    - Offers are **deterministic** from a match seed + turn number.
  - **Board size**: 14×14 (~1.5× former 9×9 edge length; same 1-unit cells).
  - **Movement**: **always the entire squad** — one piece per squad cell; units never move or occupy cells independently. Orthogonal BFS up to range 3; blocked/occupied cells are not enterable. **Basic Move is once per squad per turn**; movement abilities (Run/Blink/…) remain cooldown-gated.
  - **Actions** (deterministic, data-driven per unit def):
    - Actions live on `UnitDefs` as `actions[action_id]` with `{ id, kind, range, damage, cooldown, type, tags?, … }`. **`kind`** selects resolver behavior (melee/ranged, Run/Blink/Dash, delayed strikes, traps, Switch, etc.).
    - HUD **Move** + **End Turn** are fixed; **ability buttons** are built from the selected squad’s front unit `actions` keys (each unit type defines its own loadout).
    - **Availability cues**: active-player squads with a remaining basic Move show a **cyan** ring; squads with any ability off cooldown show an **amber** ring. When neither remains, **End Turn** is highlighted.
  - **Optional action fields** (backwards compatible):
    - `aoe_radius`: splash radius around defender cell (Manhattan).
    - `aoe_splash`: splash damage applied to each additional enemy squad hit.
    - `self_move: "dash_adjacent"`: attacker dashes to an empty cell adjacent to defender before dealing damage (deterministic landing).
    - `obstacle_bonus`: added damage when targeting destructible obstacles.
- **Board**:
  - Voxel tiles with terrain types (e.g. soil/rock/sand) and blocked voxel obstacles.
  - Control Points (CPs) placed on the board; each has an owner state.
- **Terrain identity** (candidate from prototype):
  - Soil: melee/defence/growth/mobility bias
  - Rock: heavy/armor/ranged bias
  - Sand: mobility/blink/traps/eruption bias
  - **Implemented now (MVP combat modifiers)**:
    - **Soil**: +1 melee damage (attacker standing on Soil).
    - **Rock**: +1 ranged damage (attacker standing on Rock).
    - **Sand**: no combat modifier yet (reserved for mobility/utility).
  - **Implemented now (MVP utility modifiers)**:
    - **Sand**: +1 move range (squad standing on Sand).
    - **Rock**: -1 incoming ranged damage (defender standing on Rock; min damage 1).
    - **Soil**: +1 HP regen to front unit at end of turn (squad standing on Soil; capped by unit max HP).
- **Obstacles** (candidate from prototype): ~12% impassable voxels, excluded from start zones and near centre.
  - Some obstacles are **destructible** (block movement until destroyed).
  - **Current implementation (seeded generation)**:
    - Terrain: per-cell sampling with simple weights (Soil most common; Rock/Sand sprinkled).
    - Obstacles: target density ~12% of cells, placed deterministically from a seeded candidate list.
    - Exclusions: no obstacles in home spawn rows (top/bottom), and no obstacles within Manhattan distance 1 of the center cell or any CP.
    - Playability guarantees: generator carves a clear lane from each home band toward the CP row and prevents CPs from being fully walled in.
  - **Implemented now (MVP interaction)**: melee/ranged can target destructible obstacles (within range) to reduce obstacle HP; at 0 HP the cell becomes passable.
- **Squads / Units**:
  - A **Squad** is the primary selectable piece.
  - A Squad contains 1..N **Units**; Units are 2D sprites anchored to a 3D cell.
  - A Squad occupies a cell; Units are represented visually as a stack/row over that cell (MVP: **emoji labels** per alive unit; replaceable with textured sprites later).
  - **Movement never splits squads**: all movement abilities relocate the **whole squad** to another cell; individual units do not have separate board positions.
  - **Per-squad composition cap**: each squad can hold **up to 3 small-class units + 1 large-class unit** (at most **4** alive units in one cell).
  - When a squad is **full**, that card play **reinforces/heals** in **reinforcement zones** (home deployment rows and/or CP) instead of adding another unit.
  - **Alive**: a squad is alive if **any unit** in it has HP > 0.
  - **Targeting**: attacks hit the squad’s **front alive unit** (first alive unit in `units[]`).
- **Actions**:
  - Actions have **range**, **targeting rule**, and **cooldown** (turn-based).
  - **Unit roster (content MVP)**:
    - `soldier`: baseline melee + ranged.
    - `archer`: baseline melee + ranged (lower HP).
    - `tank`: high HP brawler; strong melee, weak short-ranged shot.
    - `mage`: fragile; ranged attack splashes nearby enemy squads (AoE).
    - `rogue`: dash strike melee (range 2; dashes adjacent) for reach/picks.
    - `bomber`: demolition ranged shot; strong vs obstacles via `obstacle_bonus`, weak vs squads.
- **No action points**: Abilities are limited by per-action cooldowns and target legality (multiple abilities OK if ready). **Basic Move** is limited to **once per squad per turn**.
- **Control Points** (candidate from prototype):
  - Being **on or orthogonally adjacent** to a CP at end of turn adds a “flag”.
  - At 3 flags: CP is captured; majority CPs wins.
- **Win condition**: Control a majority of CPs, **or eliminate all enemy squads**.
  - **Implemented now**: CPs at fixed cells; end-turn adds 1 flag if exactly one player occupies/adjoins (Manhattan ≤ 1); capture at 3 flags; match ends on majority CPs. Elimination is checked after damage and end-turn. Match stops advancing turns once a winner is set.

## Progression + Army Decks (Match Availability)
- **Meta**: players collect **Units** and assemble an **Army** (deck) that defines what can appear during the match.
- **In-match Offer** (Option 1):
  - Each turn, server offers **3 Unit cards** sampled from the player’s remaining deck inventory.
  - **Implemented now (MVP)**: cards are sampled only from inventory entries that are **actually playable right now** (spawnable or reinforceable); unplayable inventory IDs are omitted from the random pool.
  - Offer is **terrain-weighted** based on the current board state (terrain under the player’s alive squads; if none, terrain in the player’s home spawn band).
  - Offers are **deterministic** from match seed + turn number + active player.
  - **Playability guarantee**: offer includes at least 1 card playable **right now** as either:
    - **Spawn** (has a legal spawn cell and an available squad slot for that unit size), or
    - **Reinforce** (you have inventory for the unit and **some** owned squad is on an **RA cell** (home/deployment band or CP) with capacity or can be healed).
  - **Spawn bias (MVP)**: if spawning is still legal for any inventory unit (notably when **small squad slots are full** but a **large slot** remains), the offer tries to include at least one **spawnable** card so offers don’t collapse into reinforce-only purely due to RNG.
  - Player plays 1 offered card or **skips** (skip = no placement this turn).
- **One card type, two modes**:
  - **Spawn mode**: play a Unit card to create a new Squad on a legal spawn cell (start zones, etc.). **Large-first spawn is allowed**.
  - **Reinforce mode**:
    - If the squad has capacity: adds a Unit into that Squad.
    - If the squad is full: converts into a **small heal** (only legal if the front unit isn’t already at max HP).
- **Reinforcement Areas (RA)**:
  - Reinforce only if the target Squad is standing on an **RA cell**.
  - **Implemented now (MVP)**: RA includes **home/deployment rows** (same bands as spawn) **plus** **CP cells** (marked on the board).
  - RA can be **fixed zones** and/or **capturable reinforcement points**.
- **Fresh units**:
  - Placement doesn’t end turn.
  - Units added this turn (spawn/reinforce) **cannot act until next turn**.
  - **Implemented now (MVP)**: squads that were spawned or reinforced this turn cannot Move/Melee/Ranged or attack obstacles this turn.

## Rendering Rules
- **World**: 3D voxels for ground and obstacles.
- **Characters**: 2D sprites billboarded to camera; consistent scale and sorting.
- **Readability**: Always show selected squad, reachable cells, and attackable cells.
  - Active-player availability rings: cyan = basic Move left; amber = ability off cooldown.
  - Attack mode highlights: legal enemy targets are highlighted; hovered legal target is preview-highlighted.
  - Offer targeting highlights: spawn cells and legal reinforce targets are highlighted during card targeting.
  - **Combat preview (MVP)**: hovering a legal target in melee/ranged shows predicted damage with terrain attacker bonus + defender reduction.
  - **Optional range overlay**: in melee/ranged mode, all in-range cells are tinted.

## UX Conventions (MVP)
- **Camera controls (MVP)**:
  - **Zoom**: wheel/trackpad zoom; pinch to zoom on touch screens. Zoom keeps the point under the cursor (or two-finger centroid) **anchored in screen space** before board-edge clamping, so the view does not “crawl” or jump.
  - **Rotate**: press-and-hold, then drag left/right to rotate the board; **free rotation** (no snap).
  - **Pan**: trackpad two-finger pan / right-drag (desktop) / two-finger drag (touch).
  - **Start framing**: on startup (and on window resize), camera auto-zooms to fit the entire board inside the HUD-safe play area.
  - **Playable area framing**: camera recenters using the HUD-safe play rect; **edge clamping** ray-tests the **play rect corners** on the ground (tilted ortho). At **minimum zoom**, bounds use a **zoom-scaled outset** so pan is usable; HUD margins may show slight overscan past the nominal board edge.
  - **Zoom range**: allow closer zoom-in for inspecting squads/tiles.
- **Window / display (MVP)**:
  - **Resizable window**: stretch mode **canvas_items**, aspect **ignore**, scale mode **fractional** — enlarging the window **expands the rendered game area** edge-to-edge (no pillarboxing/letterboxing from stretch); orthographic framing uses the HUD-safe play rect and **refits on resize**.
- **Phase clarity (MVP polish)**:
  - **Debug**: **F3** or the **Debug** button toggles a panel that tweaks the main **directional light** (energy, shadows, bias, distance, color, specular).
  - **Default sun**: height **-61°**, angle **330°**, energy **2.05**, shadows on (bias **0.068** / normal **1.75** / max dist **100**), specular **0.45**, white.
  - **Esc**: opens an in-match **menu** (Resume / Restart Match / Quit).
  - HUD shows an explicit **Phase** indicator: **Offer** vs **Action**.
  - HUD shows a short **prompt** describing the expected next click for the current phase/mode.
- **Invalid action feedback (MVP polish)**:
  - Rejected clicks/actions show a short HUD **toast** (e.g. “Invalid move”, “Offer phase: pick a card or Skip”).
- Clicking empty space:
  - If in an action mode (Move/Melee/Ranged): exits back to Select.
  - If already in Select: clears selection.
- **Select → Move**: selecting an owned squad that still has basic Move available auto-enters **Move** mode (reachable cells highlighted).
- **Squad inspection (MVP)**:
  - HUD shows a minimal panel for the **selected squad** with its **unit list** (unit id, HP, ready turn) and current **cooldowns**.
  - Clicking a unit in that list sets it as the squad’s **front unit** (reorders `units[]` so attacks/actions use that unit).
- **Lightweight combat/world feedback (MVP polish)**:
  - Hits briefly **flash** the damaged squad and show a small floating damage number.
  - CP capture shows a brief “CAPTURE” popup + toast.
  - Destroying an obstacle shows a brief “DESTROYED” popup + toast.

## Networking (Authoritative, Web + Mobile)
- **Goal**: strong anti-cheat + low bandwidth (send intents; server sim is truth).
- **Transport**: `wss://` WebSockets for Godot web + mobile.
- **Session**: synchronous 1v1 short match (5–10 min).
- **Join flow**: room code (no accounts).
  - Player A creates room → gets `room_code` + token.
  - Player B joins room code → gets token.
  - Only the two tokens may join the match socket.
- **Server authority**:
  - Server validates all moves/abilities/cooldowns/targets and publishes authoritative deltas.
  - RNG (offers/draft) is server-owned.
- **Protocol**: see `docs/networking-protocol.md` (v0).
  - Client → server: `intent` with `{seq, turn, intent:{k,...}}`
  - Server → clients: `patch` deltas (ops) + occasional `state` snapshots for resync/reconnect
- **Vertical slice implemented**:
  - Godot has a minimal net layer (`Network` autoload): HTTP create/join room → WS connect → send intents.
  - Client applies server `state` + minimal `patch` ops (`set`/`inc`/`push`) and maps authoritative state into the existing offline `GameState` for rendering (squad **cells** and optional `pending_effects` / `board.hazards` when present; full unit stats stay **client-resolved** until the server sim grows).
  - In net play, the **local Godot sim** still runs `Resolver` for actions (optimistic, same as offline); the server accepts matching intents for **turn**, **move**-class goals (`move`, `run`, `jump`, `blink`, `dash`, `pounce`), **switch**, **delayed** (echo `pending_effects` entry), and **plant** (append hazard), plus stubbed **attack** / legacy **melee**/**ranged** (no HP simulation on the server yet). See `docs/networking-protocol.md` for `intent.k` list.

## Offline Save + Replay (MVP)
- `GameState` supports a **minimal JSON snapshot** for offline loop testing and deterministic replays.
- A `ReplayDriver` can load a snapshot and apply a list of intents (`move`, `attack`, `end_turn`, `play_card`, plus ability intents such as `run`, `blink`, `delayed`, …) deterministically.
- **Turn timer**: 60s, server-owned.
  - On expiry: server immediately executes end-turn (hard timeout).

## Data Model (High-level)
- `GameState`: turn, activePlayer, board, squads, **pendingEffects** (delayed strikes), playerInventory
- `Board`: size, tiles (terrain), obstacles, **hazards** (mines/snares), controlPoints
- `Squad`: id, owner, cell(x,y), units[], cooldowns, **snaredNoMoveUntilTurn** (trap), freshTurn
- `Unit`: unitDefId, hp, readyTurn; optional **armorFactor** on unit def reduces HP loss per hit

## Content (implemented baseline)
- **Modern roster** entries exist in `UnitDefs` (e.g. Ninja, Engineer, MRAP, Chunk, …) alongside legacy fantasy units (`soldier`, `archer`, …). Ability specs and resolved TBDs: `docs/planned-units-abilities.md`, `docs/abilities-spec.md`.
- **Logistics / FOB**: unit defs may include tags `logistics` / `fob`; spawn card targeting unions extra empty cells near qualifying squads (Chebyshev 1 / orthogonal cross radius 2).

## Out of Scope (for now)
- Networking, matchmaking, progression/meta, content pipelines beyond placeholders.


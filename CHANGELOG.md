# Changelog

All notable changes to this project are documented here.

This changelog is intentionally **concise**:
- Use **one bullet per change**.
- Prefer **player-visible** changes and major technical milestones.
- Keep entries to the **current milestone** plus a short history.

## Unreleased
- **UX**: selecting a squad auto-enters **Move** when that squad still has its basic Move available.
- **UX**: active squads pulse with a **cyan** ring when basic Move remains and an **amber** ring when any ability is off cooldown; **End Turn** highlights when none remain.
- **Rules**: basic **Move is once per squad per turn** (movement abilities still cooldown-gated).
- **Win**: CP flagging counts **standing on or adjacent** to the point; **elimination** (wipe all enemy squads) ends the match; turn no longer advances after a winner is set.
- **UX**: **Esc** opens an in-match menu (Resume / Restart Match / Quit).
- **Lighting**: default sun set to height **-61°**, angle **330°**, energy **2.05**, shadow bias **0.068**, normal bias **1.75**, specular **0.45**.
- **Display**: window **stretch aspect** is **ignore** (with **canvas_items** + **fractional** scale) so resizing the window **fills the viewport** with the game — no growing letterboxing/pillarboxing; the 3D view grows with the window (camera already refits on `size_changed`).
- **Net (Godot + Node)**: movement-class abilities (`run`/`jump`/`blink`/`dash`/`pounce`) and **switch** / **delayed** / **plant** now send WebSocket intents (no more “net stub” toast on dashes); server handles them alongside `move` (cell updates) or echoes `pending_effects` / `board.hazards`. **Net state merge** keeps local unit HP/cooldowns when the server only sends squad id/owner/cell. **End turn** in net mode runs the local resolver first, then notifies the server (turn counter stays in sync with patches).
- **UX**: **Delayed strike** telegraphs on the board (tinted cell + “turns left / resolves at turn N” label) from `pending_effects`.
- **Tooling**: fixed additional Godot 4.6 **strict type inference** compile errors in `Pathfinding`, `Resolver`, `Main`, and `Rules` (warnings treated as errors).
- **Units + abilities**: expanded `UnitDefs` with a **modern roster** (Ninja through Buggy, Chunk, etc.), **`kind`-driven actions**, **armor** on selected defs, **delayed strikes** (`pendingEffects`), **board hazards** (mine / big mine / snare), **Logistics/FOB** spawn-range tags, and resolver support for Run, Blink, Dash, Charge, Pounce, Slam, Railgun, Switch, and related abilities; HUD uses a **dynamic ability bar**; see `docs/abilities-spec.md` and `docs/planned-units-abilities.md`.
- **Design doc**: movement is defined as **always entire-squad** — no per-unit spatial movement or splitting squads across cells.
- **Offer UI**: board picks run in `_unhandled_input` (after Control GUI) so offer/HUD clicks work; HUD root uses `mouse_filter` ignore for empty areas; choosing a card still refreshes the HUD via `changed`.
- **Movement (net)**: move intents use the same loose rules as the v0 server (no terrain or squad “wall” pathing); highlights match. **Movement (offline)**: move range highlights use **terrain-based** range (e.g. sand) like validation. Re-clicking the **selected** squad in move mode no longer cancels move; board clicks are no longer processed twice.
- **Squads**: each alive unit on the board is shown as an **emoji** placeholder (by unit type) in a billboard label over the cell until real sprites exist.
- **Board**: default grid increased to **14×14** (same cell size; ~1.5× the former 9×9 edge span). Offline seeds and multiplayer examples updated; camera re-fits when board dimensions change (e.g. snapshots).
- **Debug**: HUD **Debug** panel (bottom-left; **F3** toggles) exposes **Sun** directional-light tweaks (sun **height** / **angle** °, energy, shadows, biases, max shadow distance, color, specular).
- **Camera**: ortho zoom anchors to cursor/centroid; board clamp uses **HUD play-rect** corner rays (not the full viewport) plus **zoom-scaled outset** (`board_clamp_outset_world` default **1.15**) so max-zoom pan isn’t dominated by clamp; tilted-camera corner iteration replaces scalar half-extent bounds (fixes zoom snap/pivot drift).
- Removed temporary **debug NDJSON instrumentation** from `GameState`, `Main` (session log writes and verbose spawn/reinforce traces).
- Squad capacity is **per squad**: **3 small-class + 1 large-class** units (max **4** alive units per squad); global “army squad slot” caps for spawning were removed — **spawn** is limited by **empty cells in your spawn band + inventory**, and **reinforce/heal** follows per-squad composition in reinforcement zones.
- Reduced default offline debug seed squads to **1 small squad per player** so early offers aren’t squeezed by extra starting squads (previous seed placed 2 small squads per player).
- Reinforcement zones now include **home/deployment rows** (same bands as spawn) in addition to **CP cells**, so offers can reinforce squads deployed in your start zones without requiring center captures.
- Clarified Offer prompts + reinforce rejection toasts: reinforce requires being in a **reinforcement zone** (**home deployment rows** and/or **CP**).
- Offers no longer surface inventory units that are **unplayable right now** as cards (cannot spawn **and** cannot reinforce), reducing misleading “dead” draws when the board/spawn band is clogged or reinforce isn’t possible.
- When spawn fails after a click (Resolver rejects the spawn), the game shows **Spawn failed** instead of silently doing nothing.
- Improved deterministic offers: if **spawn is still legal** for some inventory unit (**spawn band has an empty cell** + inventory), the 3-card offer guarantees at least one **spawnable** pick (so draws don’t collapse into reinforce-only purely due to RNG); default inventory includes **ogre** for large-unit testing.
- Fixed deterministic offer “playability” checks to treat reinforce as playable whenever **any** eligible on-RA squad can accept the card (not only when a squad was pre-selected), preventing misleading offers when reinforce is the only option.
- Added a short toast when a card can only be played as reinforce because **there are no empty spawn cells** (so reinforce-only targeting isn’t mistaken for a bug).
- Fixed offer card flow: spawn vs reinforce targeting is disambiguated (defaults to spawn when both are legal unless you’ve selected a squad in a reinforce zone that can reinforce), and mis-clicks on non-reinforcable squads no longer show a confusing “can’t spawn” message.
- Fixed unit placement clicks not registering when the HUD/UI consumed input events (board click handling now runs in `_input`).
- Auto-fit starting camera zoom to frame the full board within the HUD-safe play area (also re-fits on window resize).
- Allow closer camera zoom-in (lower minimum orthographic size).
- Added camera controls (Godot): wheel/trackpad zoom, pinch zoom, hold-drag rotate (free rotation), and pan (trackpad/touch + right-drag).
- Restricted camera pan pivot to stay within the board bounds.
- Camera centering/clamping now targets the visible play area (excludes HUD panels).
- Fixed camera pinch-zoom script compile error by adding explicit float types (Godot warnings-as-errors).
- Fixed Godot 4.6 startup by resolving GDScript compile errors (Variant typing warnings-as-errors, `NetworkClient` method rename, and correct `Rules` usage).
- Added HUD phase indicator (Offer vs Action) with short phase prompts, plus toast feedback for rejected clicks/actions.
- Added lightweight feedback: hit flash + floating damage text, CP capture popup/toast, and obstacle destroyed popup/toast.
- Added a multiplayer vertical slice: Godot client can create/join rooms over HTTP, connect via WebSocket token, send `end_turn`/`move` intents, and apply server `state`/`patch` updates.
- Terrain-weighted deterministic offers: 3-card offers are now biased by terrain under the active player’s squads (or home band if none), and the “at least one playable” guarantee now ensures a card is playable as spawn (legal spawn cell + inventory) or reinforce (any eligible squad on an RA with capacity/heal).
- Added a minimal selected-squad inspection panel (unit list + ready turns + cooldowns) and click-to-set front unit (reorders squad `units[]` safely in sim).
- Added combat hover preview: in melee/ranged mode, hovering a legal target shows predicted damage including terrain attacker bonus and defender reduction; added an optional range overlay tint for selected action.
- Added offline `GameState` JSON snapshot save/load (S/L) plus a minimal deterministic replay driver (`ReplayDriver`) that can apply an intent list to a loaded snapshot.
- Combat actions are now data-driven per unit definition (range/damage/cooldown pulled from `UnitDefs.actions`), while keeping the HUD buttons (Move/Melee/Ranged) the same.
- Improved procedural board playability guarantees: ensure clear lanes from each home spawn band toward the CP row, avoid fully isolating CPs, and tune destructible obstacle frequency to avoid spam.
- Added squad reinforcement capacity rules: squads cap at **4** alive units (**3 small-class + 1 large-class**); reinforces add a unit if composition allows, otherwise heal the front unit (if not already at max HP).
- Added terrain utility effects: Sand grants +1 move range, Rock reduces incoming ranged damage by 1 (min 1), and Soil regenerates +1 HP to the front unit at end of turn.
- Added initial terrain gameplay: Soil buffs melee (+1 dmg) and Rock buffs ranged (+1 dmg) based on attacker tile; added offer targeting highlights for spawn/reinforce.
- Multi-unit squads: squads now stay alive if any unit has HP > 0; attacks target the “front” alive unit instead of always `units[0]`.
- Added Reinforcement Areas (RA) as explicit board cells and rendered a minimal RA marker on the board.
- HUD + squad labels now show a minimal unit-count indicator (`xN`) and use total alive HP for readability.
- Added offline deterministic 3-card offer loop (3 cards + Skip) with spawn/reinforce card plays and “fresh squad can’t act this turn” gating.
- Added seeded deterministic board generation (terrain grid + ~12% obstacles with center/CP/start-band exclusions) and terrain-colored ground tiles.
- Added basic destructible obstacle interaction: melee/ranged can target destructible blockers to clear paths.
- Improved board readability: attack modes now highlight legal targets and provide hover previews; HUD shows current mode plus selected squad HP/cooldowns.
- Added deterministic voxel obstacles to the MVP board (rendered blockers that affect BFS movement).
- Added playable Control Points loop: CP markers + end-turn flagging/capture at 3 flags + majority-CP win state.
- Added initial `DESIGN.md` (concise living design doc).
- Added Cursor rule to maintain design doc + changelog.
- Incorporated key mechanics from prototype design doc (determinism + cooldown pacing, CP flags/capture, spawn-cell commitment, terrain-weighted offers, budget cap).
- Specified networking approach: server-authoritative WebSockets with room codes + 60s hard turn timer.
- Added initial authoritative networking protocol spec (`docs/networking-protocol.md`) and local run doc (`docs/running-server.md`).
- Added minimal Node.js WebSocket server skeleton (`server/`) with room create/join tokens, intent ingest, and `state`/`patch` broadcasts (turn timer stubbed).
- Defined progression + deck-based offers, squad slot limits (3 small + 1 large), reinforcement areas, and Fresh-unit action gating.
- Added destructible obstacle voxels (some obstacles can be destroyed to open paths).
- Bootstrapped a Godot MVP project (Main scene + board rendering + HUD).
- Implemented offline deterministic sim (turns, selection, BFS movement, melee/ranged attacks with cooldowns).


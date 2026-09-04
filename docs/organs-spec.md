# Organs spec (Chess 3)

Companion to [DESIGN.md](../DESIGN.md). Locked implementation choices.

## Visuals (rig)
- Soft humanoid slot layout + idle spring jiggle.
- Move: hop tween between cells with stride jiggle.
- Hover: ray-proximity picks an organ and amplifies its jiggle.
- Death: popped organs spawn emoji `RigidBody3D` corpses on the board floor.

## Body slots (visual + optional def hint)
- Def field `body_slot`: `head` | `torso` | `arm` | `leg` | `any` (default `any`).
- Soft humanoid slots (one each): `head`, `torso`, `arm_l`, `arm_r`, `leg_l`, `leg_r`.
- Assignment: walk organs in stack order; prefer matching `body_slot` into an empty primary slot (`arm` → first free arm, `leg` → first free leg). Overflow / leftover → extras (back, side, float offsets).
- Missing limb slots may be filled by `any` organs after preferred slots are considered.

## Damage pop order
- Raw damage after terrain → **HP chip count** on the front organ (mutant organs have **2 HP** and chip before popping).
- Each damage point removes 1 HP from index **0**; at 0 HP the organ is deleted from `units[]` (no zero-HP placeholders).
- **Graft Plate** organs spawn with **2 HP** (ablative armor graft).
- If fewer organs than damage, Mutant dies (not alive).
- On attach, **`core` sinks to the back** of the stack (all cores after non-cores) so the heart dies last and specialty organs act as ablative HP. Manual / snapshot order is otherwise preserved.
- Combat preview lists which organ emojis will pop vs remain.
- Cooldown keys for actions the mutant no longer has are pruned after pops.

## Attach lock
- `SquadState.organs_locked` starts `false`.
- After any resolver move that sets `cell`, if the new cell is outside the owner’s Spawn Pool band → `organs_locked = true`.
- Attach legality requires: owned, alive, not locked, cell in Spawn Pool, alive organ count &lt; hard max (10).

## Caps
- Soft ceiling **6**: HUD may warn when attaching beyond; still legal until hard max.
- Hard max **10**: `can_add_unit_to_squad` / attach rejects.

## Ability union
- Mutant action set = union of `actions` keys across all alive organs (mutant organs may borrow one bonus action).
- Lookup for an `action_id`: **best** def among organs that define it (higher damage / path_damage / range / steps; lower cooldown). Front reorder does **not** change shared ability power (it still changes damage pop order).
- Cooldowns live on the Mutant (`SquadState.cooldowns`), keyed by `action_id`.

## Basic move vs abilities
| Player action | Sim |
|---------------|-----|
| **Move** (HUD key) | 1 cell orthogonally; once per Mutant per turn; Sand +1 range |
| **Run** (Hoof) | 2 cells path move; ability cooldown |

## Gene roster (biotech fantasy → Chess-2 ability)

| id | emoji | name | ability |
|----|-------|------|---------|
| core | 🫀 | Cardiac Core | melee chip |
| claw | 🦾 | Ripper Claw | melee + **Dash** (3 through, path dmg) |
| hoof | 🦵 | Stride Hoof | **Run** 3 |
| eye | 👁️ | Scout Eye | **Ranged** 5, **1** chip |
| shell | 🐚 | Shock Shell | **Slam** AoE r1 |
| ram | 🐏 | Ram Crest | **Charge** 2 + push |
| node | ⚡ | Fuse Node | **Powerstrike** (delay 1, double dmg cell) |
| vent | 🌋 | Vent Sac | **Eruption** (delay 1, double dmg r1) |
| spine | 🔭 | Rail Spine | **Railgun** line 4 |
| spring | 🦿 | Spring Coil | **Jump** 3 over units |
| leap | 🐆 | Leap Muscle | **Pounce** 3 + landing AoE |
| synapse | 🔗 | Synapse Link | **Switch** mutants range 3 |
| phase | ✨ | Phase Gland | **Blink** chebyshev 4 |
| beacon | 📡 | Strike Beacon | **Airstrike** delay, range 5, cross 5 |
| spore | 💣 | Spore Mine | **Mine** plant r1 |
| pod | 💥 | Burst Pod | **Big mine** plant r1 + splash |
| gland | 🧪 | Snare Gland | **Snare** plant r1 (2-turn root, CD 4) |
| plate | 🛡️ | Graft Plate | passive **3 HP** |
| chunk | 🧊 | Biomass Chunk | passive **1 HP** filler |
| brood | 👜 | Brood Sack | **Logistics** spawn +1 ring |
| anchor | ⚓ | Anchor Node | **FOB** spawn cross +2 |
| rot | 🦠 | Rot Sac | curse: **+1 dmg taken** |
| leech | 🪱 | Leech Coil | curse: **−1 move** |
| static | 📻 | Static Lobe | curse: **+1 ability CD** |

## Field pickups
- **Gear** (`BoardState.gear`): `{ unit_def_id, is_mutant }` per cell. Spawned at gen + dropped on pop of **reclaimable** organs (`UnitDefs.is_reclaimable_gear`). Max **14** gear on board. Board visual = organ emoji only (no ball).
- **Eggs** (`BoardState.eggs`): same payload; consumed on step. Curse organs only enter play via eggs (not gene pool). Board visual = opaque green/red ball (contents hidden).
- **Non-reclaimable on pop**: `core`, `brood`, `anchor`, and curse organs — destroyed organs leave no gear.
- **UI**: reachable pickups highlighted when selected mutant can graft (move/run reach).
- **Demo AI**: styles rush/swarm/balanced path to pickups within 6 cells when under soft cap.

## Gene offer spending
- A turn’s 3-gene offer can be spent **multiple times** in the same offer phase.
- Each spawn/attach removes that gene from `offer_cards` and inventory (must have count > 0).
- After each play, unplayable leftovers are pruned; offer ends on **Skip**, empty offer, or nothing playable left.

## Spawn egress
- Obstacles are excluded from `HOME_SPAWN_ROWS + SPAWN_EGRESS_ROWS` (currently 2+1) so the first step out of the Spawn Pool is not blocked by generation.

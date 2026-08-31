# Abilities spec (resolved TBDs)

Companion to [planned-units-abilities.md](planned-units-abilities.md). These choices are what the simulation implements.

## Metrics

- **Blink**: Chebyshev distance ≤ 4 (king moves). Destination must be empty, in bounds, not blocked by obstacle HP > 0.
- **Switch**: The squad using Switch is the **caster**. **Both** target squads must be **friendly**, within Manhattan range **3** of the **caster’s cell** (not necessarily of each other). Squads **A** and **B** swap `cell` positions; the caster does not move.

## Push (Charge)

- After Charge deals damage to the defender, attempt to **push** the defender **one step** along the ray from attacker toward defender (from attacker cell to defender cell, orthogonal steps only — Charge path must be straight axis-aligned toward the defender).
- **Push destination** empty and passable: defender squad moves there.
- If blocked (map edge, obstacle HP > 0, or friendly/enemy squad): **no movement**; damage still applied.

## Dash (path damage)

- Path is **orthogonal**, up to **3** steps, **ignores squad occupancy** for movement (cannot end on blocked terrain or obstacle).
- **Landing**: last cell must be empty and passable.
- **Damage along path**: each **enemy** squad whose cell is **entered** along the path (excluding the landing cell if it was enemy — landing cell handled separately) takes **dash_path_damage** once, in **path order** (deterministic). Enemy on landing cell takes **landing melee damage** from the action def if applicable, or path damage — use primary **damage** field for landing attack when targeting squad.

Actually simplify dash: damages **each enemy squad** whose cell lies on **any step** of the path (including jumped-over), **once**, in order of first encounter along path.

## Armor

- Unit def optional **`armor_factor`** (int, default 1). Incoming damage to that unit’s HP uses  
  `hp_loss = max(1, floor(raw_damage / armor_factor))`  
  when `armor_factor > 1`; when 1, behaves as normal (`hp_loss = raw_damage` capped by hp).

## Delayed strikes

- **`resolve_at_turn`**: when the ability is used, schedule `resolve_at_turn = gs.turn_number + 1`. Resolver processes pending effects **after** `turn_number` is incremented in `end_turn`, when `gs.turn_number == resolve_at_turn`.
- Deterministic ordering: sort by ascending `pending_id`.

## Mines and snares

- **Mine / Big mine / Snare**: stored on [BoardState](src/sim/BoardState.gd) hazards. Owner is planting player.
- **Trigger**: when **any** squad **enters** the cell (movement abilities included), hazard fires **once** then is removed (mines/snare).
- **Snare**: sets defender squad `snared_until_turn = gs.turn_number + 2` (cannot move until that turn number exceeds current — effectively **2** active-player opportunities captured by global turn counter; implemented as **cannot move while `turn_number <= snared_until_turn`** — adjust: store `snared_until_turn` exclusive so moves forbidden if `gs.turn_number <= snared_until_turn`).

Use: `snared_until_turn = gs.turn_number + 2` means after two **global** turn increments snare clears — simpler: **`snare_turns_remaining`** decremented each **end_turn** when that squad’s owner… messy.

Simplest: **`snared_no_move_until_turn`** = `gs.turn_number + 2` — cannot move while `turn_number < snared_no_move_until_turn`.

## Logistics / FOB

- **Logistics**: union **spawn** cells with Chebyshev distance ≤ **1** from any **alive** friendly squad whose **front unit** has tag **`logistics`**.
- **FOB**: same with **cross** orthogonals at range ≤ **2** (cells at Manhattan distance 1 or 2 only on axis-aligned rays — “cross shape”):  
  cells where `abs(dx)+abs(dy) <= 2` and `(dx==0 or dy==0)` i.e. Manhattan ≤ 2 on orthogonal-only from squad cell.

## Kind field

- Each action in `UnitDefs` includes **`kind`** for resolver branching (`melee`, `ranged`, `run`, `dash`, `charge`, `jump`, `blink`, `pounce`, `slam`, `railgun`, `delayed_single`, `delayed_radius`, `delayed_area`, `switch`, `plant_mine`, `plant_big_mine`, `plant_snare`).
- Legacy **`type`** remains for terrain bonuses (`melee` / `ranged` where applicable).

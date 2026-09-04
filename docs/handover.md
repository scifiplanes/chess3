# Agent handover — Chess 3 (Mutants / Organs)

Read **DESIGN.md** and **CHANGELOG.md** for product-facing rules. Organ details: **docs/organs-spec.md**.

## What Chess 3 is
Fork of Chess 2. Pieces are **Mutants** built from **Organs** (1 HP each). Deck is a **gene pool**. Attach organs only in the **Spawn Pool** until the Mutant leaves (then `organs_locked`). Abilities = **union** of all organs. Soft ceiling 6 / hard max 10.

## Key files
| Area | Files |
|------|--------|
| Design | `DESIGN.md`, `docs/organs-spec.md`, `CHANGELOG.md` |
| Organ defs | `src/sim/UnitDefs.gd` (`body_slot`, emoji, actions) |
| State | `SquadState.gd` (`organs_locked`), `GameState.gd` (gene inventory, attach) |
| Rules | `Rules.gd` (`is_spawn_pool_cell`, attach legality, caps) |
| Resolve | `Resolver.gd` (`_pop_organs`, `_set_squad_cell` lock-on-leave, ability union lookup) |
| View | `SquadView.gd` (humanoid emoji layout + spring jiggle / hit impulse) |
| UI | `HUD.gd` (`rebuild_ability_buttons_for_squad`), `Main.gd` |

## Extension patterns
1. **New organ**: add to `UnitDefs.DEFS` + `UNIT_EMOJI` with `max_hp: 1` and `body_slot`. Seed counts in `GameState._seed_default_inventory`.
2. **New ability kind**: same as Chess 2 — Resolver + Rules + Main targeting.
3. **Attach / lock**: do not reintroduce CP reinforce; Spawn Pool only via `Rules.is_spawn_pool_cell`.

## Not done
- Networking organ sim parity
- Full physical ragdoll collisions
- Meta progression beyond in-match gene pool

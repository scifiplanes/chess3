# Agent handover — units & abilities implementation

This note orients a **future coding agent** on the tactical game codebase after the **planned units and abilities** work landed. Read **DESIGN.md** and **CHANGELOG.md** for product-facing rules and recent player-visible changes.

## What exists now

- **Content**: [src/sim/UnitDefs.gd](src/sim/UnitDefs.gd) holds legacy units (`soldier` … `bomber`, `ogre`) plus a **modern roster** (e.g. `ninja`, `engineer`, `buggy`, `chunk`, …). Each action has an **`kind`** field (e.g. `melee`, `ranged`, `run`, `blink`, `delayed_radius`, `plant_mine`). Optional **`armor_factor`** on the unit def; **`tags`** include `logistics`, `fob`, `chunk`.
- **State**: [src/sim/GameState.gd](src/sim/GameState.gd) has **`pending_effects`** (delayed strikes) and snapshot/replay support for them and board hazards. [src/sim/SquadState.gd](src/sim/SquadState.gd): dynamic **`cooldowns`**, **`snared_no_move_until_turn`** for snares.
- **Board**: [src/sim/BoardState.gd](src/sim/BoardState.gd) **`hazards`** — mine / big_mine / snare per cell; triggered on squad **enter** in [src/sim/Resolver.gd](src/sim/Resolver.gd) (`move_squad` and special moves call `_trigger_hazard_on_enter`).
- **Rules**: [src/sim/Rules.gd](src/sim/Rules.gd) — snare blocks normal move; railgun/charge axis and blocking rules; **`spawn_cells`** unions Logistics (Chebyshev ≤1) and FOB (orthogonal cross, Manhattan ≤2) from tagged squads.
- **Resolution**: [src/sim/Resolver.gd](src/sim/Resolver.gd) — armor-aware damage (`_hp_loss_from_raw`), `attack`/`use_*` methods, **`end_turn`** increments turn then **`_resolve_pending_effects`** (matches `resolve_at_turn` to new `turn_number`).
- **Pathfinding**: [src/sim/Pathfinding.gd](src/sim/Pathfinding.gd) — `path_pass_through_to` (dash), `jump_landing_legal`, `chebyshev_disk` (blink), etc.
- **UI**: [scenes/HUD.tscn](scenes/HUD.tscn) uses **`AbilityBar`**; [src/presentation/HUD.gd](src/presentation/HUD.gd) **`rebuild_ability_buttons`** from front unit’s actions. [src/presentation/Main.gd](src/presentation/Main.gd) routes clicks by **`UnitDefs.action_kind`** — squad-target vs cell-target vs switch two-click vs instant slam.
- **Replay**: [src/sim/ReplayDriver.gd](src/sim/ReplayDriver.gd) — extra intent types (`run`, `blink`, `charge`, `railgun`, `delayed`, `plant`, `switch`, …).

## Authoritative design choices

Concrete rules (Blink metric, Switch caster range, armor math, dash ordering, etc.) live in **[docs/abilities-spec.md](docs/abilities-spec.md)**. The original brainstorm list is **[docs/planned-units-abilities.md](docs/planned-units-abilities.md)**.

## Extension patterns

1. **New unit**: Add an entry to `UnitDefs.DEFS` (max_hp, size, optional `tags` / `armor_factor`, `actions` dict). Add emoji in `UNIT_EMOJI` and optional **`ACTION_LABEL`** for new action ids. Use **`list_action_ids`** / **`action_order`** on the def if you need a stable UI order (otherwise keys sort).
2. **New ability kind**: Add the `kind` on the action dict, branch in **Resolver** (new `use_*` or extend `attack`), **Rules** if legality is non-trivial, and **Main** (`_on_action_pressed`, `_on_cell_clicked`, `_refresh_reachable_for_action`, `_render_highlights`) so targeting and highlights stay consistent.
3. **Inventory / offers**: Default pool is seeded in `GameState._seed_default_inventory`; offer weighting uses `_offer_preferred_terrain_for_unit` — extend if new units need terrain bias.

## Not done / caveats (good next tasks)

- **Networking**: Offline sim is authoritative for new abilities; **[DESIGN.md](../DESIGN.md)** still notes server stubs for combat. Mirror intents and validation in the server per [docs/networking-protocol.md](networking-protocol.md) when ready.
- **Net client stub**: [src/presentation/Main.gd](../src/presentation/Main.gd) may toast **“Ability not available in net stub”** for movement abilities; extend `Network` intents if needed.
- **UX polish**: No delayed-strike **ghost marker** on board (“lands turn N+1”) — only scheduling + resolve is implemented.
- **Regression**: Godot was not executed in the agent environment; run the project locally after substantive changes.

## Quick file map

| Area | Files |
|------|--------|
| Data | `src/sim/UnitDefs.gd`, `UnitState.gd`, `SquadState.gd` |
| Sim | `Rules.gd`, `Resolver.gd`, `Pathfinding.gd`, `GameState.gd`, `BoardState.gd` |
| UI | `scenes/HUD.tscn`, `src/presentation/HUD.gd`, `Main.gd`, `SquadView.gd` |
| Replay | `src/sim/ReplayDriver.gd` |
| Docs | `DESIGN.md`, `CHANGELOG.md`, `docs/abilities-spec.md`, `docs/planned-units-abilities.md` |

## Workspace rules reminder

Per [.cursor/rules](../.cursor/rules): after **feature / rule / mechanic** changes that affect players, update **DESIGN.md** and **CHANGELOG.md** (Unreleased unless versioning).

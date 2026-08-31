# Planned units and abilities

Design targets for content not yet implemented in `UnitDefs` / sim. **Movement abilities relocate the whole squad** unless a future rule explicitly says otherwise (see `DESIGN.md`).

## Planned unit types

Ninja, Operator, Spidertank, Swarm, Walker, Wolfpack, Copter, Technical, Fog, Android, Guerrilla, Sniper, Engineer, Tank, IFV, MRAP, MLRS, Strike Drone, Heavy Copter, Mortar, APC, Soldier, Buggy.

## Planned abilities

| Ability | Spec (draft) |
|--------|----------------|
| **Move** | Move squad 1 cell. Cooldown 1 turn. Planned cost: **1 AP** (see `DESIGN.md` — MVP uses cooldown-only pacing; AP is a future rules option). |
| **Run** | Move squad **2** cells. |
| **Dash** | Move squad **3** cells **through** other units; damage units passed through or along the path (exact pipeline TBD in sim). |
| **Slam** | Damage enemy units in **1** cell radius (Manhattan unless noted otherwise in resolver). |
| **Charge** | Move squad **2** cells; if an enemy is in the way, damage and **push** that squad (push rules TBD). |
| **Powerstrike** | **Delay 1 turn**, then deal **double damage** to **one** cell. |
| **Eruption** | **Delay 1 turn**, then deal **double damage** in **1** cell radius. |
| **Railgun** | Damage units in a **straight line**; range **4** cells. |
| **Jump** | Move squad **3** cells, **passing over** intervening units (does not stop on occupied cells). |
| **Pounce** | Move squad **3** cells; on landing, damage enemy units in radius (radius TBD — default **1** cell unless balanced otherwise). |
| **Switch** | Range **3** cells: swap positions of **two** units (targeting and same-owner/enemy rules TBD). |
| **Armor** | Unit requires **2** damage per hit to lose **1** HP (or “two instances of damage to destroy” — exact damage pipeline TBD). |
| **Chunk** | Passive **cube**: no actions; contributes **extra HP** only. |
| **Airstrike** | Range **5** cells; target a **5**-cell area; **1** turn delay, then damage. |
| **Mine** | Plant in **1** cell radius; explodes when an **enemy steps on** it; deals damage to that squad/unit. |
| **Big mine** | Same trigger radius as Mine; explosion deals damage in **1** cell radius (splash). |
| **Snare** | Plant in **1** cell radius; when triggered by an enemy step, **no damage** (or minor — TBD): **trap for 2 turns** (cannot move / reduced actions — status rules TBD). |
| **Blink** | Move squad to **any empty cell** within **4** cells (Manhattan or Chebyshev — TBD). |
| **Logistics** | Allows **spawn/reinforce card plays** to target spawn cells within **1** cell radius of this squad (extends normal RA/spawn rules — exact validation TBD). |
| **FOB** | Same idea as Logistics at **2** cell range in a **cross shape** (orthogonal only from the unit’s cell). |

## Notes

- **Cooldown vs delay**: “Cooldown N turns” gates **reuse** of the ability; “wait/delay 1 turn” means the **effect resolves** one turn after targeting (scheduled effect — fits `pendingEffects` in the data model).
- **Swiitch** → **Switch** (spelling).
- **Snare** is separate from **Big mine** (trap emphasis vs splash damage emphasis).

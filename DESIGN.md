# Game Design — Chess 3 (Mutants / Organs)

## Vision
- **Core**: Turn-based tactics on a **3D voxel board**; pieces are **Mutants** built from **Organs**.
- **Feel**: Readable, snappy, deterministic tactics; Mutants look like janky emoji humanoids.

## Chess 2 → Chess 3 Mapping
- **Squad** → **Mutant** (one piece per cell).
- **Unit** → **Organ** (stack members; each is **1 HP**).
- **Army inventory / offers** → **Gene pool** (organ genes offered each turn).
- **Reinforce** → **Attach** organ onto a Mutant (Spawn Pool only, while unlocked).

## Core Rules (MVP)
- **Players**: 2, alternating turns. Opener = **`seed % 2`**; **both** seats get opening (**2 of 5**) on turns 1–2.
- **Determinism**: No RNG in combat/movement; gene offers are seeded.
- **Turn structure**: Gene offer → **first personal turn: pick 2 of 5** (or Skip remaining); **later: pick 1 of 3** or Skip → Action phase → End Turn. Opening prompts are **step-by-step** (`n/2`); **MOVE/END/ability keys hide** while any gene offer is up.
- **Hot-seat deck**: **72pt DECK** budget; **BALANCED** default is an **8-gene signature rack** at full budget. Style presets (**rush/kite/tank/swarm**) also fill to **72**. Prep UI is **loadout bay** (style pills → specimen rack visible by default; catalog behind **Customize**; CLEAR as text link) with optional **gene draft** ritual; P1 lock → pass-device handoff → P2 → start. Prep hint uses readable **system sans** + ASCII `-> LOCK` (Jrudge C glyph reads as `<`).
  - Unchosen genes stay in the pool for later offers; Skip takes none.
- **Board**: 14×14 voxels; terrain (Soil/Rock/Sand); destructible obstacles (weird mushroom alpha sprites); Control Points.
- **Movement**: entire Mutant only; basic **Move** **1** cell (Sand **+1** → 2); **Run** ability (**Stride Hoof**) **3** cells; basic Move once per Mutant per turn.
- **Win**: majority of CPs — stand **in the CP zone** (CP cell + 8 neighbors) for **7** uncontested end-turn flags (**8** if you only have one living Mutant), **or** eliminate all enemy Mutants.
- **Move**: **1** cell baseline; **+1** while in your **Spawn Pool** (egress); **+1** on Sand (stacks).

## Mutants & Organs
- A Mutant is alive while it has **≥1 organ**.
- Each organ has **1 HP** (exception: **Graft Plate** is **4 HP**). Damage removes organs from the **front of the stack** (index 0 upward); removed organs leave the array.
- **Mutant organs** (~22% offer roll; turn-1 hand guarantees ≥1 when possible): **2 HP**, **2.2×** board scale, one **bonus ability** borrowed from another organ type (shown on gene cartridge as `M·` + extra action).
- **N damage → N HP chipped** on the front organ first; pop when HP hits 0 (terrain bonuses/reductions still apply to raw damage before chip count).
- **24 organ genes** (21 offer + 3 egg-only curses) cover abilities + debuffs; see `docs/organs-spec.md`.
- Organs grant abilities; the Mutant uses the **union** of all attached organs’ actions (duplicate action ids merge to the **strongest** variant by damage/range/steps; one shared cooldown on the Mutant).
- On attach, **core** organs are kept at the **back** of the stack (die last); specialty organs soak damage first.
- **Soft ceiling**: prefer ≤ **6** organs (UI cue). **Hard max**: **10**. At **7+** organs: **−1 move**; at **9+**: **−1** more; **+1 damage taken** at **8+**.
- Free attach order otherwise; visuals apply a soft humanoid bias (see `docs/organs-spec.md`). Front-of-stack organ gets a warm outline (dies next).
- **Symmetrical slots**: organs on `arm_r` / `leg_r` mirror horizontally so limbs face outward.
- Board keeps one **egress row** beyond each Spawn Pool clear of obstacles so Mutants can leave without being walled in.

## Spawn Pool & Attach
- **Spawn Pool** = home deployment band only (not CPs).
- **Match start**: empty board — no pre-placed Mutants; first squads come from gene offers.
- **Spawn**: play a gene on an empty Spawn Pool cell → new Mutant with that organ.
- **Attach**: play a gene onto an owned Mutant that is in the Spawn Pool and **`organs_locked == false`**.
- Attach can target the **same cell repeatedly** (stack more organs) until lock or hard max.
- The moment a Mutant’s cell is **outside** the Spawn Pool, set **`organs_locked`**. Locked forever (return to pool does not unlock).
- No heal-on-full attach. Fresh Mutants/attaches cannot act until next turn.

## Field pickups (Gear & Eggs)
- **Gear**: organ weapons scattered at board gen (**3–5** per map). Step onto gear to **field-graft** — works **anywhere**, bypasses **`organs_locked`**, respects hard **10** cap. Popped **reclaimable** organs become ground gear (step to reclaim). **Core / brood / anchor / curses** do not drop as gear. Scattered gear capped at **14** (farthest culled on overflow).
- **Eggs**: **2–4** containers per map; step to attach contained organ (egg consumed). Pool mixes normal organs and **cursed** grafts (~**12%**): Rot Sac, Leech Coil, Static Lobe.
- **Telegraph**: selected mutant highlights reachable pickups (stronger graft rings); organ-emoji gear, green/red **opaque egg ball** (contents hidden), red cursed egg; hover chip **STEP TO GRAFT** / **GRAFT — …**; **toast + GRAFT pop + burst/sparks + mutant mint punch** on graft; **leave-lock**: tip once + **amber LOCK egress** (one `LOCKED` pop per cell per move session).
- **Demo AI**: rush / swarm / balanced detour toward pickups within **6** cells when under organ soft cap.

## Gene Pool (Offers)
- **Opening (turns 1–2)**: each seat’s first turn is a 5-gene hand; place **2 of 5** (spawn/attach), or Skip remaining after the first place. Hand **hard-biases** teaching genes (**core/claw/eye/hoof/shell/plate/spring/chunk**) when inventory has ≥3; guarantees **core** + one combat gene when possible; prefers unique faces; **excludes** specialty (anchor/brood/spore/pod/phase/beacon/node/vent/spine/leap/synapse/ram/gland/…) when a simpler unused gene exists — **Anchor/Brood hard-banned** while any teach gene remains in inventory (re-applied after playability swaps).
- **Later turns**: 3-gene offer (+ Skip) from remaining gene-pool inventory; **pick one** gene, or Skip. First post-opening offer toasts once: “Later offers: pick 1 gene — specialty unlocked.”
- Playable now = spawnable **or** attachable (unlocked Mutant in Spawn Pool with capacity).
- Deterministic from match seed + turn + active player; playability-filtered like Chess 2 offers.

## Combat & Terrain (kept)
- **Damage baselines** (1 chip = 1 organ HP unless noted): core **melee 1**, claw **melee 2**, eye **ranged 1**, shell **slam 1** AOE; dash **path 1**. Goal: ~6-organ stacks survive **~3 claw hits** (soil bonus still meaningful).
- Soil: +1 melee damage (attacker). Rock: +1 ranged (attacker); −1 incoming ranged (defender, min 1). Sand: +1 move range.
- **Eye**: `ranged` range **6**, **2** chip, cooldown **1** (once per your turn after act).
- Obstacles: melee/ranged can damage **destructible blockers**; **hero props** (landmark mushrooms, blobs, rocks) are destructible and leave **loose debris** when destroyed.
- Soil HP regen **disabled** (organs are discrete 1-HP parts).
- **Hazards** (snare/mine): owner stepping on own trap does **not** disarm it; only enemies trigger and consume. Cannot plant on a cell that already has a hazard.

## Rendering
- World: 3D voxels; **K1 mood** = soft fungal mycelium checker (darker, low-contrast), rock as calcified mushroom stone, sand as spore crust; dark void backdrop.
- Spawn pools: muted amber **slime-mold vein** pads with faint **beveled square** rim — not neon discs or hexes. Visible during **gene offer** only (turns 1–2 pulse bright mint on active seat); **hidden in action/move** so cyan reach + selection + amber egress stay readable. CP gold zone paint is **demoted** until that seat has ≥1 Mutant.
- Obstacles: billboarded **weird mushroom** alpha sprites (6 species × 3 yaw frames; **frame follows camera yaw** + flip; **FIXED_Y** billboard so feet plant on tile tops — not full billboard float; slight scale jitter; destructible tint warmer). Per board, **4–6 hero props** are drawn from a larger pool (giant mushrooms, organic blobs, old rocks) as large landmark blockers.
- Mutants: per-organ **dithered** emoji billboards in a **spaced** humanoid layout (yaw to camera); rematch-in-place on attach (no deferred free duplicates); soft depth jiggle; debug dither on/strength/levels; spring jiggle + hit impulse.
- **Post dither**: fullscreen ordered Bayer (Elfenstein port) over the whole frame (3D + HUD + menus); F3 debug for strength / colour preserve / pixel / levels / matrix / palette / lift-gain-gamma; on by default.
- **Move**: Mutants tween between cells with a hop + stride jiggle (not a hard snap).
- **Hover**: mouse-near organ gets a stronger jiggle / scale punch.
- **Organ death**: destroyed organs detach as `RigidBody3D` corpses onto the board floor and **stay** (**grayed** emoji tint — unusable debris, not loot); yellow-amber **particle splatter** at the pop + lasting **floor splat decal**; impact debris persists after settling. Field gear the selected mutant **cannot** graft (hard max / non-reclaimable) is **grayed** the same way.
- **Ragdoll**: living Mutants use **jointed organ RigidBodies** — control mode freezes + jiggles; hits/abilities briefly ragdoll then **re-seat** to the cell pose (grid position never drifts).
- **Battlefield juice**: ability resolve shoves force-tagged bodies (corpses + **settled debris**); light chunks (`force_light`) loft harder; living organs ragdoll separately. Heavy abilities spawn loose **cut mushroom-matter** billboard chunks; atmosphere = top **light shaft** + physics-reactive dust/clouds; **contact shadows** under organs/corpses/debris; pooled burst + hit sparks.
- Readability: selection, reachables, attackables; amber **available-turn** cell tint + pulse rings on Mutants that still can move/act; mint attach rings when a gene is pending; gene-offer spawn highlights; **CP zones gold** (stronger 3×3 pads + bevel edges + beacon — demoted only until seat has a Mutant) vs **move reach cyan**; **ability telegraphs** — soft violet reach, amber impact AoE/line/path on hover, toxin-green trap plant, orange delayed footprints (full AoE); **Slam** arms with AoE telegraph and requires confirm (re-click self / press again); brief resolve cell flash; hover info chip + gene cartridge tooltips. **END** blinks when the seat has no eligible moves/actions; MOVE + ready abilities warm-highlight when usable. Destructible obstacles highlight orange in melee/ranged and pop `DESTROYED` when cleared.
- **Control Points**: three CPs spaced **±5** from center on x; odd boards use mid-row, even boards nudge CP toward the **second** player (`h/2 - seed%2`) so first-player tempo cancels the shorter home→CP path; **3×3 capture zone** = dark underlay + gold wash + outer perimeter frame + taller beacon/tip (demoted until seat has a Mutant); flag meters; billboard state (`NEUTRAL` / `P# HELD` / `P# n/need` / `CONTESTED`).
- **Camera**: ortho pan/zoom/rotate; **clamped to the board** (zoomed-out keeps playfield on-screen; zoom-out capped near fit). **Knockout sweep** on organ shed (Chillout exceptional-replay grammar). **Demo mode** auto-frames action cells.
- **HUD (K1 wet-mud)**: board-first — dark low-contrast clay chrome (`wet_clay_canvas`, **pixel-stable** grain — no UV stretch); fake-3D **extrude rim** + contact shadow + stamp wells / embossed type; light type on slabs; phase plaque (`OFFER`/`ACTION` / TURN), twin extruded hex **ZONES** gems with **P1/P2** seat labels (`owned/need`), gene cartridges (face verb only; full blurb in tooltip), MOVE/END/ability keys (press **0.96**); squad inspect shows stack emojis when selected (clay backplate hides with panel); debug `…` is a tiny flat chip (dock collapsed when closed; hidden during offers). System sans for words.
- **Pointer priority**: HUD chrome (`ui_blocks_board_hover`) owns hover — board cell highlight + organ jiggle clear while the cursor is over UI; action/gene/CP controls show amber hover feedback. First-match **Quick rules** is a full-screen modal (Esc / Got it / dimmer dismiss); pause menu will not open underneath it.

## Networking / Meta
- **Web publish**: Godot HTML5 export (`export_presets.cfg` → committed `web/`) hosted on **Vercel** with COOP/COEP for threaded WASM (`vercel.json` outputDirectory `web`; `tools/export_web.sh`). UI uses bundled **Noto Sans** + **Noto Color Emoji** (Web cannot load system fonts).
- Authoritative WS stack exists from Chess 2 fork; **not** required for this MVP organ slice.
- **Main menu** (`MenuFlow.tscn`): **Hot-seat** (72-pt gene deck prep → match), **Demo** (AI vs AI loop + tempo), **Settings** (`user://settings.cfg`), **Exit**. **CRT-era rounded terminal** shell — amber phosphor, pill buttons, rounded bezel; **no** barrel distortion or scanlines; title shows one short readable line (“Hot-seat tactics — pass the device.”); main screen board vignette carries an **emoji mutant ghost**; Settings **FULLSCREEN / VSYNC** and Demo **tempo** pills: filled phosphor when ON/selected, outline when OFF; rules teaching lives on **opening prompt** + **first egress** toast + first **1-of-3** specialty toast. Dev skip: `--match` boots straight into `Main.tscn`.
- **Demo AI** (`DemoAI.gd`): six styles — **rush** (ram-first, soft cap **2**, max **1** body, gap-close after turn **>10**), **kite** (one deep eye stack, soft **7**, shoot at **3–6**; flee ≤**2**; contest CP when foe >**2** away; railgun after eye), **tank** (plate×3, soft **5**, leave at **2** organs, second body after **2**, claw-before-shell, slam-first, peel ≤**7**, charge after turn **>3**, sit safe CP), **control** (dual gland + claw, spawn up to **3** bodies, soft **4**, snare→CP sit), **swarm** (soft **3**), **balanced** (soft **4**, max **2** bodies, no field-graft / no dash). Round-robin in `playtest_style_roundrobin.gd` (gates: control≥4, balanced≤6, rush≥3≤6, kite≥3, tank≥3, swarm≤9, CP≥8, max≤12); `playtest_30_matches` uses the same 15×2 pair schedule.
- **Opening offer**: opening hand hard-biases teaching genes; prefers unique faces (keeps intentional **eye/hoof** doubles); unavoidable dups show **×N** on cartridges; teaching guarantee **core** + combat gene when inventory allows; specialty swapped out when simpler genes remain; **Skip** full-bright once allowed (dim but readable while locked). Cartridge blurbs use `Verb · detail` (e.g. `Melee · 2 dmg`, `Shoot · r6 / 2 dmg / cd1`); turn-1 offer prompt: **Pick 2 · place each on a glowing home pad — that becomes your Mutant.** (leave-lock teaching on **first-egress** toast only).
- **Hot-seat prep**: default bay = style pills + specimen rack + Lock; gene **catalog** behind **Customize**; CLEAR is a text link (not a style pill). Rack packs existing gene cards left in HFlow (~4/row); readable sans for gene names + **GENE_BLURBS** `Verb · detail` under each cartridge.
- **Mutant organs** read vs mushroom props via **2.2×** scale + soft team rim/tint + **team corner brackets** on the cell (idle α**0.22** / half**0.36**; selected α**0.42** / half**0.40**); availability/fresh rings stay soft single bevels; HP pip cubes match **team color**; mushrooms idle **α~0.72** (heroes ×**0.85**; on select/move ~**0.58**/0.48, heroes ×**0.70**) — alpha-cut scissor stays **below** modulate α so props stay visible. Eggs = opaque green/red balls (no content peek); gear = organ emoji only. Action-phase select prompt: **Select: Move or {ability}** + **Stack: {emoji list}**; ability keys show organ emoji. Ineligible act → toast + hover chip + board pop/flash + mutant warn pulse (`FRESH` / `SPENT` / `ENEMY` / `BLOCKED` / …).
- First entry into a **CP zone** toasts once: “Hold 2 of 3 zones (flags add up).”
- Out of scope: meta progression beyond in-match gene pool (except hot-seat deck editing).

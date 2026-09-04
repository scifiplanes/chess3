# Main menu — research & concept brief

**Status:** visual concepts only (no implementation yet).  
**Gallery:** open `index.html` in a browser.

## Design language (v2 — CRT era, **preferred**)

Reference: `docs/hud-concepts/hud-concept-a-cryo-crt.png` (KOS-MOS biostrategic terminal).

- **Shell:** menus live **inside a curved CRT viewport** — thick rounded bezel, barrel distortion, vignette.
- **Phosphor:** warm **amber** primary (with P1 cyan / P2 coral accents only where needed); scanlines + soft bloom; subtle ghosting on title text.
- **Shapes:** **rounded** everywhere — pill buttons, rounded-rect panels, circular/stepped sliders; **no sharp octagons** or gunmetal plates on menus.
- **Typography:** monospace / dot-matrix for labels; display face for CHESS 3 title (phosphor feel).
- **Tone:** 1980s biostrategic analysis terminal — specimen logistics, not gore. Menus are the “console”; in-match HUD can stay K1 floating chrome.
- **Layout:** full-screen CRT sheet (unlike board-first match HUD); faint board/mycelium visible through glass on main menu.

### v1 (superseded)
Angular K1 metal keys — kept in gallery for comparison only.

## Navigation map

```
MAIN MENU
├── Hot-seat → Match Preparation → [Match]
├── Demo     → [Auto loop: match → interstitial → match …]
├── Settings → (back to Main)
└── Exit
```

## 1 — Main menu

| Option | Action |
|--------|--------|
| **Hot-seat** | Local 2P; deck prep then standard match (human offer + actions). |
| **Demo** | Spectator loop: two AIs, random seeds/styles, watchable tempo. |
| **Settings** | Audio, default demo tempo, display, camera sensitivity. |
| **Exit** | Quit application. |

**UX notes**
- Default focus: Hot-seat (first item).
- Keyboard: ↑↓ navigate, Enter confirm, Esc = Exit on main menu only.
- Title **CHESS 3** + optional subtitle (*Mutants / Organs*) — keep short.

## 2 — Hot-seat prep (direction v3 — loadout bay)

**Default:** Loadout bay · one player at a time (P1 → handoff → P2).  
**Optional tab:** Gene draft ritual (same shell).

### 02b — Loadout bay
- Title `LOADOUT BAY · P#` · mode pills `LOADOUT` | `DRAFT`
- **CAPACITANCE** bar (`spent / 72`) — not a spreadsheet column
- Style pills: BALANCED / RUSH / KITE / TANK / SWARM / CLEAR
- **Specimen rack:** only genes in the loadout as K1-style cartridges (`emoji · name · ×N · pt`)
- Footer: `BACK` | `LOCK · PASS TO P2` (P1) / `START MATCH` (P2)
- Concepts: `menu-concept-02b-loadout-bay.png`

### 02c — Customize catalog
- Secondary wall of draftable gene tiles (tap to add)
- Rack remains the truth; no dual scrolling ledgers
- Concept: `menu-concept-02c-loadout-catalog.png`

### 02d — Gene draft (optional)
- Same shell; DRAFT selected
- **Offer pack** of 5 cartridges (in-match offer muscle memory)
- Pick 1 → add to rack → new pack; **REROLL PACK** skips
- Lock when valid (≥1 core, ≤72)
- Concept: `menu-concept-02d-gene-draft.png`

### 02e — Pass handoff
- Full-screen overlay after P1 locks: `PASS DEVICE TO PLAYER 2`
- Concept: `menu-concept-02e-pass-handoff.png`

### Superseded (02 CRT split)
Dual P1/P2 panels with gene rows + −/+ steppers — Excel with CRT skin. Kept in gallery for comparison.

### Deck rules (unchanged budget)
- Cap **72**; ≥1 `core`; max per gene **10**; presets must validate.
- Style presets: default/balanced, rush, kite, tank, swarm.

## 3 — Demo mode (AI spectator loop)

Endless **randomized matches** using existing playtest AI (`playtest_30_matches` style: styles, offer pick-1, act, end turn).

### During match (concept 03)
- Full board + K1 HUD (gene tray hidden or auto-plays for AI).
- **Overlay chrome only:**
  - `DEMO · MATCH ###` (top-left)
  - **Tempo:** `SLOW | NORMAL | FAST` + slider (applies next turn boundary)
  - `PAUSE` | `SKIP TURN` (debug/spectator)
  - Bottom strip: `AI vs AI · seed #### · rush vs kite` (style names)

### Tempo timing (proposal)

| Step | Slow | Normal | Fast |
|------|------|--------|------|
| Offer pick | 1.2s | 0.5s | 0.15s |
| Action anim + sim | 2.0s | 0.9s | 0.25s |
| End turn | 0.8s | 0.4s | 0.1s |
| Between-match card | 3.0s | 1.5s | 0.5s |

Human-readable: Normal ≈ one full turn every **~2s**; Slow for study; Fast for attract-mode wall display.

### Between matches (concept 05)
- Result card: winner + reason (elim / CP / timeout).
- **Auto-advance** countdown (3…2…1) → next random seed + style assignment.
- Controls: `CHANGE TEMPO`, `PAUSE LOOP`, `EXIT TO MENU`.
- Streak counter optional (`Match 047`).

### AI source
- Reuse `_play_offer` / `_play_actions` from `tools/playtest_30_matches.gd` (extract to `DemoDirector` later).
- Random seed per match; styles independent per side.

## 4 — Settings

| Section | Controls |
|---------|----------|
| **Audio** | Master, SFX, UI sliders |
| **Demo** | Default tempo (Slow/Normal/Fast) |
| **Display** | Fullscreen, VSync |
| **Controls** | Camera pan/zoom sensitivity |

Persist to `user://settings.cfg` (Godot ConfigFile). BACK → Main menu.

## Implementation checklist (later)

- [ ] `MainMenu.tscn` + scene stack (Menu → Prep → Game → Menu)
- [ ] `DeckEditor` UI widget (reuse `K1GeneCartridge`)
- [ ] `GameState.setup` accepts custom `player_inventory` dicts
- [ ] `DemoDirector` node: async turn loop + tempo delays
- [ ] Wire Settings persistence
- [ ] Replace direct `Main.tscn` boot with menu entry (keep debug skip flag)

## Concept files

| File | Screen |
|------|--------|
| `menu-concept-01-main-crt.png` | Main menu (CRT v2) |
| `menu-concept-02-hotseat-prep-crt.png` | Hot-seat deck prep (CRT v2 · superseded Excel split) |
| `menu-concept-02b-loadout-bay.png` | Loadout bay default (v3) |
| `menu-concept-02c-loadout-catalog.png` | Bay customize catalog wall |
| `menu-concept-02d-gene-draft.png` | Optional gene draft ritual |
| `menu-concept-02e-pass-handoff.png` | Pass-device handoff overlay |
| `menu-concept-03-demo-spectator-crt.png` | Demo in-match spectator (CRT v2) |
| `menu-concept-04-settings-crt.png` | Settings (CRT v2) |
| `menu-concept-05-demo-between-crt.png` | Demo interstitial (CRT v2) |
| `menu-concept-01-main.png` … | v1 angular K1 (archived) |

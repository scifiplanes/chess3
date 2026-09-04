# Chess 3

Turn-based tactics on a 3D voxel board. Pieces are **Mutants** built from **Organs**. Godot **4.7**.

Repo: [github.com/scifiplanes/chess3](https://github.com/scifiplanes/chess3)

## Run (desktop)

Open the project in Godot 4.7 and press Play (`MenuFlow.tscn`).

```bash
"/Applications/Godot 4.7.app/Contents/MacOS/Godot" --path .
```

## Web export → Vercel

Threaded WebAssembly needs cross-origin isolation. `vercel.json` sets `COOP` / `COEP` / `CORP`.

```bash
# Export → web/ (then commit + push so Vercel can deploy)
bash tools/export_web.sh

# Or export + CLI production deploy
bash tools/export_web.sh --deploy
```

Requires Godot **4.7.x** with **Web** export templates installed (`Editor → Manage Export Templates`).

### Git-connected Vercel

`vercel.json` sets **Output Directory** to `web`. That folder is committed (Vercel does not run Godot). Re-export and push whenever the game build should update.

## Docs

- `DESIGN.md` — living design decisions
- `CHANGELOG.md` — notable changes
- `docs/` — specs and concept boards

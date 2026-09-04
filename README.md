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
# Export only → build/web/
bash tools/export_web.sh

# Export + production deploy (needs Vercel CLI login / linked project)
bash tools/export_web.sh --deploy
```

Requires Godot **4.7.x** with **Web** export templates installed (`Editor → Manage Export Templates`).

### Git-connected Vercel

Point the Vercel project at this repo with **Output Directory** `build/web`. The build must already exist (run `tools/export_web.sh` in CI or deploy the folder with the CLI above). Vercel’s default cloud build does not run Godot.

## Docs

- `DESIGN.md` — living design decisions
- `CHANGELOG.md` — notable changes
- `docs/` — specs and concept boards

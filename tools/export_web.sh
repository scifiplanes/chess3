#!/usr/bin/env bash
# Export Chess 3 for Web and optionally deploy the static build to Vercel.
#
#   tools/export_web.sh            # export only → web/
#   tools/export_web.sh --deploy   # export + vercel deploy --prod
#
# Override Godot with GODOT=/path/to/Godot (expects 4.7.x + web export templates).
# After export, commit web/ so Git-connected Vercel deploys have an output directory.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRESET="Web"
OUT_DIR="web"
OUT_HTML="${OUT_DIR}/index.html"

DEPLOY=0
VERCEL_EXTRA=()
while [[ $# -gt 0 ]]; do
	case "$1" in
		--deploy)
			DEPLOY=1
			shift
			;;
		*)
			if [[ $DEPLOY -eq 1 ]]; then
				VERCEL_EXTRA+=("$1")
				shift
			else
				echo "Unknown arg: $1" >&2
				echo "Usage: $0 [--deploy [vercel args...]]" >&2
				exit 2
			fi
			;;
	esac
done

resolve_godot() {
	if [[ -n "${GODOT:-}" ]]; then
		echo "$GODOT"
		return
	fi
	if command -v godot >/dev/null 2>&1; then
		command -v godot
		return
	fi
	local candidates=(
		"/Applications/Godot 4.7.app/Contents/MacOS/Godot"
		"/Applications/Godot.app/Contents/MacOS/Godot"
	)
	local c
	for c in "${candidates[@]}"; do
		if [[ -x "$c" ]]; then
			echo "$c"
			return
		fi
	done
	echo "Godot binary not found. Set GODOT= or install Godot 4.7." >&2
	exit 1
}

GODOT_BIN="$(resolve_godot)"
VERSION="$("$GODOT_BIN" --version 2>/dev/null || true)"
echo "Using Godot: $GODOT_BIN ($VERSION)"

mkdir -p "$OUT_DIR"
# Keep Godot from importing/scanning export artifacts as project assets.
printf '# Ignore export output from Godot filesystem scanner.\n' > "${OUT_DIR}/.gdignore"

echo "Exporting preset \"$PRESET\" → $OUT_HTML"
"$GODOT_BIN" --headless --path "$ROOT" --export-release "$PRESET" "$OUT_HTML"

if [[ ! -f "$OUT_HTML" ]]; then
	echo "Export failed: $OUT_HTML missing. Install web export templates for this Godot version." >&2
	exit 1
fi

find "$OUT_DIR" -name '*.import' -delete

# Headers-only config for `vercel deploy --cwd web` (root vercel.json drives Git deploys).
python3 - <<'PY'
import json
from pathlib import Path
root = Path("vercel.json")
cfg = json.loads(root.read_text())
slim = {"headers": cfg.get("headers", [])}
Path("web/vercel.json").write_text(json.dumps(slim, indent=2) + "\n")
PY

echo "Export OK:"
ls -lh "$OUT_DIR" | sed -n '1,20p'

if [[ $DEPLOY -eq 0 ]]; then
	echo "Done (export only). Deploy with: $0 --deploy"
	exit 0
fi

resolve_vercel() {
	if command -v vercel >/dev/null 2>&1; then
		command -v vercel
		return
	fi
	if command -v npx >/dev/null 2>&1; then
		echo "npx"
		return
	fi
	echo ""
}

VERCEL_BIN="$(resolve_vercel)"
if [[ -z "$VERCEL_BIN" ]]; then
	echo "vercel CLI not found. Install: npm i -g vercel" >&2
	exit 1
fi

echo "Deploying ${OUT_DIR} to Vercel (prod)..."
vercel_args=(deploy --prod --cwd "$OUT_DIR" --yes)
if ((${#VERCEL_EXTRA[@]} > 0)); then
	vercel_args+=("${VERCEL_EXTRA[@]}")
fi
if [[ "$VERCEL_BIN" == "npx" ]]; then
	npx --yes vercel "${vercel_args[@]}"
else
	"$VERCEL_BIN" "${vercel_args[@]}"
fi

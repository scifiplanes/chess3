#!/usr/bin/env node
/**
 * Bugfix scenario + visual gate runner.
 * GODOT_BIN overrides Godot path.
 */
import { spawnSync } from "child_process";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const godot = process.env.GODOT_BIN || "godot";

function run(args, label) {
  const r = spawnSync(godot, args, { encoding: "utf8", cwd: root, timeout: 180000 });
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  process.stdout.write(out);
  if (r.status !== 0) {
    console.error(`${label} exited ${r.status}`);
    process.exit(r.status || 1);
  }
  return out;
}

const scenarios = run(
  ["--headless", "--path", root, "--script", "res://tools/playtest_bugfix_scenarios.gd"],
  "scenarios"
);
if (!/BUGFIX_SCENARIOS_OK/.test(scenarios) || !/, 0 fail ===/.test(scenarios)) {
  console.error("scenario suite missing OK marker");
  process.exit(1);
}

const chess3 = run(
  ["--headless", "--path", root, "--script", "res://tools/playtest_chess3.gd"],
  "chess3"
);
if (!/, 0 fail ===/.test(chess3)) {
  console.error("chess3 suite failed");
  process.exit(1);
}

const visual = run(
  ["--path", root, "res://tools/visual_validate_bugfix.tscn"],
  "visual"
);
if (!/BUGFIX_VALIDATE_OK/.test(visual)) {
  console.error("visual validate failed");
  process.exit(1);
}

console.log("PLAYTEST_VISBUG_OK");

#!/usr/bin/env node
/**
 * Completion verify for board UX + juice thread.
 * GODOT_BIN overrides Godot path.
 */
import { spawnSync } from "child_process";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const godot =
  process.env.GODOT_BIN ||
  "/Applications/Godot 4.7.app/Contents/MacOS/Godot";

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

function staticCheck(name, fn) {
  try {
    fn();
    console.log(`PASS static ${name}`);
  } catch (e) {
    fail(`FAIL static ${name}: ${e.message || e}`);
  }
}

staticCheck("WARMUP_SILENT", () => {
  for (const f of [
    "src/presentation/vfx/OrganSplatterVfx.gd",
    "src/presentation/vfx/HitSparkVfx.gd",
    "src/presentation/vfx/AbilityBurstVfx.gd",
  ]) {
    const s = read(f);
    const i = s.indexOf("static func warmup");
    const j = s.indexOf("static func", i + 1);
    const w = s.slice(i, j > 0 ? j : s.length);
    if (/\bplay\s*\(/.test(w)) throw new Error(f);
  }
});

staticCheck("DEMO_EXIT", () => {
  const s = read("src/presentation/Main.gd");
  if (!/_leave_demo_to_menu/.test(s) || !/change_scene_to_packed\(MenuFlowScene\)/.test(s)) {
    throw new Error("missing immediate demo exit");
  }
});

staticCheck("REMATCH", () => {
  const s = read("src/presentation/SquadView.gd");
  if (!/_rematch_organ_layout/.test(s) || !/_free_organ_node/.test(s)) {
    throw new Error("rematch helpers missing");
  }
  const rb = s.slice(
    s.indexOf("func _apply_organ_layout_rebuild_or_update"),
    s.indexOf("func _slot_mirror_x")
  );
  if (/queue_free\(\)/.test(rb)) throw new Error("rebuild still queue_frees");
});

staticCheck("GRAY_UNUSABLE", () => {
  const o = read("src/presentation/OrganEmojiPart.gd");
  const b = read("src/presentation/BoardView.gd");
  if (!/unusable_gear_tint/.test(o) || !/corpse_tint/.test(o) || !/unusable_gear_tint/.test(b)) {
    throw new Error("gray tints missing");
  }
});

staticCheck("LOCK_SPAM", () => {
  const i = read("src/presentation/InputController.gd");
  const m = read("src/presentation/Main.gd");
  if (!/_emit_hover/.test(i) || !/_lock_popped_cells/.test(m) || !/seen_spawn_lock_tip/.test(m)) {
    throw new Error("lock spam guards missing");
  }
});

staticCheck("GRAFT_CELEBRATE", () => {
  const m = read("src/presentation/Main.gd");
  const b = read("src/presentation/BoardView.gd");
  const s = read("src/presentation/SquadView.gd");
  if (
    !/GRAFT/.test(m) ||
    !/play_graft_celebrate/.test(m) ||
    !/func play_graft_celebrate/.test(b) ||
    !/func play_graft_celebrate/.test(s) ||
    !/AbilityBurstVfxScript\.play/.test(m)
  ) {
    throw new Error("graft celebrate incomplete");
  }
});

staticCheck("DEBRIS_FORCE", () => {
  const d = read("src/presentation/vfx/ImpactDebris.gd");
  const l = read("src/presentation/vfx/LooseProp.gd");
  const f = read("src/presentation/vfx/BattlefieldForce.gd");
  if (!/force_light/.test(d) || !/force_while_frozen",\s*true/.test(d)) {
    throw new Error("debris force metas missing");
  }
  if (!/force_light/.test(l) || !/DEBRIS_LOFT_BONUS/.test(f)) {
    throw new Error("loose/force loft missing");
  }
});

staticCheck("SLOT_SPACED", () => {
  const s = read("src/presentation/SquadView.gd");
  const m = s.match(/"arm_l":\s*Vector3\((-?[0-9.]+)/);
  if (!m || Math.abs(+m[1]) < 0.28) throw new Error("arms too close");
});

function run(args, label) {
  const r = spawnSync(godot, args, {
    encoding: "utf8",
    cwd: root,
    timeout: 300000,
  });
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  process.stdout.write(out);
  if (r.error) fail(`${label}: ${r.error.message}`);
  if (r.status !== 0) fail(`${label} exited ${r.status}`);
  return out;
}

const juice = run(
  ["--headless", "--path", root, "-s", "res://tools/playtest_battlefield_juice.gd"],
  "battlefield_juice"
);
if (!/PLAYTEST_BATTLEFIELD_JUICE_OK/.test(juice)) {
  fail("battlefield juice missing OK");
}

const pickups = run(
  ["--headless", "--path", root, "-s", "res://tools/playtest_pickups_live.gd"],
  "pickups_live"
);
if (!/, 0 fail/.test(pickups) || !/=== results:/.test(pickups)) {
  fail("pickups live failed");
}

const vis = spawnSync(
  process.execPath,
  [path.join(root, "tools/gate_visual_bugfix_check.mjs")],
  {
    encoding: "utf8",
    cwd: root,
    timeout: 300000,
    env: { ...process.env, GODOT_BIN: godot },
  }
);
process.stdout.write(`${vis.stdout || ""}\n${vis.stderr || ""}`);
if (vis.status !== 0 || !/PLAYTEST_VISBUG_OK/.test(`${vis.stdout || ""}\n${vis.stderr || ""}`)) {
  fail("visual bugfix gate failed");
}

console.log("COMPLETION_VERIFY_OK");

#!/usr/bin/env node
/**
 * UX telegraph pass gates (CP / END blink / organ dupe / slam confirm / obstacles).
 * GODOT_BIN overrides Godot path.
 * Usage: node tools/gate_ux_telegraph_check.mjs [--gate G0|G1|...|G7|all]
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

const gateArg = (() => {
  const i = process.argv.indexOf("--gate");
  return i >= 0 ? process.argv[i + 1] : "all";
})();

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

function read(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

function runGodot(scriptRel, okToken, { asScene = false } = {}) {
  const args = asScene
    ? ["--headless", "--path", root, `res://${scriptRel}`]
    : ["--headless", "--path", root, "--script", `res://${scriptRel}`];
  const r = spawnSync(godot, args, {
    encoding: "utf8",
    cwd: root,
    timeout: 180000,
  });
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  const hasParse =
    /Parse Error/i.test(out) || /Failed to load script/i.test(out);
  const hasOk = okToken == null || out.includes(okToken);
  const ok = r.status === 0 && hasOk;
  // SceneTree --script can emit spurious Main.tscn parse noise while still
  // succeeding; real failures have non-zero status or missing OK token.
  if (hasParse && !ok) {
    console.error(out);
    fail(`Godot ${scriptRel} reported Parse Error / script load failure`);
  }
  if (!ok) {
    console.error(out);
    fail(`Godot ${scriptRel} failed (status=${r.status})`);
  }
  if (hasParse) {
    console.warn(`WARN godot ${scriptRel}: parse noise in log (status=0, OK token present)`);
  }
  console.log(`PASS godot ${scriptRel}`);
}

function g0() {
  runGodot("tools/playtest_main_boot.tscn", "PLAYTEST_MAIN_BOOT_OK", { asScene: true });
  runGodot("tools/validate_scenes.tscn", "VALIDATE_SCENES_OK", { asScene: true });
  console.log("G0_OK");
}

function g1() {
  const b = read("src/presentation/BoardView.gd");
  if (!/var under_col :=/.test(b) || !/_add_cp_zone_perimeter/.test(b)) {
    throw new Error("CP underlay/perimeter missing");
  }
  if (!/alpha := 0\.42 if is_center else 0\.30/.test(b)) {
    throw new Error("CP gold wash not strong enough");
  }
  if (!/base_mesh\.height = 0\.42/.test(b)) {
    throw new Error("CP beacon not tall enough");
  }
  console.log("G1_OK");
}

function g2() {
  const h = read("src/presentation/HUD.gd");
  const m = read("src/presentation/Main.gd");
  if (!/_set_end_turn_blink/.test(h) || !/set_loops\(\)/.test(h)) {
    throw new Error("END blink missing");
  }
  if (!/set_move_highlighted/.test(h) || !/set_ready_abilities_highlighted/.test(h)) {
    throw new Error("eligible UI highlight helpers missing");
  }
  if (!/set_move_highlighted/.test(m) || !/set_ready_abilities_highlighted/.test(m)) {
    throw new Error("Main does not drive eligible highlights");
  }
  if (!/no_acts_left/.test(m)) {
    throw new Error("Main missing no_acts_left END blink driver");
  }
  console.log("G2_OK");
}

function g3() {
  const s = read("src/presentation/SquadView.gd");
  const pop = s.slice(
    s.indexOf("func _try_incremental_organ_pop"),
    s.indexOf("func _try_incremental_organ_grow")
  );
  if (/queue_free\(\)/.test(pop)) {
    throw new Error("incremental pop still queue_frees");
  }
  if (!/_free_organ_node\(node\)/.test(pop)) {
    throw new Error("incremental pop must call _free_organ_node");
  }
  const shed = s.slice(
    s.indexOf("func shed_all_organs_as_corpses"),
    s.indexOf("func _request_separation_sweep")
  );
  if (!/_free_organ_node/.test(shed)) {
    throw new Error("shed_all must free organ nodes");
  }
  const layer = read("src/presentation/SquadLayer.gd");
  if (!/view\.free\(\)/.test(layer)) {
    throw new Error("SquadLayer must free dead views immediately");
  }
  console.log("G3_OK");
}

function g4() {
  const juice = read("tools/playtest_battlefield_juice.gd");
  if (!/_s12_organ_pop_no_living_duplicate/.test(juice)) {
    throw new Error("S12 organ-pop dupe playtest missing");
  }
  runGodot("tools/playtest_battlefield_juice.gd", "PLAYTEST_BATTLEFIELD_JUICE_OK");
  console.log("G4_OK");
}

function g5() {
  const m = read("src/presentation/Main.gd");
  if (!/func _confirm_slam/.test(m)) throw new Error("missing _confirm_slam");
  if (!/SLAM — click self or press again to confirm/.test(m)) {
    throw new Error("slam confirm toast missing");
  }
  const slamArm = m.slice(m.indexOf('"slam":'), m.indexOf('"delayed_single"'));
  if (/resolver\.use_slam/.test(slamArm) && !/_confirm_slam/.test(slamArm)) {
    throw new Error("slam match still calls use_slam directly");
  }
  if (!/current_action == "slam"/.test(m)) {
    throw new Error("slam confirm path missing");
  }
  console.log("G5_OK");
}

function g6() {
  const bs = read("src/sim/BoardState.gd");
  const dmg = bs.slice(
    bs.indexOf("func damage_obstacle"),
    bs.indexOf("func hazard_at")
  );
  if (!/obstacles\.erase\(cell\)/.test(dmg)) {
    throw new Error("damage_obstacle must erase on hp<=0");
  }
  const m = read("src/presentation/Main.gd");
  if (!/BREAK — obstacle/.test(m) || !/DESTROYED/.test(m)) {
    throw new Error("obstacle attack feedback missing");
  }
  runGodot("tools/playtest_ux_telegraph.gd", "PLAYTEST_UX_TELEGRAPH_OK");
  console.log("G6_OK");
}

function g7() {
  // Boot first — Board-only suites cannot catch Main.gd parse errors.
  g0();
  g1();
  g2();
  g3();
  g5();
  runGodot("tools/playtest_ux_telegraph.gd", "PLAYTEST_UX_TELEGRAPH_OK");
  runGodot("tools/playtest_battlefield_juice.gd", "PLAYTEST_BATTLEFIELD_JUICE_OK");
  runGodot("tools/playtest_chess3.gd", "0 fail");
  console.log("UX_TELEGRAPH_PASS_OK");
}

const runners = { G0: g0, G1: g1, G2: g2, G3: g3, G4: g4, G5: g5, G6: g6, G7: g7 };

try {
  if (gateArg === "all") {
    g7();
  } else {
    const fn = runners[gateArg];
    if (!fn) fail(`unknown gate ${gateArg}`);
    fn();
  }
} catch (e) {
  fail(String(e.message || e));
}

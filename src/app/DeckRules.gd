extends RefCounted
class_name DeckRules

const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

## Hot-seat deck prep: point budget and validation.

const BUDGET := 72
const MAX_PER_GENE := 10

const GENE_COSTS := {
	"core": 1,
	"chunk": 1,
	"hoof": 1,
	"brood": 2,
	"plate": 2,
	"claw": 2,
	"eye": 2,
	"spring": 2,
	"phase": 2,
	"gland": 2,
	"spore": 2,
	"shell": 2,
	"ram": 3,
	"node": 3,
	"vent": 3,
	"spine": 3,
	"leap": 3,
	"synapse": 3,
	"pod": 3,
	"beacon": 4,
	"anchor": 3,
}

const GENE_NAMES := {
	"core": "Cardiac Core",
	"claw": "Ripper Claw",
	"hoof": "Stride Hoof",
	"eye": "Scout Eye",
	"gland": "Snare Gland",
	"shell": "Shock Shell",
	"ram": "Ram Crest",
	"node": "Fuse Node",
	"vent": "Vent Sac",
	"spine": "Rail Spine",
	"spring": "Spring Coil",
	"leap": "Leap Muscle",
	"synapse": "Synapse Link",
	"plate": "Graft Plate",
	"chunk": "Biomass Chunk",
	"beacon": "Strike Beacon",
	"spore": "Spore Mine",
	"pod": "Burst Pod",
	"phase": "Phase Gland",
	"brood": "Brood Sack",
	"anchor": "Anchor Node",
}

const GENE_BLURBS := {
	"core": "Spawn · home pad",
	"claw": "Melee · 2 dmg",
	"hoof": "Run · 3",
	"eye": "Shoot · r6 / 2 dmg / cd1",
	"gland": "Snare · r1 / cd4",
	"shell": "Slam · neighbors 1",
	"ram": "Charge · 2 + push",
	"node": "Strike · delayed 1 cell",
	"vent": "Blast · delayed AoE",
	"spine": "Rail · line shot",
	"spring": "Jump · 3",
	"leap": "Pounce · splash",
	"synapse": "Swap · two friendlies",
	"plate": "Armor · 4 HP",
	"chunk": "Pad · +1 HP",
	"beacon": "Strike · delayed cross",
	"spore": "Mine · 2 dmg",
	"pod": "Mine · 3 + splash",
	"phase": "Teleport · 4",
	"brood": "Spawn · +1 ring",
	"anchor": "Spawn · cross +2",
}

const DEFAULT_POOL := {
	"core": 9,
	"claw": 7,
	"hoof": 6,
	"eye": 5,
	"shell": 4,
	"plate": 4,
	"ram": 3,
	"spring": 4,
}

const PRESETS := {
	"default": DEFAULT_POOL,
	"rush": {"core": 5, "claw": 8, "hoof": 7, "ram": 5, "leap": 2, "spring": 2, "chunk": 3, "plate": 2, "eye": 2, "shell": 2, "spore": 2},
	"kite": {"core": 5, "eye": 8, "spine": 3, "beacon": 2, "node": 2, "phase": 3, "spring": 3, "brood": 2, "chunk": 4, "gland": 2, "spore": 2},
	"tank": {"core": 5, "plate": 8, "shell": 7, "chunk": 8, "ram": 3, "claw": 2, "hoof": 2, "eye": 2, "gland": 2, "vent": 2},
	"swarm": {"core": 10, "hoof": 10, "claw": 7, "chunk": 8, "brood": 5, "eye": 3, "spore": 3, "spring": 2, "gland": 2},
	"clear": {},
}

static func style_presets() -> Array[String]:
	return ["default", "rush", "kite", "tank", "swarm"]

static func all_genes() -> Array[String]:
	return UnitDefsScript.all_gene_ids()

static func draftable_genes() -> Array[String]:
	var out: Array[String] = []
	for gid in GENE_COSTS.keys():
		out.append(str(gid))
	out.sort()
	return out

## Five unique draftable genes for ritual packs. Prefer genes that still fit budget.
static func draft_pack(inv: Dictionary, rng: RandomNumberGenerator, count: int = 5) -> Array[String]:
	var pool: Array[String] = draftable_genes()
	var spent := point_cost(inv)
	var room := BUDGET - spent
	var affordable: Array[String] = []
	var rest: Array[String] = []
	affordable.clear()
	rest.clear()
	for gid in pool:
		var cost := int(GENE_COSTS.get(gid, 99))
		var n := int(inv.get(gid, 0))
		if n >= MAX_PER_GENE:
			continue
		if cost <= room:
			affordable.append(gid)
		else:
			rest.append(gid)
	var bag: Array[String] = []
	while bag.size() < count and (not affordable.is_empty() or not rest.is_empty()):
		var src: Array[String] = affordable if not affordable.is_empty() else rest
		var i := rng.randi_range(0, src.size() - 1)
		var pick: String = src[i]
		src.remove_at(i)
		if bag.has(pick):
			continue
		bag.append(pick)
	# Guarantee a core option until inventory has one.
	if int(inv.get("core", 0)) < 1 and not bag.has("core") and GENE_COSTS.has("core"):
		if bag.size() >= count:
			bag[0] = "core"
		else:
			bag.append("core")
	return bag

static func point_cost(inv: Dictionary) -> int:
	var total := 0
	for k in inv.keys():
		var gid := str(k)
		var n := int(inv.get(gid, 0))
		if n <= 0:
			continue
		total += n * int(GENE_COSTS.get(gid, 99))
	return total

static func validate(inv: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if int(inv.get("core", 0)) < 1:
		out["reason"] = "Need at least 1 core"
		return out
	for k in inv.keys():
		var gid := str(k)
		var n := int(inv.get(gid, 0))
		if n < 0:
			out["reason"] = "Negative count for %s" % gid
			return out
		if n <= 0:
			continue
		if n > MAX_PER_GENE:
			out["reason"] = "%s exceeds max (%d)" % [gid, MAX_PER_GENE]
			return out
		if not GENE_COSTS.has(gid):
			out["reason"] = "Unknown gene %s" % gid
			return out
	var spent := point_cost(inv)
	if spent > BUDGET:
		out["reason"] = "Over budget (%d / %d)" % [spent, BUDGET]
		return out
	out["ok"] = true
	return out

static func sanitized_copy(inv: Dictionary) -> Dictionary:
	var out := {}
	for gid in draftable_genes():
		out[gid] = clampi(int(inv.get(gid, 0)), 0, MAX_PER_GENE)
	return out

static func preset(name: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(name, DEFAULT_POOL)
	return sanitized_copy(p)

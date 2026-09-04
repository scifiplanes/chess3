extends RefCounted
class_name UnitDefs

## Organ emoji placeholders (Chess 3 biotech fantasy roster).
const UNIT_EMOJI := {
	"core": "🫀",
	"claw": "🦾",
	"hoof": "🦵",
	"eye": "👁️",
	"gland": "🧪",
	"shell": "🐚",
	"ram": "🐏",
	"node": "⚡",
	"vent": "🌋",
	"spine": "🔭",
	"spring": "🦿",
	"leap": "🐆",
	"synapse": "🔗",
	"plate": "🛡️",
	"chunk": "🧊",
	"beacon": "📡",
	"spore": "💣",
	"pod": "💥",
	"phase": "✨",
	"brood": "👜",
	"anchor": "⚓",
	"rot": "🦠",
	"leech": "🪱",
	"static": "📻",
}

const ACTION_LABEL := {
	"melee": "Melee",
	"ranged": "Ranged",
	"move": "Move 1",
	"run": "Run",
	"dash": "Dash",
	"charge": "Charge",
	"jump": "Jump",
	"blink": "Teleport",
	"pounce": "Pounce",
	"slam": "Slam",
	"railgun": "Railgun",
	"powerstrike": "Power",
	"eruption": "Erupt",
	"airstrike": "Map strike",
	"switch": "Switch",
	"mine": "Mine",
	"big_mine": "Big mine",
	"snare": "Snare",
}

static func emoji_for(unit_def_id: String) -> String:
	return str(UNIT_EMOJI.get(unit_def_id, "❔"))

static func action_label(action_id: String) -> String:
	return str(ACTION_LABEL.get(action_id, action_id.capitalize()))

static func organ_display_name(unit_def_id: String) -> String:
	return str(ORGAN_NAMES.get(unit_def_id, unit_def_id.capitalize()))

const ORGAN_NAMES := {
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
	"rot": "Rot Sac",
	"leech": "Leech Coil",
	"static": "Static Lobe",
}

static func all_gene_ids() -> Array[String]:
	var out: Array[String] = []
	for k in DEFS.keys():
		out.append(str(k))
	out.sort()
	return out

static func ability_summary(unit_def_id: String, is_mutant: bool = false) -> String:
	var ids := list_action_ids(unit_def_id)
	if is_mutant:
		var extra := mutant_extra_action(unit_def_id)
		if extra != "" and not ids.has(extra):
			ids.append(extra)
	if ids.is_empty():
		if unit_def_id == "plate":
			return "4 HP graft"
		if unit_def_id == "chunk":
			return "Extra HP"
		if unit_def_id == "brood":
			return "Spawn +1 ring"
		if unit_def_id == "anchor":
			return "Spawn cross +2"
		if unit_def_id == "rot":
			return "Curse: +1 dmg taken"
		if unit_def_id == "leech":
			return "Curse: −1 move"
		if unit_def_id == "static":
			return "Curse: +1 ability CD"
		return "Passive"
	var labels: Array[String] = []
	for aid in ids:
		labels.append(action_label(str(aid)))
	return ", ".join(labels)

## Mutant organs: 2 HP, larger on board, one bonus action borrowed from the roster.
const MUTANT_HP := 2
const MUTANT_SCALE := 2.2
const MUTANT_OFFER_CHANCE := 0.22

const MUTANT_EXTRA := {
	"core": "slam",
	"claw": "run",
	"hoof": "run",
	"eye": "snare",
	"gland": "ranged",
	"shell": "melee",
	"ram": "slam",
	"node": "ranged",
	"vent": "slam",
	"spine": "railgun",
	"spring": "jump",
	"leap": "dash",
	"synapse": "blink",
	"plate": "melee",
	"chunk": "melee",
	"beacon": "eruption",
	"spore": "snare",
	"pod": "mine",
	"phase": "blink",
	"brood": "run",
	"anchor": "logistics_passive",
}

static func mutant_extra_action(unit_def_id: String) -> String:
	var extra := str(MUTANT_EXTRA.get(unit_def_id, ""))
	if extra == "logistics_passive":
		return ""
	return extra

static func can_roll_mutant(unit_def_id: String) -> bool:
	return mutant_extra_action(unit_def_id) != "" or str(unit_def_id) in ["brood", "anchor", "chunk", "plate"]

static func max_hp_for(unit_def_id: String, is_mutant: bool) -> int:
	if is_mutant:
		return MUTANT_HP
	var d: Dictionary = DEFS.get(unit_def_id, {})
	return maxi(1, int(d.get("max_hp", 1)))

static func organ_scale_for(unit_def_id: String, is_mutant: bool) -> float:
	if is_mutant:
		return MUTANT_SCALE
	if size_category(unit_def_id) == "large":
		return 1.15
	if str(unit_def_id) == "chunk":
		return 0.92
	return 1.0

static func list_action_ids_for_unit(unit) -> Array[String]:
	if unit == null:
		return []
	var out := list_action_ids(str(unit.unit_def_id))
	if bool(unit.is_mutant):
		var extra := mutant_extra_action(str(unit.unit_def_id))
		if extra != "" and not out.has(extra):
			out.append(extra)
	return out

static func action_def_for_unit(unit, action_id: String) -> Dictionary:
	if unit == null:
		return {}
	var ad := action_def(str(unit.unit_def_id), action_id)
	if not ad.is_empty():
		return ad
	if bool(unit.is_mutant):
		var extra := mutant_extra_action(str(unit.unit_def_id))
		if str(action_id) == extra:
			for def_key in DEFS.keys():
				var borrowed := action_def(str(def_key), extra)
				if not borrowed.is_empty():
					return borrowed
	return {}

## Organ defs: max_hp defaults 1. Optional body_slot + tags (logistics/fob).
const DEFS := {
	"core": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 1, "cooldown": 1, "type": "melee", "tags": []},
		},
	},
	"claw": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "arm",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"dash": {"id": "dash", "kind": "dash", "steps": 3, "path_damage": 1, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"hoof": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "leg",
		"actions": {
			"run": {"id": "run", "kind": "run", "steps": 3, "cooldown": 1, "type": "move", "tags": []},
		},
	},
	"eye": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "head",
		"actions": {
			"ranged": {"id": "ranged", "kind": "ranged", "range": 6, "damage": 2, "cooldown": 1, "type": "ranged", "tags": []},
		},
	},
	"gland": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {
			"snare": {"id": "snare", "kind": "plant_snare", "range": 1, "cooldown": 4, "type": "utility", "tags": []},
		},
	},
	"shell": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {
			"slam": {"id": "slam", "kind": "slam", "aoe_radius": 1, "damage": 1, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"ram": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"actions": {
			"charge": {"id": "charge", "kind": "charge", "steps": 2, "damage": 2, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"node": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "head",
		"actions": {
			"powerstrike": {"id": "powerstrike", "kind": "delayed_single", "range": 4, "damage": 2, "cooldown": 4, "type": "ranged", "tags": []},
		},
	},
	"vent": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"actions": {
			"eruption": {"id": "eruption", "kind": "delayed_radius", "range": 3, "aoe_radius": 1, "damage": 2, "cooldown": 4, "type": "ranged", "tags": []},
		},
	},
	"spine": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"actions": {
			"railgun": {"id": "railgun", "kind": "railgun", "range": 4, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"spring": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "leg",
		"actions": {
			"jump": {"id": "jump", "kind": "jump", "steps": 3, "cooldown": 2, "type": "move", "tags": []},
		},
	},
	"leap": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "leg",
		"actions": {
			"pounce": {"id": "pounce", "kind": "pounce", "jump_range": 3, "aoe_radius": 1, "damage": 2, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"synapse": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "head",
		"actions": {
			"switch": {"id": "switch", "kind": "switch", "range": 3, "cooldown": 4, "type": "utility", "tags": []},
		},
	},
	"plate": {
		"max_hp": 4,
		"size": "small",
		"body_slot": "any",
		"actions": {},
	},
	"chunk": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {},
	},
	"beacon": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "head",
		"actions": {
			"airstrike": {"id": "airstrike", "kind": "delayed_area", "range": 5, "damage": 2, "cooldown": 5, "type": "ranged", "tags": []},
		},
	},
	"spore": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {
			"mine": {"id": "mine", "kind": "plant_mine", "range": 1, "damage": 2, "cooldown": 3, "type": "utility", "tags": []},
		},
	},
	"pod": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {
			"big_mine": {"id": "big_mine", "kind": "plant_big_mine", "range": 1, "damage": 3, "splash": 1, "cooldown": 4, "type": "utility", "tags": []},
		},
	},
	"phase": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"actions": {
			"blink": {"id": "blink", "kind": "blink", "range": 4, "cooldown": 3, "type": "move", "tags": []},
		},
	},
	"brood": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"tags": ["logistics"],
		"actions": {},
	},
	"anchor": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "torso",
		"tags": ["fob"],
		"actions": {},
	},
	"rot": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "any",
		"tags": ["curse", "curse_fragile"],
		"actions": {},
	},
	"leech": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "leg",
		"tags": ["curse", "curse_slow"],
		"actions": {},
	},
	"static": {
		"max_hp": 1,
		"size": "small",
		"body_slot": "head",
		"tags": ["curse", "curse_static"],
		"actions": {},
	},
}

static func size_category(unit_def_id: String) -> String:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	if d.is_empty():
		return "small"
	return str(d.get("size", "small"))

static func body_slot(unit_def_id: String) -> String:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var s := str(d.get("body_slot", "any"))
	if s == "head" or s == "torso" or s == "arm" or s == "leg" or s == "any":
		return s
	return "any"

static func unit_tags(unit_def_id: String) -> Array:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var t = d.get("tags", [])
	return t if t is Array else []

static func is_curse_organ(unit_def_id: String) -> bool:
	for t in unit_tags(unit_def_id):
		if str(t) == "curse":
			return true
	return false

static func curse_tag_count(squad, tag: String) -> int:
	var n := 0
	if squad == null:
		return 0
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		for t in unit_tags(str(u.unit_def_id)):
			if str(t) == tag:
				n += 1
				break
	return n

static func extra_damage_taken(squad) -> int:
	return curse_tag_count(squad, "curse_fragile") * 2

static func move_range_penalty(squad) -> int:
	return curse_tag_count(squad, "curse_slow")

static func ability_cooldown_penalty(squad) -> int:
	return curse_tag_count(squad, "curse_static")

static func gear_spawn_pool() -> Array[String]:
	var out: Array[String] = []
	for id in ["claw", "eye", "hoof", "shell", "ram", "spine", "spring", "leap", "gland", "spore", "pod", "node", "vent", "beacon", "phase", "synapse", "plate", "chunk"]:
		out.append(id)
	return out

## Popped organs that may land as reclaimable field gear (weapons / grafts).
## Structural (core/brood/anchor) and curses stay gone — not re-pickable like gear.
static func is_reclaimable_gear(unit_def_id: String) -> bool:
	var id := str(unit_def_id)
	if id == "" or is_curse_organ(id):
		return false
	if id in ["core", "brood", "anchor"]:
		return false
	for gid in gear_spawn_pool():
		if str(gid) == id:
			return true
	return false

static func egg_spawn_pool() -> Array[String]:
	var out: Array[String] = []
	for id in ["chunk", "plate", "claw", "eye", "rot", "leech", "static", "hoof", "shell"]:
		out.append(id)
	return out

static func armor_factor(unit_def_id: String) -> int:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	return maxi(1, int(d.get("armor_factor", 1)))

static func action_kind(ad: Dictionary) -> String:
	var k := str(ad.get("kind", ""))
	if k != "":
		return k
	return str(ad.get("type", ""))

static func action_def(unit_def_id: String, action_id: String) -> Dictionary:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var actions: Dictionary = d.get("actions", {})
	var a: Dictionary = actions.get(action_id, {})
	return a

static func has_action(unit_def_id: String, action_id: String) -> bool:
	return not action_def(unit_def_id, action_id).is_empty()

## Union of action ids across all alive organs on a mutant (squad).
static func list_action_ids_for_squad(squad) -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	if squad == null:
		return out
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		for aid in list_action_ids_for_unit(u):
			if seen.has(aid):
				continue
			seen[aid] = true
			out.append(aid)
	out.sort()
	return out

## Best merged action def across alive organs (union): prefer higher damage/range/steps,
## lower cooldown. Front order no longer changes shared ability power.
static func action_def_for_squad(squad, action_id: String) -> Dictionary:
	if squad == null:
		return {}
	var best: Dictionary = {}
	var best_score := -999999
	for u_any in squad.units:
		var u = u_any
		if u == null or int(u.hp) <= 0:
			continue
		var ad: Dictionary = action_def_for_unit(u, action_id)
		if ad.is_empty():
			continue
		var score := _action_def_score(ad)
		if best.is_empty() or score > best_score:
			best = ad
			best_score = score
	return best

static func _action_def_score(ad: Dictionary) -> int:
	var damage := int(ad.get("damage", 0))
	var path_damage := int(ad.get("path_damage", 0))
	var aoe_splash := int(ad.get("aoe_splash", 0))
	var range_v := int(ad.get("range", 0))
	var steps := int(ad.get("steps", 0))
	var jump_range := int(ad.get("jump_range", 0))
	var aoe_radius := int(ad.get("aoe_radius", 0))
	var cd := int(ad.get("cooldown", 0))
	return damage * 100 + path_damage * 80 + aoe_splash * 40 + range_v * 20 + steps * 15 + jump_range * 15 + aoe_radius * 10 - cd * 5

static func list_action_ids(unit_def_id: String) -> Array[String]:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var actions: Dictionary = d.get("actions", {})
	var order = d.get("action_order", null)
	var out: Array[String] = []
	if order is Array:
		for x in order:
			var aid := str(x)
			if actions.has(aid):
				out.append(aid)
		for k in actions.keys():
			if not out.has(str(k)):
				out.append(str(k))
	else:
		for k in actions.keys():
			out.append(str(k))
		out.sort()
	return out

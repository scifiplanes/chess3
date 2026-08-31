extends RefCounted
class_name UnitDefs

## Placeholder board visuals until real textures exist.
const UNIT_EMOJI := {
	"soldier": "⚔️",
	"archer": "🏹",
	"tank": "🛡️",
	"mage": "🔮",
	"rogue": "🥷",
	"bomber": "💣",
	"ogre": "👹",
	"ninja": "🥷",
	"operator": "🎯",
	"spidertank": "🕷️",
	"swarm": "🐝",
	"walker": "🦿",
	"wolfpack": "🐺",
	"copter": "🚁",
	"technical": "🛻",
	"fog": "🌫️",
	"android": "🤖",
	"guerrilla": "🌲",
	"sniper": "🔭",
	"engineer": "🔧",
	"ifv": "🚌",
	"mrap": "🚙",
	"mlrs": "🚀",
	"strike_drone": "🛸",
	"heavy_copter": "🚟",
	"mortar": "💥",
	"apc": "🚐",
	"buggy": "🏎️",
	"chunk": "📦",
}

const ACTION_LABEL := {
	"melee": "Melee",
	"ranged": "Ranged",
	"move": "Move 1",
	"run": "Run",
	"dash": "Dash",
	"charge": "Charge",
	"jump": "Jump",
	"blink": "Blink",
	"pounce": "Pounce",
	"slam": "Slam",
	"railgun": "Railgun",
	"powerstrike": "Power",
	"eruption": "Erupt",
	"airstrike": "Air",
	"switch": "Switch",
	"mine": "Mine",
	"big_mine": "Boom",
	"snare": "Snare",
}

static func emoji_for(unit_def_id: String) -> String:
	return str(UNIT_EMOJI.get(unit_def_id, "❔"))

static func action_label(action_id: String) -> String:
	return str(ACTION_LABEL.get(action_id, action_id.capitalize()))

## Unit defs: optional armor_factor (damage divisor). Tags: logistics, fob, chunk.
const DEFS := {
	"soldier": {
		"max_hp": 10,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"archer": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"tank": {
		"max_hp": 18,
		"size": "small",
		"armor_factor": 2,
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 4, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 2, "damage": 1, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"mage": {
		"max_hp": 7,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {
				"id": "ranged",
				"kind": "ranged",
				"range": 3,
				"damage": 2,
				"cooldown": 2,
				"type": "ranged",
				"tags": [],
				"aoe_radius": 1,
				"aoe_splash": 1,
			},
		},
	},
	"rogue": {
		"max_hp": 9,
		"size": "small",
		"actions": {
			"melee": {
				"id": "melee",
				"kind": "melee",
				"range": 2,
				"damage": 3,
				"cooldown": 2,
				"type": "melee",
				"tags": [],
				"self_move": "dash_adjacent",
			},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 2, "damage": 1, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"bomber": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {
				"id": "ranged",
				"kind": "ranged",
				"range": 3,
				"damage": 1,
				"cooldown": 2,
				"type": "ranged",
				"tags": [],
				"obstacle_bonus": 3,
			},
		},
	},
	"ogre": {
		"max_hp": 14,
		"size": "large",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 5, "cooldown": 1, "type": "melee", "tags": []},
		},
	},
	"ninja": {
		"max_hp": 9,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"run": {"id": "run", "kind": "run", "steps": 2, "cooldown": 2, "type": "move", "tags": []},
			"blink": {"id": "blink", "kind": "blink", "range": 4, "cooldown": 3, "type": "move", "tags": []},
		},
	},
	"operator": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 4, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"mine": {"id": "mine", "kind": "plant_mine", "range": 2, "damage": 4, "cooldown": 3, "type": "utility", "tags": []},
			"snare": {"id": "snare", "kind": "plant_snare", "range": 2, "cooldown": 3, "type": "utility", "tags": []},
		},
	},
	"spidertank": {
		"max_hp": 16,
		"size": "large",
		"armor_factor": 2,
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 4, "cooldown": 1, "type": "melee", "tags": []},
			"railgun": {"id": "railgun", "kind": "railgun", "range": 4, "damage": 3, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"swarm": {
		"max_hp": 7,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"slam": {"id": "slam", "kind": "slam", "range": 1, "damage": 2, "aoe_radius": 1, "cooldown": 3, "type": "melee", "tags": []},
			"run": {"id": "run", "kind": "run", "steps": 2, "cooldown": 2, "type": "move", "tags": []},
		},
	},
	"walker": {
		"max_hp": 14,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"charge": {"id": "charge", "kind": "charge", "range": 6, "steps": 2, "damage": 3, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"wolfpack": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 4, "cooldown": 1, "type": "melee", "tags": []},
			"pounce": {"id": "pounce", "kind": "pounce", "jump_range": 3, "damage": 3, "aoe_radius": 1, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"copter": {
		"max_hp": 9,
		"size": "small",
		"actions": {
			"ranged": {"id": "ranged", "kind": "ranged", "range": 4, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"jump": {"id": "jump", "kind": "jump", "steps": 3, "cooldown": 2, "type": "move", "tags": []},
			"airstrike": {"id": "airstrike", "kind": "delayed_area", "range": 5, "damage": 3, "cooldown": 4, "type": "ranged", "tags": [], "pattern": "plus5"},
		},
	},
	"technical": {
		"max_hp": 10,
		"size": "small",
		"tags": ["logistics"],
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"mine": {"id": "mine", "kind": "plant_mine", "range": 2, "damage": 3, "cooldown": 3, "type": "utility", "tags": []},
		},
	},
	"fog": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"eruption": {"id": "eruption", "kind": "delayed_radius", "range": 3, "damage": 4, "aoe_radius": 1, "cooldown": 4, "type": "ranged", "tags": []},
		},
	},
	"android": {
		"max_hp": 12,
		"size": "small",
		"armor_factor": 2,
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
		},
	},
	"guerrilla": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"snare": {"id": "snare", "kind": "plant_snare", "range": 2, "cooldown": 3, "type": "utility", "tags": []},
		},
	},
	"sniper": {
		"max_hp": 6,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"railgun": {"id": "railgun", "kind": "railgun", "range": 4, "damage": 4, "cooldown": 3, "type": "ranged", "tags": []},
			"powerstrike": {"id": "powerstrike", "kind": "delayed_single", "range": 3, "damage": 6, "cooldown": 5, "type": "ranged", "tags": []},
		},
	},
	"engineer": {
		"max_hp": 9,
		"size": "small",
		"tags": ["logistics"],
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"mine": {"id": "mine", "kind": "plant_mine", "range": 2, "damage": 4, "cooldown": 3, "type": "utility", "tags": []},
			"big_mine": {"id": "big_mine", "kind": "plant_big_mine", "range": 2, "damage": 4, "splash": 2, "cooldown": 4, "type": "utility", "tags": []},
		},
	},
	"ifv": {
		"max_hp": 14,
		"size": "large",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"ranged": {"id": "ranged", "kind": "ranged", "range": 3, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"charge": {"id": "charge", "kind": "charge", "range": 6, "steps": 2, "damage": 3, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"mrap": {
		"max_hp": 16,
		"size": "large",
		"armor_factor": 2,
		"tags": ["fob"],
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"run": {"id": "run", "kind": "run", "steps": 2, "cooldown": 2, "type": "move", "tags": []},
		},
	},
	"mlrs": {
		"max_hp": 12,
		"size": "large",
		"actions": {
			"ranged": {"id": "ranged", "kind": "ranged", "range": 4, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"slam": {"id": "slam", "kind": "slam", "range": 2, "damage": 2, "aoe_radius": 1, "cooldown": 3, "type": "melee", "tags": []},
			"airstrike": {"id": "airstrike", "kind": "delayed_area", "range": 5, "damage": 4, "cooldown": 5, "type": "ranged", "tags": [], "pattern": "plus5"},
		},
	},
	"strike_drone": {
		"max_hp": 7,
		"size": "small",
		"actions": {
			"ranged": {"id": "ranged", "kind": "ranged", "range": 4, "damage": 2, "cooldown": 2, "type": "ranged", "tags": []},
			"dash": {"id": "dash", "kind": "dash", "steps": 3, "path_damage": 2, "damage": 2, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"heavy_copter": {
		"max_hp": 14,
		"size": "large",
		"actions": {
			"ranged": {"id": "ranged", "kind": "ranged", "range": 4, "damage": 3, "cooldown": 2, "type": "ranged", "tags": []},
			"pounce": {"id": "pounce", "kind": "pounce", "jump_range": 3, "damage": 4, "aoe_radius": 1, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"mortar": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"eruption": {"id": "eruption", "kind": "delayed_radius", "range": 5, "damage": 5, "aoe_radius": 1, "cooldown": 4, "type": "ranged", "tags": []},
		},
	},
	"apc": {
		"max_hp": 13,
		"size": "large",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 3, "cooldown": 1, "type": "melee", "tags": []},
			"run": {"id": "run", "kind": "run", "steps": 2, "cooldown": 2, "type": "move", "tags": []},
			"switch": {"id": "switch", "kind": "switch", "range": 3, "cooldown": 4, "type": "utility", "tags": []},
		},
	},
	"buggy": {
		"max_hp": 8,
		"size": "small",
		"actions": {
			"melee": {"id": "melee", "kind": "melee", "range": 1, "damage": 2, "cooldown": 1, "type": "melee", "tags": []},
			"run": {"id": "run", "kind": "run", "steps": 2, "cooldown": 1, "type": "move", "tags": []},
			"charge": {"id": "charge", "kind": "charge", "range": 6, "steps": 2, "damage": 2, "cooldown": 3, "type": "melee", "tags": []},
		},
	},
	"chunk": {
		"max_hp": 28,
		"size": "large",
		"tags": ["chunk"],
		"actions": {},
	},
}

static func size_category(unit_def_id: String) -> String:
	var d = DEFS.get(unit_def_id, null)
	if d == null:
		return "small"
	return str(d.get("size", "small"))

static func unit_tags(unit_def_id: String) -> Array:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var t = d.get("tags", [])
	return t if t is Array else []

static func armor_factor(unit_def_id: String) -> int:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	return maxi(1, int(d.get("armor_factor", 1)))

static func action_kind(action_def: Dictionary) -> String:
	var k := str(action_def.get("kind", ""))
	if k != "":
		return k
	return str(action_def.get("type", ""))

static func action_def(unit_def_id: String, action_id: String) -> Dictionary:
	var d: Dictionary = DEFS.get(unit_def_id, {})
	var actions: Dictionary = d.get("actions", {})
	var a: Dictionary = actions.get(action_id, {})
	return a

static func has_action(unit_def_id: String, action_id: String) -> bool:
	return not action_def(unit_def_id, action_id).is_empty()

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

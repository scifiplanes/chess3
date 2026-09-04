extends RefCounted
class_name DemoCommentary

## Short spectator lines for demo mode commentary log.

const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const DeckRulesScript = preload("res://src/app/DeckRules.gd")

static func player_tag(player: int) -> String:
	return "P%d" % (player + 1)

static func cell_str(cell: Vector2i) -> String:
	return "(%d,%d)" % [cell.x, cell.y]

static func gene_label(def_id: String, is_mutant: bool = false) -> String:
	var prefix := "M·" if is_mutant else ""
	var name := str(DeckRulesScript.GENE_NAMES.get(def_id, def_id.capitalize()))
	return "%s%s %s" % [prefix, UnitDefsScript.emoji_for(def_id), name]

static func action_label(action_id: String) -> String:
	return UnitDefsScript.action_label(action_id)

static func squad_tag(sid: int) -> String:
	return "M-%02d" % sid

static func spawn_line(player: int, def_id: String, is_mutant: bool) -> String:
	return "%s deploys %s" % [player_tag(player), gene_label(def_id, is_mutant)]

static func attach_line(player: int, def_id: String, is_mutant: bool, sid: int) -> String:
	return "%s stacks %s on %s" % [player_tag(player), gene_label(def_id, is_mutant), squad_tag(sid)]

static func graft_line(player: int, sid: int) -> String:
	return "%s %s field-grafts an organ" % [player_tag(player), squad_tag(sid)]

static func lock_line(player: int) -> String:
	return "%s mutant left spawn pool — organs locked" % player_tag(player)

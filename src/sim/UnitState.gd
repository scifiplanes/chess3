extends RefCounted
class_name UnitState

var unit_def_id: String
var hp: int
var ready_turn: int = 1 # Unit may act when gs.turn_number >= ready_turn
var is_mutant: bool = false ## Oversized organ: +HP and bonus ability.

func _init(p_unit_def_id: String, p_hp: int, p_ready_turn: int = 1, p_is_mutant: bool = false) -> void:
	unit_def_id = p_unit_def_id
	hp = p_hp
	ready_turn = p_ready_turn
	is_mutant = p_is_mutant


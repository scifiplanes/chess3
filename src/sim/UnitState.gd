extends RefCounted
class_name UnitState

var unit_def_id: String
var hp: int
var ready_turn: int = 1 # Unit may act when gs.turn_number >= ready_turn

func _init(p_unit_def_id: String, p_hp: int, p_ready_turn: int = 1) -> void:
	unit_def_id = p_unit_def_id
	hp = p_hp
	ready_turn = p_ready_turn


extends RefCounted
class_name ControlPointState

var cell: Vector2i
var owner: int = -1 # -1 = neutral, 0 = P1, 1 = P2
var flags := {0: 0, 1: 0} # player -> flags

func _init(p_cell: Vector2i) -> void:
	cell = p_cell

func flags_for(player: int) -> int:
	return int(flags.get(player, 0))

func add_flag(player: int) -> void:
	flags[player] = flags_for(player) + 1

func reset_flags() -> void:
	flags[0] = 0
	flags[1] = 0


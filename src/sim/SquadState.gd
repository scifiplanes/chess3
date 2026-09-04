extends RefCounted
class_name SquadState

var id: int
var owner: int # 0 = P1, 1 = P2
var cell: Vector2i

var units := [] # Array of UnitState
var size_category: String = "small" # "small" | "large" (stubbed by unit defs)

# If equal to GameState.turn_number, this squad is "fresh" and cannot act this turn.
var fresh_turn: int = -1

# If equal to GameState.turn_number, this squad already used its basic Move this turn.
var moved_turn: int = -1

# Action cooldowns stored as turns remaining (0 = ready). Keys match UnitDefs action ids.
var cooldowns := {}

# Snare: cannot move while turn_number < this value (global turn counter).
var snared_no_move_until_turn: int = -1

# Chess 3: once the mutant leaves the Spawn Pool, organs can no longer be attached.
var organs_locked: bool = false

func _init(p_id: int, p_owner: int, p_cell: Vector2i) -> void:
	id = p_id
	owner = p_owner
	cell = p_cell

func is_alive() -> bool:
	for u in units:
		var unit = u
		if unit != null and int(unit.hp) > 0:
			return true
	return false

func can_act(turn_number: int) -> bool:
	return is_alive() and fresh_turn != turn_number

func unit_count_alive() -> int:
	var n := 0
	for u in units:
		var unit = u
		if unit != null and int(unit.hp) > 0:
			n += 1
	return n

func total_hp_alive() -> int:
	var sum := 0
	for u in units:
		var unit = u
		if unit != null and int(unit.hp) > 0:
			sum += int(unit.hp)
	return sum

func front_unit_index() -> int:
	# "Front unit" convention: first alive unit in units[].
	for i in range(units.size()):
		var unit = units[i]
		if unit != null and int(unit.hp) > 0:
			return i
	return -1

func front_unit():
	var idx := front_unit_index()
	if idx < 0:
		return null
	return units[idx]

func tick_cooldowns() -> void:
	for k in cooldowns.keys():
		cooldowns[k] = maxi(0, int(cooldowns[k]) - 1)

func cooldown_ready(action_id: String) -> bool:
	return int(cooldowns.get(action_id, 0)) <= 0

func set_cooldown(action_id: String, turns: int) -> void:
	cooldowns[action_id] = maxi(0, int(turns))


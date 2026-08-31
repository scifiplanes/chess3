extends RefCounted
class_name BoardState

var size: Vector2i
var control_points := [] # Array of ControlPointState
var reinforcement_areas := [] # Array of Vector2i (cells)

# Terrain (per-cell).
# Stored as flat int array: idx = y * size.x + x
const TERRAIN_SOIL := 0
const TERRAIN_ROCK := 1
const TERRAIN_SAND := 2
var terrain: PackedInt32Array

# Obstacles (including destructibles).
# Stored as: Vector2i -> { "hp": int, "destructible": bool }
var obstacles := {}

# Hazards: mines, big mines, snares. Vector2i -> { "kind": String, "owner": int, "damage": int, ... }
var hazards := {}

func _init(p_size: Vector2i) -> void:
	size = p_size
	control_points.clear()
	reinforcement_areas.clear()
	terrain = PackedInt32Array()
	terrain.resize(size.x * size.y)
	terrain.fill(TERRAIN_SOIL)
	obstacles.clear()
	hazards.clear()

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y

func _tidx(cell: Vector2i) -> int:
	return cell.y * size.x + cell.x

func terrain_at(cell: Vector2i) -> int:
	if not in_bounds(cell):
		return TERRAIN_SOIL
	var idx := _tidx(cell)
	if idx < 0 or idx >= terrain.size():
		return TERRAIN_SOIL
	return int(terrain[idx])

func set_terrain(cell: Vector2i, terrain_id: int) -> void:
	if not in_bounds(cell):
		return
	terrain[_tidx(cell)] = int(terrain_id)

func fill_terrain(terrain_id: int) -> void:
	if terrain.is_empty():
		return
	terrain.fill(int(terrain_id))

func is_blocked(cell: Vector2i) -> bool:
	var o = obstacles.get(cell, null)
	if o == null:
		return false
	return int(o.get("hp", 0)) > 0

func add_obstacle(cell: Vector2i, hp: int = 9999, destructible: bool = false) -> void:
	if not in_bounds(cell):
		return
	obstacles[cell] = {"hp": hp, "destructible": destructible}

func is_reinforcement_area(cell: Vector2i) -> bool:
	for c in reinforcement_areas:
		if c == cell:
			return true
	return false

func obstacle_hp(cell: Vector2i) -> int:
	var o = obstacles.get(cell, null)
	if o == null:
		return 0
	return int(o.get("hp", 0))

func is_destructible(cell: Vector2i) -> bool:
	var o = obstacles.get(cell, null)
	if o == null:
		return false
	return bool(o.get("destructible", false))

func damage_obstacle(cell: Vector2i, dmg: int) -> void:
	var o = obstacles.get(cell, null)
	if o == null:
		return
	if not bool(o.get("destructible", false)):
		return
	var hp := maxi(0, int(o.get("hp", 0)) - dmg)
	o["hp"] = hp
	obstacles[cell] = o

func hazard_at(cell: Vector2i):
	return hazards.get(cell, null)

func set_hazard(cell: Vector2i, kind: String, owner: int, damage: int = 2, splash: int = 0) -> void:
	if not in_bounds(cell):
		return
	hazards[cell] = {"kind": str(kind), "owner": int(owner), "damage": int(damage), "splash": int(splash)}

func remove_hazard(cell: Vector2i) -> void:
	hazards.erase(cell)


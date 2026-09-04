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

# Large scenic hero props (subset of obstacles). Array of:
# { "cell": Vector2i, "kind": "mushroom"|"blob"|"rock", "variant": int }
var hero_props := []

# Hazards: mines, big mines, snares. Vector2i -> { "kind": String, "owner": int, "damage": int, ... }
var hazards := {}

# Gear pickups: organ weapons scattered or dropped on the board.
# Vector2i -> { "unit_def_id": String, "is_mutant": bool }
var gear := {}

# Egg containers: stepping attaches the contained organ (may be cursed).
# Vector2i -> { "unit_def_id": String, "is_mutant": bool }
var eggs := {}

## Max scattered/dropped gear on the board; excess drops cull farthest piece.
const MAX_BOARD_GEAR := 14

func _init(p_size: Vector2i) -> void:
	size = p_size
	control_points.clear()
	reinforcement_areas.clear()
	terrain = PackedInt32Array()
	terrain.resize(size.x * size.y)
	terrain.fill(TERRAIN_SOIL)
	obstacles.clear()
	hero_props.clear()
	hazards.clear()
	gear.clear()
	eggs.clear()

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

func add_obstacle(cell: Vector2i, hp: int = 9999, destructible: bool = false, prop_kind: String = "") -> void:
	if not in_bounds(cell):
		return
	var entry := {"hp": hp, "destructible": destructible}
	if str(prop_kind) != "":
		entry["prop_kind"] = str(prop_kind)
	obstacles[cell] = entry

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

func obstacle_prop_kind(cell: Vector2i) -> String:
	var o = obstacles.get(cell, null)
	if o == null:
		return ""
	return str(o.get("prop_kind", ""))

func remove_hero_prop_at(cell: Vector2i) -> void:
	for i in range(hero_props.size() - 1, -1, -1):
		var hp_any = hero_props[i]
		if typeof(hp_any) != TYPE_DICTIONARY:
			continue
		var hp: Dictionary = hp_any
		var c = hp.get("cell", null)
		if c is Vector2i and c == cell:
			hero_props.remove_at(i)

func damage_obstacle(cell: Vector2i, dmg: int) -> void:
	var o = obstacles.get(cell, null)
	if o == null:
		return
	if not bool(o.get("destructible", false)):
		return
	var hp := maxi(0, int(o.get("hp", 0)) - dmg)
	o["hp"] = hp
	obstacles[cell] = o
	if hp <= 0:
		remove_hero_prop_at(cell)
		obstacles.erase(cell)

func hazard_at(cell: Vector2i):
	return hazards.get(cell, null)

func set_hazard(cell: Vector2i, kind: String, owner: int, damage: int = 2, splash: int = 0) -> void:
	if not in_bounds(cell):
		return
	hazards[cell] = {"kind": str(kind), "owner": int(owner), "damage": int(damage), "splash": int(splash)}

func remove_hazard(cell: Vector2i) -> void:
	hazards.erase(cell)

func gear_at(cell: Vector2i):
	return gear.get(cell, null)

func set_gear(cell: Vector2i, unit_def_id: String, is_mutant: bool = false) -> void:
	if not in_bounds(cell):
		return
	gear[cell] = {"unit_def_id": str(unit_def_id), "is_mutant": bool(is_mutant)}

func remove_gear(cell: Vector2i) -> void:
	gear.erase(cell)

func egg_at(cell: Vector2i):
	return eggs.get(cell, null)

func set_egg(cell: Vector2i, unit_def_id: String, is_mutant: bool = false) -> void:
	if not in_bounds(cell):
		return
	eggs[cell] = {"unit_def_id": str(unit_def_id), "is_mutant": bool(is_mutant)}

func remove_egg(cell: Vector2i) -> void:
	eggs.erase(cell)

func pickup_cell_clear(cell: Vector2i) -> bool:
	# Walkable cell with no squad, obstacle, gear, or egg.
	if not in_bounds(cell):
		return false
	if is_blocked(cell):
		return false
	if gear.has(cell) or eggs.has(cell):
		return false
	return true

## 3×3 capture zone: CP cell + 8 neighbors (Chebyshev distance ≤ 1).
func cp_zone_cells(cp_cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := Vector2i(cp_cell.x + dx, cp_cell.y + dy)
			if in_bounds(c):
				out.append(c)
	return out

func is_in_cp_zone(cell: Vector2i, cp_cell: Vector2i) -> bool:
	if not in_bounds(cell) or not in_bounds(cp_cell):
		return false
	return absi(cell.x - cp_cell.x) <= 1 and absi(cell.y - cp_cell.y) <= 1


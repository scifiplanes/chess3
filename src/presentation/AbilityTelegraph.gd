extends RefCounted
class_name AbilityTelegraph

## Board-first reach / impact cell sets for ability targeting + resolve flash.

const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

## Soft violet wash for in-range (not impact).
const COLOR_REACH := Color(0.55, 0.35, 0.75, 1.0)
## Amber-orange impact / AoE / line preview.
const COLOR_IMPACT := Color(1.0, 0.55, 0.15, 1.0)
## Legal enemy / lethal.
const COLOR_ENEMY := Color(1.0, 0.25, 0.25, 1.0)
## Delayed pending.
const COLOR_DELAYED := Color(1.0, 0.55, 0.12, 1.0)
## Trap plant reach.
const COLOR_TRAP := Color(0.45, 0.72, 0.28, 1.0)
## Move / landing (matches Main cyan).
const COLOR_MOVE := Color(0.0, 0.78, 0.95, 1.0)

static func preview(gs, action_id: String, caster_cell: Vector2i, target_cell: Vector2i, action_def: Dictionary = {}) -> Dictionary:
	## Returns {reach_cells, impact_cells, shape, is_line, is_trap}.
	var ad: Dictionary = action_def
	if ad.is_empty() and gs != null:
		var occ = gs.squad_at(caster_cell)
		if occ != null:
			ad = UnitDefsScript.action_def_for_squad(occ, action_id)
	var aid := str(action_id)
	var reach: Array[Vector2i] = []
	var impact: Array[Vector2i] = []
	var shape := "point"
	var is_line := false
	var is_trap := false

	match aid:
		"melee", "ranged":
			shape = "point"
			reach = _manhattan_disk(gs, caster_cell, int(ad.get("range", 1)))
			if _in_bounds(gs, target_cell):
				impact = [target_cell]
		"railgun":
			shape = "line"
			is_line = true
			reach = _ortho_ray_reach(gs, caster_cell, int(ad.get("range", 4)))
			if _in_bounds(gs, target_cell) and (target_cell.x == caster_cell.x or target_cell.y == caster_cell.y):
				impact = _ortho_line_to(gs, caster_cell, target_cell, int(ad.get("range", 4)))
		"charge":
			shape = "line"
			is_line = true
			# Soft reach = nearby; impact = approach path when targeting enemy.
			reach = _manhattan_disk(gs, caster_cell, int(ad.get("steps", 2)) + 1)
			if _in_bounds(gs, target_cell):
				impact = _line_cells_inclusive(caster_cell, target_cell)
		"slam":
			shape = "circle"
			var rad := int(ad.get("aoe_radius", 1))
			impact = _manhattan_disk(gs, caster_cell, rad)
			reach = impact.duplicate()
		"pounce":
			shape = "circle"
			var rad := int(ad.get("aoe_radius", 1))
			if _in_bounds(gs, target_cell):
				impact = _manhattan_disk(gs, target_cell, rad)
				if not impact.has(target_cell):
					impact.append(target_cell)
		"eruption":
			shape = "circle"
			var rad := int(ad.get("aoe_radius", 1))
			reach = _manhattan_disk(gs, caster_cell, int(ad.get("range", 3)))
			if _in_bounds(gs, target_cell):
				impact = _manhattan_disk(gs, target_cell, rad)
		"airstrike":
			shape = "cross"
			reach = _manhattan_disk(gs, caster_cell, int(ad.get("range", 5)))
			if _in_bounds(gs, target_cell):
				impact = _cross_cells(gs, target_cell)
		"powerstrike":
			shape = "point"
			reach = _manhattan_disk(gs, caster_cell, int(ad.get("range", 4)))
			if _in_bounds(gs, target_cell):
				impact = [target_cell]
		"dash":
			shape = "line"
			is_line = true
			if _in_bounds(gs, target_cell):
				impact = _line_cells_inclusive(caster_cell, target_cell)
		"mine", "big_mine", "snare":
			shape = "trap"
			is_trap = true
			reach = _chebyshev_disk(gs, caster_cell, int(ad.get("range", 1)))
			if _in_bounds(gs, target_cell):
				impact = [target_cell]
				if aid == "big_mine":
					# Splash on adjacent ortho cells.
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var n: Vector2i = target_cell + d
						if _in_bounds(gs, n) and not impact.has(n):
							impact.append(n)
		_:
			if _in_bounds(gs, target_cell):
				impact = [target_cell]

	return {
		"reach_cells": reach,
		"impact_cells": impact,
		"shape": shape,
		"is_line": is_line,
		"is_trap": is_trap,
	}

static func impact_for_pending(gs, pe: Dictionary) -> Array[Vector2i]:
	var payload: Dictionary = pe.get("payload", {})
	var cx := int(payload.get("cx", -1))
	var cy := int(payload.get("cy", -1))
	if cx < 0 or cy < 0:
		return []
	var cell := Vector2i(cx, cy)
	var kind := str(pe.get("kind", ""))
	match kind:
		"eruption":
			return _manhattan_disk(gs, cell, int(payload.get("aoe_radius", 1)))
		"airstrike":
			return _cross_cells(gs, cell)
		"powerstrike":
			return [cell] if _in_bounds(gs, cell) else []
		_:
			return [cell] if _in_bounds(gs, cell) else []

static func _in_bounds(gs, cell: Vector2i) -> bool:
	if gs == null or gs.board == null:
		return false
	return gs.board.in_bounds(cell)

static func _manhattan_disk(gs, origin: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := maxi(0, radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if absi(dx) + absi(dy) > r:
				continue
			var c := Vector2i(origin.x + dx, origin.y + dy)
			if _in_bounds(gs, c):
				out.append(c)
	return out

static func _chebyshev_disk(gs, origin: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := maxi(0, radius)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) > r:
				continue
			var c := Vector2i(origin.x + dx, origin.y + dy)
			if _in_bounds(gs, c):
				out.append(c)
	return out

static func _cross_cells(gs, origin: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in [origin, origin + Vector2i(1, 0), origin + Vector2i(-1, 0), origin + Vector2i(0, 1), origin + Vector2i(0, -1)]:
		if _in_bounds(gs, c) and not out.has(c):
			out.append(c)
	return out

static func _ortho_ray_reach(gs, origin: Vector2i, range_max: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cur := origin
		for _i in range(range_max):
			cur = Vector2i(cur.x + dir.x, cur.y + dir.y)
			if not _in_bounds(gs, cur):
				break
			out.append(cur)
	return out

static func _ortho_line_to(gs, from: Vector2i, to: Vector2i, range_max: int) -> Array[Vector2i]:
	if from.x != to.x and from.y != to.y:
		return []
	var dx := signi(to.x - from.x)
	var dy := signi(to.y - from.y)
	var out: Array[Vector2i] = []
	var cur := from
	var steps := 0
	while steps < range_max:
		cur = Vector2i(cur.x + dx, cur.y + dy)
		steps += 1
		if not _in_bounds(gs, cur):
			break
		out.append(cur)
		if cur == to:
			break
	return out

static func _line_cells_inclusive(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	## Simple Manhattan corridor (prefer axis-aligned then L if needed).
	var out: Array[Vector2i] = []
	var cur := from
	out.append(cur)
	while cur.x != to.x:
		cur = Vector2i(cur.x + signi(to.x - cur.x), cur.y)
		out.append(cur)
	while cur.y != to.y:
		cur = Vector2i(cur.x, cur.y + signi(to.y - cur.y))
		out.append(cur)
	return out

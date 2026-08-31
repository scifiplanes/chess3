extends RefCounted
class_name Pathfinding

func reachable_cells(gs, sid: int, max_steps: int, ignore_blocked_terrain: bool = false, ignore_squad_blockers: bool = false) -> Dictionary:
	var s = gs.get_squad(sid)
	if s == null or not s.is_alive():
		return {}

	var start = s.cell
	var visited := {} # Vector2i -> steps
	var q: Array = []
	q.append({"c": start, "d": 0})
	visited[start] = 0

	while q.size() > 0:
		var item = q.pop_front()
		var c: Vector2i = item["c"]
		var d: int = item["d"]
		if d >= max_steps:
			continue

		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = c + dir
			if not gs.board.in_bounds(n):
				continue
			if not ignore_blocked_terrain and gs.board.is_blocked(n):
				continue
			# Allow starting cell; disallow stepping onto other squads unless matching loose net stub pathing.
			if not ignore_squad_blockers:
				var occ = gs.squad_at(n)
				if occ != null and occ.id != sid:
					continue
			var nd: int = d + 1
			if not visited.has(n) or nd < int(visited[n]):
				visited[n] = nd
				q.append({"c": n, "d": nd})

	return visited

## Pass through enemy squads; cannot end on blocked terrain. Destination must be empty for caller to filter.
func reachable_pass_through_squads(gs, sid: int, max_steps: int) -> Dictionary:
	return reachable_cells(gs, sid, max_steps, false, true)

func chebyshev_disk(center: Vector2i, radius: int, gs) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null or gs.board == null:
		return out
	var sz: Vector2i = gs.board.size
	for y in range(0, int(sz.y)):
		for x in range(0, int(sz.x)):
			var c := Vector2i(x, y)
			var dx: int = abs(c.x - center.x)
			var dy: int = abs(c.y - center.y)
			if maxi(dx, dy) <= radius:
				out.append(c)
	return out

func straight_ray_cells(origin: Vector2i, dir: Vector2i, length: int, gs) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if gs == null or gs.board == null:
		return out
	var c := origin
	for _i in range(length):
		c = c + dir
		if not gs.board.in_bounds(c):
			break
		out.append(c)
	return out

func manhattan_intermediate_allowed(from: Vector2i, to: Vector2i, gs) -> bool:
	# For jump/dash: straight orthogonal segments only; intermediate cells may be occupied/blocked except obstacles block?
	if gs == null or gs.board == null:
		return false
	if from.x != to.x and from.y != to.y:
		return false
	var dx := signi(to.x - from.x)
	var dy := signi(to.y - from.y)
	var c := from
	while c != to:
		c = Vector2i(c.x + dx, c.y + dy)
		if not gs.board.in_bounds(c):
			return false
		if gs.board.is_blocked(c):
			return false
	return true

func jump_landing_legal(gs, sid: int, to_cell: Vector2i, max_steps: int) -> bool:
	var s = gs.get_squad(sid)
	if s == null:
		return false
	var dist: int = abs(to_cell.x - s.cell.x) + abs(to_cell.y - s.cell.y)
	if dist < 1 or dist > max_steps:
		return false
	if not manhattan_intermediate_allowed(s.cell, to_cell, gs):
		return false
	if not gs.board.in_bounds(to_cell) or gs.board.is_blocked(to_cell):
		return false
	if gs.squad_at(to_cell) != null:
		return false
	return true

## Shortest orthogonal path; may pass through **enemy** squads; destination must be empty. Returns cells along path **excluding** start, **including** dest.
func path_pass_through_to(gs, sid: int, dest: Vector2i, max_steps: int) -> Array:
	var s = gs.get_squad(sid)
	var out: Array = []
	if s == null or gs.board == null:
		return out
	var start: Vector2i = s.cell
	if start == dest:
		return out
	if not gs.board.in_bounds(dest) or gs.board.is_blocked(dest):
		return out
	if gs.squad_at(dest) != null:
		return out
	var visited := {} # Vector2i -> Vector2i parent
	var q: Array = []
	q.append({"c": start, "d": 0})
	visited[start] = start
	var found := false
	while q.size() > 0:
		var item = q.pop_front()
		var c: Vector2i = item["c"]
		var dist: int = item["d"]
		if dist >= max_steps:
			continue
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n = c + dir
			if not gs.board.in_bounds(n):
				continue
			if gs.board.is_blocked(n):
				continue
			var occ = gs.squad_at(n)
			var is_dest: bool = (n == dest)
			if is_dest:
				if occ != null:
					continue
			else:
				if occ != null:
					if occ.id == sid:
						continue
					if int(occ.owner) == int(s.owner):
						continue
			if visited.has(n):
				continue
			visited[n] = c
			if is_dest:
				found = true
				q.clear()
				break
			q.append({"c": n, "d": dist + 1})
	if not found:
		return out
	var cur: Vector2i = dest
	while cur != start:
		out.push_front(cur)
		var p = visited.get(cur, null)
		if p == null:
			return []
		cur = p
	if out.size() > max_steps:
		return []
	return out


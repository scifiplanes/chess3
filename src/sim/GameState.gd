extends Node
class_name GameState

const BoardStateScript = preload("res://src/sim/BoardState.gd")
const BoardGeneratorScript = preload("res://src/sim/BoardGenerator.gd")
const SquadStateScript = preload("res://src/sim/SquadState.gd")
const UnitStateScript = preload("res://src/sim/UnitState.gd")
const ControlPointStateScript = preload("res://src/sim/ControlPointState.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")
const RulesScript = preload("res://src/sim/Rules.gd")
const ORGAN_HP_MAX := 4

## Default match grid: ~1.5× former 9×9 linear span (round(9 * 1.5) == 14).
const DEFAULT_BOARD_SIZE := Vector2i(14, 14)

signal changed

var board
var squads := {} # int -> SquadState
var rules := RulesScript.new()

var active_player: int = 0
var turn_number: int = 1
var winner: int = -1 # -1 = none, 0 = P1, 1 = P2

var selected_squad_id: int = -1

var _next_squad_id: int = 1
var seed: int = 0

# Minimal per-player inventory for the match (unit_def_id -> count remaining).
var player_inventory := {
	0: {},
	1: {},
}

# Current gene offer for the active player.
var offer_pending: bool = true
var offer_cards: Array[String] = []
var offer_mutants: Array[bool] = []
var offer_picks_remaining: int = 1

# Scheduled abilities (delayed strikes). Resolved in Resolver after turn_number increments.
var pending_effects: Array = []
var _next_pending_id: int = 1

func next_pending_id() -> int:
	var id := _next_pending_id
	_next_pending_id += 1
	return id

func setup(p_board_size: Vector2i, p_seed: int = 0, p_inventories: Dictionary = {}) -> void:
	board = BoardStateScript.new(p_board_size)
	squads.clear()
	pending_effects.clear()
	_next_pending_id = 1
	active_player = 0
	turn_number = 1
	winner = -1
	selected_squad_id = -1
	_next_squad_id = 1
	if int(p_seed) != 0:
		seed = int(p_seed)
	else:
		seed = int(Time.get_unix_time_from_system())
	var gen = BoardGeneratorScript.new()
	gen.call("generate", board, seed)
	if p_inventories.is_empty():
		_seed_default_inventory()
	else:
		player_inventory[0] = p_inventories.get(0, _default_pool()).duplicate(true)
		player_inventory[1] = p_inventories.get(1, _default_pool()).duplicate(true)
	start_offer_phase()
	emit_signal("changed")

## Real matches: odd seeds let P1 take the opening tempo (with both seats still getting 2-of-5).
func apply_seed_first_player() -> void:
	active_player = absi(int(seed)) % 2
	turn_number = 1
	start_offer_phase()
	emit_signal("changed")

func _default_pool() -> Dictionary:
	return {
		"core": 8,
		"chunk": 4,
		"claw": 4,
		"hoof": 4,
		"eye": 4,
		"plate": 3,
		"gland": 3,
		"shell": 3,
		"spore": 2,
		"spring": 2,
		"phase": 2,
		"ram": 2,
		"spine": 2,
		"brood": 2,
		"node": 1,
		"vent": 1,
		"leap": 1,
		"synapse": 1,
		"pod": 1,
		"beacon": 1,
		"anchor": 1,
	}

func add_squad(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int, is_mutant: bool = false) -> int:
	# Back-compat: seed squads created via add_squad are not "fresh" gated.
	return _add_squad_internal(owner, cell, unit_def_id, unit_hp, false, is_mutant)

func spawn_fresh_squad(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int, is_mutant: bool = false) -> int:
	return _add_squad_internal(owner, cell, unit_def_id, unit_hp, true, is_mutant)

func _add_squad_internal(owner: int, cell: Vector2i, unit_def_id: String, unit_hp: int, fresh: bool, is_mutant: bool = false) -> int:
	var size_cat := UnitDefsScript.size_category(unit_def_id)

	var sid := _next_squad_id
	_next_squad_id += 1
	var squad := SquadStateScript.new(sid, owner, cell)
	squad.size_category = size_cat
	var ready_turn := turn_number + 1 if fresh else turn_number
	var hp := maxi(1, mini(ORGAN_HP_MAX, int(unit_hp)))
	squad.units.append(UnitStateScript.new(unit_def_id, hp, ready_turn, is_mutant))
	if fresh:
		squad.fresh_turn = turn_number
	# Logistics/FOB spawns can leave the home band — those mutants are attach-locked immediately.
	if not rules.is_spawn_pool_cell(self, cell, owner):
		squad.organs_locked = true
	squads[sid] = squad
	emit_signal("changed")
	return sid

func reinforce_squad(sid: int, unit_def_id: String, unit_hp: int, is_mutant: bool = false) -> bool:
	var s = get_squad(sid)
	if s == null or not s.is_alive():
		return false
	if bool(s.organs_locked):
		return false
	if not rules.can_add_unit_to_squad(s, str(unit_def_id)):
		return false
	# Fresh-unit gating: organs attached this turn make the mutant fresh.
	s.fresh_turn = turn_number
	var hp := maxi(1, mini(ORGAN_HP_MAX, int(unit_hp)))
	s.units.append(UnitStateScript.new(unit_def_id, hp, turn_number + 1, is_mutant))
	_stabilize_core_at_back(s)
	s.size_category = "small"
	emit_signal("changed")
	return true

func field_attach_organ(sid: int, unit_def_id: String, unit_hp: int, is_mutant: bool = false) -> bool:
	# Gear/egg graft: bypass Spawn Pool lock; still respects hard organ cap.
	var s = get_squad(sid)
	if s == null or not s.is_alive():
		return false
	if not rules.can_field_attach(s):
		return false
	var hp := maxi(1, mini(ORGAN_HP_MAX, int(unit_hp)))
	s.units.append(UnitStateScript.new(unit_def_id, hp, turn_number, is_mutant))
	_stabilize_core_at_back(s)
	s.size_category = "small"
	emit_signal("changed")
	return true

func _stabilize_core_at_back(squad) -> void:
	# Edge: spawn/attach appends in play order, so 🫀 would die first and leave
	# specialty-only survivors (e.g. shell with slam but no melee). Keep all cores
	# at the back so outer organs soak damage and the heart dies last.
	if squad == null or squad.units.size() < 2:
		return
	var cores: Array = []
	var others: Array = []
	for u in squad.units:
		if str(u.unit_def_id) == "core":
			cores.append(u)
		else:
			others.append(u)
	if cores.is_empty() or others.is_empty():
		return
	squad.units.clear()
	for u in others:
		squad.units.append(u)
	for u in cores:
		squad.units.append(u)

func get_squad(sid: int):
	return squads.get(sid, null)

func squad_at(cell: Vector2i):
	for s in squads.values():
		var squad = s
		if squad.cell == cell and squad.is_alive():
			return squad
	return null

func cp_owner_counts() -> Dictionary:
	var counts := {0: 0, 1: 0}
	for cp in board.control_points:
		if cp.owner == 0:
			counts[0] = int(counts[0]) + 1
		elif cp.owner == 1:
			counts[1] = int(counts[1]) + 1
	return counts

func end_turn() -> void:
	for s in squads.values():
		var squad = s
		squad.tick_cooldowns()
	active_player = 1 - active_player
	turn_number += 1
	selected_squad_id = -1
	emit_signal("changed")

func _seed_default_inventory() -> void:
	var pool := _default_pool()
	player_inventory[0] = pool.duplicate(true)
	player_inventory[1] = pool.duplicate(true)

func offer_hand_size() -> int:
	# Both seats get the opening hand on their first turn (cuts first-player skew).
	return 5 if int(turn_number) <= 2 else 3

func offer_pick_quota() -> int:
	return 2 if int(turn_number) <= 2 else 1

func start_offer_phase() -> void:
	offer_pending = true
	offer_picks_remaining = offer_pick_quota()
	offer_cards = _generate_offer_cards(active_player, turn_number)
	offer_mutants = _generate_offer_mutants(offer_cards, active_player, turn_number)

func clear_offer_phase() -> void:
	offer_pending = false
	offer_cards = []
	offer_mutants = []
	offer_picks_remaining = 0

## Called after a gene is successfully played from the offer tray.
func record_offer_pick() -> void:
	offer_picks_remaining = maxi(0, offer_picks_remaining - 1)
	if offer_picks_remaining <= 0:
		clear_offer_phase()
		return
	prune_unplayable_offer_cards()
	if offer_cards.is_empty():
		clear_offer_phase()
		return
	var any_playable := false
	for c in offer_cards:
		if _offer_is_playable_now(active_player, str(c)):
			any_playable = true
			break
	if not any_playable:
		clear_offer_phase()

## Remove one played gene from the current offer by tray index.
func consume_offer_card_at(index: int) -> void:
	if index < 0 or index >= offer_cards.size():
		return
	offer_cards.remove_at(index)
	if index < offer_mutants.size():
		offer_mutants.remove_at(index)

## Remove one played gene from the current offer (first matching id).
func consume_offer_card(unit_def_id: String) -> void:
	var id := str(unit_def_id)
	for i in range(offer_cards.size()):
		if str(offer_cards[i]) == id:
			consume_offer_card_at(i)
			break

## Chess 3: offer shows 3 genes; player picks at most one (or Skip).
## Unplayable cards are pruned so an empty/unplayable tray auto-ends.
func prune_unplayable_offer_cards() -> void:
	if not bool(offer_pending):
		return
	var kept: Array[String] = []
	var kept_mut: Array[bool] = []
	for i in range(offer_cards.size()):
		var id := str(offer_cards[i])
		if _offer_is_playable_now(active_player, id):
			kept.append(id)
			var mut := false
			if i < offer_mutants.size():
				mut = bool(offer_mutants[i])
			kept_mut.append(mut)
	offer_cards = kept
	offer_mutants = kept_mut

func finish_offer_if_done() -> void:
	# Kept for callers/tests: prune + clear when nothing remains playable.
	if not bool(offer_pending):
		return
	prune_unplayable_offer_cards()
	if offer_cards.is_empty():
		clear_offer_phase()
		return
	var any_playable := false
	for c in offer_cards:
		if _offer_is_playable_now(active_player, str(c)):
			any_playable = true
			break
	if not any_playable:
		clear_offer_phase()

func _generate_offer_cards(player: int, turn: int) -> Array[String]:
	# Deterministic offer based on (seed, player, turn).
	# Opening (turns 1–2): 5-card hand; later: 3-card tray.
	var opening := int(turn) <= 2
	var hand_size := 5 if opening else 3
	var pool: Array[String] = []
	var inv: Dictionary = player_inventory.get(player, {})
	for k in inv.keys():
		if int(inv.get(k, 0)) > 0:
			pool.append(str(k))
	if pool.is_empty():
		pool = ["core", "claw", "eye"]

	var pool_all: Array[String] = pool.duplicate()
	pool_all.sort()
	# Remove inventory ids that cannot be played at all right now (neither spawn nor attach).
	var filtered: Array[String] = []
	for id in pool_all:
		if _offer_is_playable_now(player, str(id)):
			filtered.append(str(id))
	if not filtered.is_empty():
		pool = filtered

	pool.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) ^ int(turn * 1315423911) ^ int(player * 2654435761)

	# Opening: hard-bias teaching genes when inventory has enough of them.
	var pick_pool: Array[String] = pool
	if opening:
		var teach: Array[String] = []
		for id in pool:
			if _OPENING_TEACH.has(str(id)):
				teach.append(str(id))
		if teach.size() >= 3:
			pick_pool = teach
		elif not teach.is_empty():
			# Any teach left → never roll specialty (Anchor/Brood/…) into the hand.
			var no_spec: Array[String] = []
			for id2 in pool:
				if not _OPENING_SPECIALTY.has(str(id2)):
					no_spec.append(str(id2))
			if not no_spec.is_empty():
				pick_pool = no_spec

	var cards: Array[String] = []
	var terrain_counts := _offer_terrain_counts_for_player(player)
	while cards.size() < hand_size:
		cards.append(_offer_weighted_pick(pick_pool, terrain_counts, rng))

	# Opening: unique faces + kick specialty + teaching body/combat when inventory allows.
	if opening:
		_offer_prefer_unique_opening(cards, pick_pool, rng)
		_offer_prefer_simple_opening(cards, pool)
		_offer_ensure_opening_teaching(cards, pool)

	# Stronger playability guarantee:
	# Ensure at least one offered card is currently playable via:
	# - Spawn: has a legal spawn cell AND inventory for that unit, OR
	# - Reinforce: selected squad is on RA and can accept a unit or heal.
	_offer_ensure_at_least_one_playable(cards, pool, player, rng)
	# If spawning is still possible for some inventory unit,
	# ensure at least one card can spawn — avoids "everything reinforces" draws when spawn is still legal.
	_offer_ensure_at_least_one_spawn_playable(cards, pool, player, rng)
	# Playability swaps can reintroduce Anchor/Brood — kick again while teach remains.
	if opening:
		_offer_prefer_simple_opening(cards, pool)

	return cards

func _generate_offer_mutants(cards: Array[String], player: int, turn: int) -> Array[bool]:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) ^ int(turn * 2246822519) ^ int(player * 3266489917) ^ 0x4D5554
	var out: Array[bool] = []
	for id in cards:
		var can_mut := UnitDefsScript.can_roll_mutant(str(id))
		out.append(can_mut and rng.randf() < UnitDefsScript.MUTANT_OFFER_CHANCE)
	# Opening 5-hand: guarantee at least one mutant when possible.
	if int(turn) <= 2 and cards.size() >= 5:
		var any := false
		for m in out:
			if m:
				any = true
				break
		if not any:
			for i in range(cards.size()):
				if UnitDefsScript.can_roll_mutant(str(cards[i])):
					out[i] = true
					break
	return out

## Teaching genes for opening hands (turns 1–2).
const _OPENING_TEACH := ["core", "claw", "eye", "hoof", "shell", "plate", "spring", "chunk"]
## Specialty tools out of opening 5 when a simpler unused face exists.
const _OPENING_SPECIALTY := [
	"anchor", "brood", "spore", "pod", "phase", "beacon", "node",
	"vent", "spine", "leap", "synapse", "ram", "gland", "airstrike",
]

func _offer_prefer_simple_opening(cards: Array[String], pool: Array[String]) -> void:
	var teach_remain := false
	for t in _OPENING_TEACH:
		if pool.has(t):
			teach_remain = true
			break
	var simple: Array[String] = []
	for p in pool:
		var id := str(p)
		if _OPENING_SPECIALTY.has(id):
			continue
		simple.append(id)
	if simple.is_empty():
		return
	# Prefer teaching faces when swapping specialty out.
	simple.sort_custom(func(a, b):
		var ta := _OPENING_TEACH.has(str(a))
		var tb := _OPENING_TEACH.has(str(b))
		if ta != tb:
			return ta
		return str(a) < str(b)
	)
	for i in range(cards.size()):
		var cid := str(cards[i])
		# Hard ban: Anchor/Brood never while any teach gene remains in inventory.
		var ban := _OPENING_SPECIALTY.has(cid)
		if teach_remain and (cid == "anchor" or cid == "brood"):
			ban = true
		if not ban:
			continue
		for s in simple:
			if cards.has(s):
				continue
			cards[i] = s
			break
		# Last resort: allow a teach already in-hand duplicate over Anchor/Brood.
		if teach_remain and (str(cards[i]) == "anchor" or str(cards[i]) == "brood"):
			for s2 in simple:
				if _OPENING_TEACH.has(str(s2)):
					cards[i] = s2
					break

## Opening hand: ≥1 spawn body (core) + ≥1 combat gene when pool allows.
func _offer_ensure_opening_teaching(cards: Array[String], pool: Array[String]) -> void:
	if cards.size() < 2:
		return
	var combat := ["eye", "claw", "hoof"]
	# Combat first so a later core fill cannot erase the only eye/claw/hoof.
	var has_c := false
	for c in combat:
		if cards.has(c):
			has_c = true
			break
	if not has_c:
		for c in combat:
			if pool.has(c):
				cards[1] = c
				break
	if pool.has("core") and not cards.has("core"):
		for i in range(cards.size()):
			if str(cards[i]) in combat:
				continue
			cards[i] = "core"
			return

func _offer_terrain_counts_for_player(player: int) -> Dictionary:
	# Returns {terrain_id -> count} based on current board state.
	# Uses alive squads if present; otherwise uses the player's spawn band terrain distribution.
	var counts := {
		int(BoardStateScript.TERRAIN_SOIL): 0,
		int(BoardStateScript.TERRAIN_ROCK): 0,
		int(BoardStateScript.TERRAIN_SAND): 0,
	}
	if board == null:
		return counts

	var any_squads := false
	for s in squads.values():
		var squad = s
		if squad == null or not squad.is_alive():
			continue
		if int(squad.owner) != int(player):
			continue
		any_squads = true
		var t := int(board.terrain_at(squad.cell))
		counts[t] = int(counts.get(t, 0)) + 1

	if any_squads:
		return counts

	# No squads yet: bias using spawn-band terrain as a proxy for "local environment".
	var y0: int = 0
	var y1: int = int(board.size.y) - 1
	var min_y: int = y0 if player == 0 else maxi(y0, y1 - (RulesScript.HOME_SPAWN_ROWS - 1))
	var max_y: int = mini(y1, (RulesScript.HOME_SPAWN_ROWS - 1)) if player == 0 else y1
	for y in range(min_y, max_y + 1):
		for x in range(0, int(board.size.x)):
			var c := Vector2i(x, y)
			var t := int(board.terrain_at(c))
			counts[t] = int(counts.get(t, 0)) + 1
	return counts

func _offer_preferred_terrain_for_unit(unit_def_id: String) -> int:
	match str(unit_def_id):
		"eye", "spine", "beacon", "node":
			return int(BoardStateScript.TERRAIN_ROCK)
		"hoof", "claw", "spring", "leap", "phase", "ram":
			return int(BoardStateScript.TERRAIN_SAND)
		"core", "shell", "vent", "plate", "chunk":
			return int(BoardStateScript.TERRAIN_SOIL)
		_:
			return int(BoardStateScript.TERRAIN_SOIL)

func _offer_weight_for_unit(unit_def_id: String, terrain_counts: Dictionary) -> int:
	var base := 10
	var pref := _offer_preferred_terrain_for_unit(unit_def_id)
	var pref_ct := int(terrain_counts.get(pref, 0))
	# Keep weights bounded and stable; counts are usually small.
	return maxi(1, base + (pref_ct * 5))

func _offer_weighted_pick(pool: Array[String], terrain_counts: Dictionary, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return "core"
	var total := 0
	for id in pool:
		total += _offer_weight_for_unit(str(id), terrain_counts)
	if total <= 0:
		return str(pool[rng.randi_range(0, pool.size() - 1)])

	var roll := rng.randi_range(1, total)
	var acc := 0
	for id in pool:
		acc += _offer_weight_for_unit(str(id), terrain_counts)
		if roll <= acc:
			return str(id)
	return str(pool[pool.size() - 1])

func _offer_prefer_unique_opening(cards: Array[String], pool: Array[String], _rng: RandomNumberGenerator) -> void:
	# Deterministic: swap each dup to the first unused pool id (sorted).
	# Keep eye/hoof doubles — decks stack those on purpose (kite plan).
	for i in range(cards.size()):
		var id := str(cards[i])
		if id == "eye" or id == "hoof":
			continue
		var earlier := false
		for j in range(i):
			if str(cards[j]) == id:
				earlier = true
				break
		if not earlier:
			continue
		var unused: Array[String] = []
		for p in pool:
			if not cards.has(str(p)):
				unused.append(str(p))
		if unused.is_empty():
			continue
		unused.sort()
		cards[i] = str(unused[0])

func _offer_has_any_playable(cards: Array[String], player: int) -> bool:
	for c in cards:
		if _offer_is_playable_now(player, str(c)):
			return true
	return false

func _offer_any_reinforce_possible(player: int, unit_def_id: String) -> bool:
	# Mirrors runtime reinforce targeting: any owned alive squad on an RA that can accept this card.
	if winner != -1:
		return false
	if not bool(offer_pending):
		return false

	var inv: Dictionary = player_inventory.get(player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return false

	var squad_ids: Array = squads.keys()
	squad_ids.sort()
	for sid_any in squad_ids:
		var sid := int(sid_any)
		if rules.can_play_card_reinforce(self, str(unit_def_id), sid):
			return true
	return false

func _offer_is_playable_now(player: int, unit_def_id: String) -> bool:
	if winner != -1:
		return false
	if not bool(offer_pending):
		# During generation we are in offer phase, but keep this safe for future callers.
		pass

	# Spawn playability: legal spawn cells exist AND inventory still has this unit id.
	var spawn_cells: Array[Vector2i] = rules.spawn_cells(self, player)
	if not spawn_cells.is_empty():
		var inv_spawn: Dictionary = player_inventory.get(player, {})
		if int(inv_spawn.get(unit_def_id, 0)) > 0:
			return true

	# Reinforce playability: any eligible squad on an RA (does not require pre-selection).
	if _offer_any_reinforce_possible(player, unit_def_id):
		return true

	return false

func _offer_playable_pool(pool: Array[String], player: int) -> Array[String]:
	var playable: Array[String] = []
	for id in pool:
		var uid := str(id)
		if _offer_is_playable_now(player, uid):
			playable.append(uid)
	return playable

func _offer_ensure_at_least_one_playable(cards: Array[String], pool: Array[String], player: int, rng: RandomNumberGenerator) -> void:
	if _offer_has_any_playable(cards, player):
		return
	var playable := _offer_playable_pool(pool, player)
	if playable.is_empty():
		# Nothing is playable right now (e.g. board locked + no RA reinforce/heal).
		# Keep deterministic behavior and return the drawn cards.
		return
	playable.sort()
	# Replace the first card deterministically with a playable option.
	cards[0] = str(playable[rng.randi_range(0, playable.size() - 1)])

func _offer_can_spawn_unit_now(player: int, unit_def_id: String) -> bool:
	if winner != -1:
		return false
	if not bool(offer_pending):
		return false

	var inv: Dictionary = player_inventory.get(player, {})
	if int(inv.get(unit_def_id, 0)) <= 0:
		return false

	var spawn_cells: Array[Vector2i] = rules.spawn_cells(self, player)
	if spawn_cells.is_empty():
		return false
	return true

func _offer_has_any_spawn_playable(cards: Array[String], player: int) -> bool:
	for c in cards:
		if _offer_can_spawn_unit_now(player, str(c)):
			return true
	return false

func _offer_spawn_playable_pool(pool: Array[String], player: int) -> Array[String]:
	var playable: Array[String] = []
	for id in pool:
		var uid := str(id)
		if _offer_can_spawn_unit_now(player, uid):
			playable.append(uid)
	return playable

func _offer_ensure_at_least_one_spawn_playable(cards: Array[String], pool: Array[String], player: int, rng: RandomNumberGenerator) -> void:
	# If no unit can spawn at all (no cells / no inventory), nothing to do.
	var any_spawn_exists := false
	for id in pool:
		if _offer_can_spawn_unit_now(player, str(id)):
			any_spawn_exists = true
			break
	if not any_spawn_exists:
		return

	if _offer_has_any_spawn_playable(cards, player):
		return

	var spawn_playable := _offer_spawn_playable_pool(pool, player)
	if spawn_playable.is_empty():
		return
	spawn_playable.sort()
	cards[0] = str(spawn_playable[rng.randi_range(0, spawn_playable.size() - 1)])

func _cell_to_arr(cell: Vector2i) -> Array:
	return [int(cell.x), int(cell.y)]

func _arr_to_cell(a) -> Vector2i:
	if a is Array and a.size() >= 2:
		return Vector2i(int(a[0]), int(a[1]))
	return Vector2i(0, 0)

func snapshot_dict() -> Dictionary:
	# Minimal deterministic snapshot for offline save/replay.
	var d := {}
	d["v"] = 1
	d["seed"] = int(seed)
	d["active_player"] = int(active_player)
	d["turn_number"] = int(turn_number)
	d["winner"] = int(winner)
	d["offer_pending"] = bool(offer_pending)
	d["offer_cards"] = offer_cards.duplicate()
	d["offer_mutants"] = offer_mutants.duplicate()
	d["offer_picks_remaining"] = int(offer_picks_remaining)
	d["player_inventory"] = player_inventory.duplicate(true)

	var bd := {}
	if board != null:
		bd["size"] = _cell_to_arr(board.size)
		bd["terrain"] = Array(board.terrain)
		bd["reinforcement_areas"] = []
		for c in board.reinforcement_areas:
			bd["reinforcement_areas"].append(_cell_to_arr(c))
		bd["control_points"] = []
		for cp in board.control_points:
			bd["control_points"].append({
				"cell": _cell_to_arr(cp.cell),
				"owner": int(cp.owner),
				"flags": cp.flags.duplicate(true),
			})
		bd["obstacles"] = []
		var cells: Array = board.obstacles.keys()
		cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in cells:
			var c: Vector2i = cell
			var o = board.obstacles.get(c, null)
			if o == null:
				continue
			bd["obstacles"].append({
				"cell": _cell_to_arr(c),
				"hp": int(o.get("hp", 0)),
				"destructible": bool(o.get("destructible", false)),
				"prop_kind": str(o.get("prop_kind", "")),
			})
		bd["hero_props"] = []
		for hp_any in board.hero_props:
			if typeof(hp_any) != TYPE_DICTIONARY:
				continue
			var hp: Dictionary = hp_any
			bd["hero_props"].append({
				"cell": _cell_to_arr(hp.get("cell", Vector2i.ZERO)),
				"kind": str(hp.get("kind", "mushroom")),
				"variant": int(hp.get("variant", 0)),
			})
		bd["hazards"] = []
		var hz_cells: Array = board.hazards.keys()
		hz_cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in hz_cells:
			var c: Vector2i = cell
			var h = board.hazards.get(c, null)
			if h == null:
				continue
			bd["hazards"].append({
				"cell": _cell_to_arr(c),
				"kind": str(h.get("kind", "")),
				"owner": int(h.get("owner", 0)),
				"damage": int(h.get("damage", 0)),
				"splash": int(h.get("splash", 0)),
			})
		bd["gear"] = []
		var gear_cells: Array = board.gear.keys()
		gear_cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in gear_cells:
			var c: Vector2i = cell
			var g = board.gear.get(c, null)
			if g == null:
				continue
			bd["gear"].append({
				"cell": _cell_to_arr(c),
				"unit_def_id": str(g.get("unit_def_id", "")),
				"is_mutant": bool(g.get("is_mutant", false)),
			})
		bd["eggs"] = []
		var egg_cells: Array = board.eggs.keys()
		egg_cells.sort_custom(func(a, b): return (a.x == b.x and a.y < b.y) or (a.x < b.x))
		for cell in egg_cells:
			var c: Vector2i = cell
			var e = board.eggs.get(c, null)
			if e == null:
				continue
			bd["eggs"].append({
				"cell": _cell_to_arr(c),
				"unit_def_id": str(e.get("unit_def_id", "")),
				"is_mutant": bool(e.get("is_mutant", false)),
			})
	d["board"] = bd

	var squads_arr := []
	var ids: Array = squads.keys()
	ids.sort()
	for sid in ids:
		var s = get_squad(int(sid))
		if s == null:
			continue
		var units_arr := []
		for u in s.units:
			var unit = u
			if unit == null:
				continue
			units_arr.append({
				"unit_def_id": str(unit.unit_def_id),
				"hp": int(unit.hp),
				"ready_turn": int(unit.ready_turn),
				"is_mutant": bool(unit.is_mutant),
			})
		squads_arr.append({
			"id": int(s.id),
			"owner": int(s.owner),
			"cell": _cell_to_arr(s.cell),
			"size_category": str(s.size_category),
			"fresh_turn": int(s.fresh_turn),
			"moved_turn": int(s.moved_turn),
			"cooldowns": s.cooldowns.duplicate(true),
			"snared_no_move_until_turn": int(s.snared_no_move_until_turn),
			"organs_locked": bool(s.organs_locked),
			"units": units_arr,
		})
	d["squads"] = squads_arr

	d["pending_effects"] = pending_effects.duplicate(true)
	d["next_pending_id"] = int(_next_pending_id)
	return d

func apply_snapshot_dict(d: Dictionary) -> void:
	# Overwrite current state from snapshot_dict().
	# Does not emit changed; caller can decide when to refresh UI.
	seed = int(d.get("seed", 0))
	active_player = int(d.get("active_player", 0))
	turn_number = int(d.get("turn_number", 1))
	winner = int(d.get("winner", -1))
	offer_pending = bool(d.get("offer_pending", false))
	offer_cards = []
	for c in d.get("offer_cards", []):
		offer_cards.append(str(c))
	offer_mutants = []
	for m in d.get("offer_mutants", []):
		offer_mutants.append(bool(m))
	offer_picks_remaining = int(d.get("offer_picks_remaining", 0))
	player_inventory = d.get("player_inventory", {0: {}, 1: {}}).duplicate(true)

	var bd: Dictionary = d.get("board", {})
	var size := _arr_to_cell(bd.get("size", [DEFAULT_BOARD_SIZE.x, DEFAULT_BOARD_SIZE.y]))
	board = BoardStateScript.new(size)
	if bd.has("terrain"):
		var t = bd.get("terrain", [])
		board.terrain = PackedInt32Array(t)
		# Defensive: ensure correct size.
		if board.terrain.size() != size.x * size.y:
			board.terrain.resize(size.x * size.y)
			board.terrain.fill(int(BoardStateScript.TERRAIN_SOIL))
	if bd.has("reinforcement_areas"):
		board.reinforcement_areas.clear()
		for a in bd.get("reinforcement_areas", []):
			board.reinforcement_areas.append(_arr_to_cell(a))
	if bd.has("control_points"):
		board.control_points.clear()
		for cp_d_any in bd.get("control_points", []):
			var cp_d: Dictionary = cp_d_any
			var cp = ControlPointStateScript.new(_arr_to_cell(cp_d.get("cell", [0, 0])))
			cp.owner = int(cp_d.get("owner", -1))
			cp.flags = cp_d.get("flags", {0: 0, 1: 0}).duplicate(true)
			board.control_points.append(cp)
	if bd.has("obstacles"):
		board.obstacles.clear()
		for o_any in bd.get("obstacles", []):
			var o: Dictionary = o_any
			var c := _arr_to_cell(o.get("cell", [0, 0]))
			board.obstacles[c] = {
				"hp": int(o.get("hp", 0)),
				"destructible": bool(o.get("destructible", false)),
				"prop_kind": str(o.get("prop_kind", "")),
			}
	board.hero_props.clear()
	for hp_any in bd.get("hero_props", []):
		if typeof(hp_any) != TYPE_DICTIONARY:
			continue
		var hp: Dictionary = hp_any
		board.hero_props.append({
			"cell": _arr_to_cell(hp.get("cell", [0, 0])),
			"kind": str(hp.get("kind", "mushroom")),
			"variant": int(hp.get("variant", 0)),
		})
	board.hazards.clear()
	for h_any in bd.get("hazards", []):
		var h: Dictionary = h_any
		var c := _arr_to_cell(h.get("cell", [0, 0]))
		board.set_hazard(c, str(h.get("kind", "mine")), int(h.get("owner", 0)), int(h.get("damage", 2)), int(h.get("splash", 0)))
	board.gear.clear()
	for g_any in bd.get("gear", []):
		var g: Dictionary = g_any
		var c := _arr_to_cell(g.get("cell", [0, 0]))
		board.set_gear(c, str(g.get("unit_def_id", "claw")), bool(g.get("is_mutant", false)))
	board.eggs.clear()
	for e_any in bd.get("eggs", []):
		var e: Dictionary = e_any
		var c := _arr_to_cell(e.get("cell", [0, 0]))
		board.set_egg(c, str(e.get("unit_def_id", "chunk")), bool(e.get("is_mutant", false)))

	pending_effects.clear()
	for pe_any in d.get("pending_effects", []):
		if typeof(pe_any) == TYPE_DICTIONARY:
			pending_effects.append((pe_any as Dictionary).duplicate(true))
	_next_pending_id = int(d.get("next_pending_id", 1))

	squads.clear()
	var max_id := 0
	for s_any in d.get("squads", []):
		var sd: Dictionary = s_any
		var sid := int(sd.get("id", 0))
		max_id = maxi(max_id, sid)
		var squad := SquadStateScript.new(sid, int(sd.get("owner", 0)), _arr_to_cell(sd.get("cell", [0, 0])))
		squad.size_category = str(sd.get("size_category", "small"))
		squad.fresh_turn = int(sd.get("fresh_turn", -1))
		squad.moved_turn = int(sd.get("moved_turn", -1))
		squad.cooldowns = sd.get("cooldowns", {}).duplicate(true)
		squad.snared_no_move_until_turn = int(sd.get("snared_no_move_until_turn", -1))
		squad.organs_locked = bool(sd.get("organs_locked", false))
		squad.units.clear()
		for u_any in sd.get("units", []):
			var ud: Dictionary = u_any
			squad.units.append(UnitStateScript.new(
				str(ud.get("unit_def_id", "core")),
				int(ud.get("hp", 1)),
				int(ud.get("ready_turn", 1)),
				bool(ud.get("is_mutant", false))
			))
		squads[sid] = squad
	_next_squad_id = max_id + 1
	selected_squad_id = -1

func _net_owner_from_squad_dict(sd: Dictionary) -> int:
	if sd.has("owner"):
		var ow = sd["owner"]
		if typeof(ow) == TYPE_STRING:
			return 0 if str(ow) == "A" else 1
		return int(ow)
	return 0

func _net_cell_from_squad_dict(sd: Dictionary) -> Vector2i:
	var cell_d: Dictionary = sd.get("cell", {"x": 0, "y": 0})
	return Vector2i(int(cell_d.get("x", 0)), int(cell_d.get("y", 0)))

func apply_authoritative_net_state(net: Dictionary) -> void:
	# Map server JSON into GameState. Merges squad cells when the server omits `units`
	# so optimistic local play (resolver + intent) keeps HP/loadouts while positions sync.
	selected_squad_id = -1

	var board_d: Dictionary = net.get("board", {})
	var w := int(board_d.get("w", DEFAULT_BOARD_SIZE.x))
	var h := int(board_d.get("h", DEFAULT_BOARD_SIZE.y))
	if board_d.has("size"):
		var sz = board_d.get("size")
		if sz is Array and (sz as Array).size() >= 2:
			w = int((sz as Array)[0])
			h = int((sz as Array)[1])

	if board == null or board.size != Vector2i(w, h):
		setup(Vector2i(w, h))

	active_player = 0 if str(net.get("active_player", "A")) == "A" else 1
	turn_number = int(net.get("turn", 1))
	if net.has("winner"):
		winner = int(net.get("winner", -1))
	else:
		winner = -1

	if net.has("offer_pending"):
		offer_pending = bool(net.get("offer_pending"))
		if net.has("offer_cards"):
			offer_cards.clear()
			for c in net.get("offer_cards", []):
				offer_cards.append(str(c))
	else:
		offer_pending = false
		offer_cards.clear()

	if board != null and board_d.has("hazards"):
		board.hazards.clear()
		for h_any in board_d.get("hazards", []):
			if typeof(h_any) != TYPE_DICTIONARY:
				continue
			var hz: Dictionary = h_any
			var c := _arr_to_cell(hz.get("cell", [0, 0]))
			board.set_hazard(c, str(hz.get("kind", "mine")), int(hz.get("owner", 0)), int(hz.get("damage", 2)), int(hz.get("splash", 0)))

	if net.has("pending_effects"):
		pending_effects.clear()
		for pe_any in net.get("pending_effects", []):
			if typeof(pe_any) == TYPE_DICTIONARY:
				pending_effects.append((pe_any as Dictionary).duplicate(true))
	if net.has("next_pending_id"):
		_next_pending_id = int(net.get("next_pending_id", 1))

	var incoming: Array = net.get("squads", [])
	var kept := {}
	var max_id := 0
	for s_any in incoming:
		if typeof(s_any) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s_any
		var sid := int(sd.get("id", 0))
		if sid == 0:
			continue
		kept[sid] = true
		max_id = maxi(max_id, sid)
		var owner := _net_owner_from_squad_dict(sd)
		var cell := _net_cell_from_squad_dict(sd)
		var units_raw = sd.get("units", [])
		var has_units := units_raw is Array and (units_raw as Array).size() > 0
		var existing = squads.get(sid)

		if has_units:
			var squad := SquadStateScript.new(sid, owner, cell)
			squad.size_category = str(sd.get("size_category", "small"))
			squad.fresh_turn = int(sd.get("fresh_turn", -1))
			squad.cooldowns = sd.get("cooldowns", {}).duplicate(true)
			squad.snared_no_move_until_turn = int(sd.get("snared_no_move_until_turn", -1))
			squad.units.clear()
			for u_any in sd.get("units", []):
				var ud: Dictionary = u_any
				squad.units.append(UnitStateScript.new(
					str(ud.get("unit_def_id", "core")),
					int(ud.get("hp", 1)),
					int(ud.get("ready_turn", 1)),
					bool(ud.get("is_mutant", false))
				))
			squads[sid] = squad
		elif existing != null:
			existing.cell = cell
			existing.owner = owner
		else:
			var squad2 := SquadStateScript.new(sid, owner, cell)
			squad2.size_category = "small"
			squad2.fresh_turn = -1
			squad2.cooldowns = {"melee": 0, "ranged": 0}
			squad2.units.clear()
			squad2.units.append(UnitStateScript.new("core", 1, turn_number))
			squads[sid] = squad2

	var to_remove: Array = []
	for sid_any in squads.keys():
		var sid2 := int(sid_any)
		if not kept.has(sid2):
			to_remove.append(sid2)
	for sidr in to_remove:
		squads.erase(sidr)

	_next_squad_id = max_id + 1
	emit_signal("changed")


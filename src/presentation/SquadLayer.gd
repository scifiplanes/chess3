extends Node3D

@export var squad_view_scene: PackedScene

const RulesScript = preload("res://src/sim/Rules.gd")

var _views := {} # int -> SquadView
var _rules = RulesScript.new()

func sync_from_game_state(gs, selected_squad_id: int, cell_size: float, attach_def_id: String = "") -> void:
	if gs == null:
		return

	var offer_pending := bool(gs.offer_pending)
	var game_over := int(gs.winner) != -1
	var attach_id := str(attach_def_id).strip_edges()

	# Create/update views for alive squads.
	var alive_ids: Array[int] = []
	for sid in gs.squads.keys():
		var id := int(sid)
		var squad = gs.get_squad(id)
		if squad == null or not squad.is_alive():
			continue
		alive_ids.append(id)

		var view = _views.get(id, null)
		if view == null:
			view = _spawn_view(id)
			if view == null:
				continue
			_views[id] = view

		var has_move := false
		var has_action := false
		if (not game_over) and (not offer_pending) and int(squad.owner) == int(gs.active_player):
			has_move = _rules.squad_has_available_move(gs, id)
			has_action = _rules.squad_has_available_action(gs, id)

		var attach_eligible := false
		if offer_pending and attach_id != "" and (not game_over):
			attach_eligible = bool(_rules.can_play_card_reinforce(gs, attach_id, id))

		view.sync_from_squad(squad, id == selected_squad_id, cell_size, has_move, has_action, attach_eligible, int(gs.turn_number))

	# Remove stale views (dead or removed squads).
	for existing_id in _views.keys():
		var id := int(existing_id)
		if not alive_ids.has(id):
			var view = _views[id]
			if is_instance_valid(view):
				if view.has_method("shed_all_organs_as_corpses"):
					view.call("shed_all_organs_as_corpses")
				var parent_n: Node = view.get_parent()
				if parent_n != null:
					parent_n.remove_child(view)
				view.free()
			_views.erase(id)

func play_hit_flash(squad_id: int) -> void:
	var view = _views.get(int(squad_id), null)
	if view == null:
		return
	if view.has_method("play_hit_flash"):
		view.call("play_hit_flash")

func play_graft_celebrate(squad_id: int) -> void:
	var view = _views.get(int(squad_id), null)
	if view == null:
		return
	if view.has_method("play_graft_celebrate"):
		view.call("play_graft_celebrate")

func play_reject_pulse(squad_id: int) -> void:
	var view = _views.get(int(squad_id), null)
	if view == null:
		return
	if view.has_method("reject_pulse"):
		view.call("reject_pulse")

func get_view(squad_id: int):
	return _views.get(int(squad_id), null)

func _spawn_view(squad_id: int):
	if squad_view_scene == null:
		return null
	var n := squad_view_scene.instantiate()
	var view = n
	add_child(n)
	if view != null:
		view.setup(squad_id)
	return view

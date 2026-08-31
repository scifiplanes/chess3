extends Node3D
class_name SquadView

const RulesScript = preload("res://src/sim/Rules.gd")
const UnitDefsScript = preload("res://src/sim/UnitDefs.gd")

@onready var unit_emojis: Label3D = $UnitEmojis
@onready var label: Label3D = $Label3D

var squad_id: int = -1
var _pips_root: Node3D
var _avail_root: Node3D
var _flash_tween: Tween
var _pulse_tween: Tween
var _last_has_move: bool = false
var _last_has_action: bool = false
var _avail_built: bool = false

func setup(p_squad_id: int) -> void:
	squad_id = p_squad_id
	_pips_root = get_node_or_null("Pips") as Node3D
	if _pips_root == null:
		_pips_root = Node3D.new()
		_pips_root.name = "Pips"
		add_child(_pips_root)
	_avail_root = get_node_or_null("Availability") as Node3D
	if _avail_root == null:
		_avail_root = Node3D.new()
		_avail_root.name = "Availability"
		add_child(_avail_root)

func sync_from_squad(squad, selected: bool, cell_size: float, has_move: bool = false, has_action: bool = false) -> void:
	if squad == null:
		return

	# Anchor visuals to grid cell center.
	position = Vector3((squad.cell.x + 0.5) * cell_size, 0.20, (squad.cell.y + 0.5) * cell_size)

	# Owner tint: P1 = cyan-ish, P2 = red-ish.
	var owner_color := Color(0.35, 0.85, 1.0)
	if squad.owner == 1:
		owner_color = Color(1.0, 0.45, 0.45)

	if unit_emojis:
		var parts := PackedStringArray()
		for u in squad.units:
			var unit = u
			if unit != null and int(unit.hp) > 0:
				parts.append(UnitDefsScript.emoji_for(unit.unit_def_id))
		unit_emojis.text = " ".join(parts)
		unit_emojis.modulate = owner_color
		unit_emojis.scale = Vector3.ONE * (1.12 if selected else 1.0)

	# Minimal state readability: HP + cooldowns.
	var hp := int(squad.total_hp_alive()) if squad.has_method("total_hp_alive") else 0
	var unit_count := int(squad.unit_count_alive()) if squad.has_method("unit_count_alive") else int(squad.units.size())
	var cd_text := ""
	var any_cd := false
	var ks: Array = squad.cooldowns.keys()
	ks.sort()
	for ck in ks:
		var v := int(squad.cooldowns.get(ck, 0))
		if v > 0:
			any_cd = true
			cd_text += "%s:%d " % [str(ck), v]
	if not any_cd:
		cd_text = "ready"

	if label:
		label.text = "S%d x%d/%d  HP:%d\n%s" % [squad.id, unit_count, RulesScript.SQUAD_MAX_TOTAL_UNITS, hp, cd_text]

	# Simple stack indicator (pips) for unit count.
	_render_pips(unit_count)
	if (not _avail_built) or has_move != _last_has_move or has_action != _last_has_action:
		_last_has_move = has_move
		_last_has_action = has_action
		_avail_built = true
		_render_availability(has_move, has_action)

func play_hit_flash() -> void:
	if unit_emojis == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var base := unit_emojis.modulate
	_flash_tween = create_tween()
	_flash_tween.tween_property(unit_emojis, "modulate", Color(1, 1, 1, 1), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_property(unit_emojis, "modulate", base, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _render_pips(unit_count: int) -> void:
	if _pips_root == null:
		return
	for c in _pips_root.get_children():
		c.queue_free()
	var n := clampi(unit_count, 0, RulesScript.SQUAD_MAX_TOTAL_UNITS)
	for i in range(n):
		var pip := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(0.08, 0.08, 0.08)
		pip.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 1.0, 1.0)
		mat.roughness = 0.9
		pip.material_override = mat
		pip.position = Vector3(-0.12 + i * 0.12, 0.52, 0.0)
		_pips_root.add_child(pip)

func _render_availability(has_move: bool, has_action: bool) -> void:
	if _avail_root == null:
		return
	for c in _avail_root.get_children():
		c.queue_free()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null
	_avail_root.scale = Vector3.ONE
	if not has_move and not has_action:
		return

	# Move = cyan foot ring; action = amber upper ring (both if both available).
	if has_move:
		_avail_root.add_child(_make_ring(Color(0.15, 0.95, 1.0, 0.85), 0.02, 0.42))
	if has_action:
		_avail_root.add_child(_make_ring(Color(1.0, 0.82, 0.2, 0.9), 0.06, 0.34))

	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_avail_root, "scale", Vector3(1.08, 1.0, 1.08), 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_avail_root, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _make_ring(color: Color, y: float, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = radius * 0.82
	tor.outer_radius = radius
	tor.rings = 12
	tor.ring_segments = 24
	mi.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 1.4
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	# TorusMesh already lies flat on the XZ plane (ground halo); no rotation needed.
	mi.position = Vector3(0.0, y, 0.0)
	return mi

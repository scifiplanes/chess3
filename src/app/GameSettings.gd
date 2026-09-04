extends Node

## Persisted player preferences (user://settings.cfg).

const PATH := "user://settings.cfg"

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var ui_volume: float = 1.0
var demo_tempo: String = "normal"
var fullscreen: bool = false
var vsync: bool = true
var camera_pan_sensitivity: float = 1.0
var camera_zoom_sensitivity: float = 1.0
var seen_opening_tutorial: bool = false
var seen_rules_overlay: bool = false
var seen_spawn_lock_tip: bool = false
var seen_field_graft_tip: bool = false
var seen_cp_zone_tip: bool = false
var seen_specialty_offer_tip: bool = false
var skip_pass_interstitial: bool = false

func _ready() -> void:
	load_settings()
	_apply_display()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	ui_volume = float(cfg.get_value("audio", "ui", ui_volume))
	demo_tempo = str(cfg.get_value("demo", "tempo", demo_tempo))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	camera_pan_sensitivity = float(cfg.get_value("controls", "camera_pan", camera_pan_sensitivity))
	camera_zoom_sensitivity = float(cfg.get_value("controls", "camera_zoom", camera_zoom_sensitivity))
	seen_opening_tutorial = bool(cfg.get_value("tutorial", "seen_opening", seen_opening_tutorial))
	seen_rules_overlay = bool(cfg.get_value("tutorial", "seen_rules_overlay", seen_rules_overlay))
	seen_spawn_lock_tip = bool(cfg.get_value("tutorial", "seen_spawn_lock", seen_spawn_lock_tip))
	seen_field_graft_tip = bool(cfg.get_value("tutorial", "seen_field_graft", seen_field_graft_tip))
	seen_cp_zone_tip = bool(cfg.get_value("tutorial", "seen_cp_zone", seen_cp_zone_tip))
	seen_specialty_offer_tip = bool(cfg.get_value("tutorial", "seen_specialty_offer", seen_specialty_offer_tip))
	skip_pass_interstitial = bool(cfg.get_value("hotseat", "skip_pass_interstitial", skip_pass_interstitial))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "ui", ui_volume)
	cfg.set_value("demo", "tempo", demo_tempo)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("controls", "camera_pan", camera_pan_sensitivity)
	cfg.set_value("controls", "camera_zoom", camera_zoom_sensitivity)
	cfg.set_value("tutorial", "seen_opening", seen_opening_tutorial)
	cfg.set_value("tutorial", "seen_rules_overlay", seen_rules_overlay)
	cfg.set_value("tutorial", "seen_spawn_lock", seen_spawn_lock_tip)
	cfg.set_value("tutorial", "seen_field_graft", seen_field_graft_tip)
	cfg.set_value("tutorial", "seen_cp_zone", seen_cp_zone_tip)
	cfg.set_value("tutorial", "seen_specialty_offer", seen_specialty_offer_tip)
	cfg.set_value("hotseat", "skip_pass_interstitial", skip_pass_interstitial)
	cfg.save(PATH)
	# Display apply is intentional from settings UI / boot only — not every tutorial flag write
	# (HTML5 window mode thrash can drop input / resize the canvas mid-click).

func apply_display() -> void:
	_apply_display()

func _apply_display() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func tempo_delays(tempo: String) -> Dictionary:
	match tempo:
		"slow":
			return {"offer": 1.2, "action": 2.0, "end_turn": 0.8, "between": 3.0}
		"fast":
			return {"offer": 0.15, "action": 0.25, "end_turn": 0.1, "between": 0.5}
		"turbo":
			return {"offer": 0.05, "action": 0.08, "end_turn": 0.05, "between": 0.2}
		_:
			return {"offer": 0.5, "action": 0.9, "end_turn": 0.4, "between": 1.5}

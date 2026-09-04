extends Node

## Carries launch config from menus into Main.tscn.

const DeckRulesScript = preload("res://src/app/DeckRules.gd")

enum Mode { NONE, HOTSEAT, DEMO }

var mode: Mode = Mode.NONE
var match_seed: int = 0
var inventories := {0: {}, 1: {}}
var style0: int = 0
var style1: int = 0
var demo_match_index: int = 0

func reset() -> void:
	mode = Mode.NONE
	match_seed = 0
	inventories = {0: {}, 1: {}}
	style0 = 0
	style1 = 0
	demo_match_index = 0

func configure_hotseat(p0: Dictionary, p1: Dictionary, seed: int = 0) -> void:
	mode = Mode.HOTSEAT
	match_seed = int(seed)
	inventories[0] = DeckRulesScript.sanitized_copy(p0)
	inventories[1] = DeckRulesScript.sanitized_copy(p1)
	style0 = 0
	style1 = 0

func configure_demo(seed: int = 0, s0: int = -1, s1: int = -1) -> void:
	mode = Mode.DEMO
	match_seed = int(seed) if int(seed) != 0 else int(Time.get_unix_time_from_system()) % 100000
	var pool: Dictionary = DeckRulesScript.DEFAULT_POOL.duplicate(true)
	inventories[0] = pool.duplicate(true)
	inventories[1] = pool.duplicate(true)
	style0 = s0 if s0 >= 0 else randi() % 6
	style1 = s1 if s1 >= 0 else randi() % 6
	demo_match_index = 0

func next_demo_match() -> void:
	demo_match_index += 1
	match_seed = int(Time.get_unix_time_from_system()) % 100000 + demo_match_index * 97
	style0 = randi() % 6
	style1 = randi() % 6

func skip_menu_boot() -> bool:
	for a in OS.get_cmdline_args():
		var s := str(a)
		if s == "--match" or s == "--net" or s.begins_with("--net=") or s.begins_with("--server="):
			return true
	return false

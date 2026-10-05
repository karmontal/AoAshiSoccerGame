class_name GameSettings
extends RefCounted
## Player settings, persisted to user://settings.cfg. Each setting is an index
## into its option list; the helpers below turn them into gameplay values.

const PATH := "user://settings.cfg"
const SECTION := "settings"

## Display order, label, options and default index of every setting.
const DEFS := [
	{"key": "match_length", "label": "MATCH LENGTH", "options": ["2 MIN", "3 MIN", "5 MIN"], "default": 1},
	{"key": "difficulty", "label": "DIFFICULTY", "options": ["EASY", "NORMAL", "HARD"], "default": 1},
	{"key": "graphics", "label": "GRAPHICS", "options": ["LOW", "MEDIUM", "HIGH"], "default": 2},
	{"key": "fps_limit", "label": "FPS LIMIT", "options": ["30", "60"], "default": 1},
	{"key": "camera", "label": "CAMERA", "options": ["NEAR", "NORMAL", "FAR"], "default": 1},
	{"key": "button_size", "label": "BUTTON SIZE", "options": ["SMALL", "NORMAL", "LARGE"], "default": 1},
	{"key": "left_handed", "label": "LEFT-HANDED", "options": ["OFF", "ON"], "default": 0},
	{"key": "vibration", "label": "VIBRATION", "options": ["OFF", "ON"], "default": 1},
	{"key": "show_fps", "label": "SHOW FPS", "options": ["OFF", "ON"], "default": 0},
]

## Remembered between matches but edited on the tactics screen, not in Settings.
const TACTICS_DEFS := [
	{"key": "formation", "label": "FORMATION", "options": Formations.NAMES, "default": 0},
	{"key": "mentality", "label": "MENTALITY", "options": Formations.MENTALITIES, "default": 1},
]

static var _values := {}
static var _loaded := false


static func get_value(key: String) -> int:
	_ensure_loaded()
	return _values[key]


static func enabled(key: String) -> bool:
	return get_value(key) == 1


static func option_text(key: String) -> String:
	return _def(key)["options"][get_value(key)]


## Moves a setting to the next/previous option (wrapping) and saves.
static func cycle(key: String, step: int) -> void:
	_ensure_loaded()
	var count: int = _def(key)["options"].size()
	_values[key] = posmod(_values[key] + step, count)
	save()


static func reset_to_defaults() -> void:
	for d: Dictionary in DEFS + TACTICS_DEFS:
		_values[d["key"]] = d["default"]
	_loaded = true
	save()


static func save() -> void:
	var cfg := ConfigFile.new()
	for key: String in _values:
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	var ok := cfg.load(PATH) == OK
	for d: Dictionary in DEFS + TACTICS_DEFS:
		var v: int = cfg.get_value(SECTION, d["key"], d["default"]) if ok else d["default"]
		_values[d["key"]] = clampi(v, 0, d["options"].size() - 1)


static func _def(key: String) -> Dictionary:
	for d: Dictionary in DEFS + TACTICS_DEFS:
		if d["key"] == key:
			return d
	push_error("Unknown setting: " + key)
	return {}


# --- Derived gameplay values ------------------------------------------------

static func match_seconds() -> float:
	return [120.0, 180.0, 300.0][get_value("match_length")]


## Opponent movement speed multiplier.
static func ai_speed() -> float:
	return [0.88, 1.0, 1.08][get_value("difficulty")]


## Opponent chance to win a tackle.
static func ai_tackle() -> float:
	return [0.25, 0.4, 0.55][get_value("difficulty")]


## Multiplier on how long the opponent takes to decide with the ball.
static func ai_reaction() -> float:
	return [1.6, 1.0, 0.7][get_value("difficulty")]


## Multiplier on the opponent's shooting error.
static func ai_shot_error() -> float:
	return [1.5, 1.0, 0.75][get_value("difficulty")]


static func camera_distance() -> float:
	return [0.8, 1.0, 1.22][get_value("camera")]


static func button_scale() -> float:
	return [0.82, 1.0, 1.2][get_value("button_size")]


## 0 = low, 1 = medium, 2 = high.
static func graphics() -> int:
	return get_value("graphics")


static func formation() -> String:
	return Formations.NAMES[get_value("formation")]


static func mentality() -> int:
	return get_value("mentality")

class_name GameAudio
extends Node
## Sound effects, the stadium crowd, menu music and match commentary.
## Effects and crowd are procedural (tools/gen_audio.py); the commentator's
## lines are recorded speech in audio/vo/. Match sounds go through
## SoccerMatch.fx("sfx"/"say") so co-op clients hear them too.

const SFX := ["kick", "kick_power", "tackle", "slide", "whistle", "whistle_long", "whistle_final",
		"whistle_foul", "net", "cheer", "ooh", "click", "vision_on", "vision_off", "success"]
## Commentary groups -> clips; one is picked at random.
const LINES := {
	"goal": ["goal_1", "goal_2", "goal_3"],
	"save": ["save_1", "save_2"],
	"miss": ["miss_1", "miss_2"],
	"foul": ["foul"],
	"penalty": ["penalty"],
	"freekick": ["freekick"],
	"through": ["through", "through_2"],
	"tackle": ["tackle"],
	"slide": ["slide"],
	"kickoff": ["kickoff"],
	"fulltime": ["fulltime"],
	"vision": ["vision"],
	"shot": ["shot"],
}
## Big moments interrupt whatever the commentator is saying.
const PRIORITY := {"goal": 3, "fulltime": 3, "penalty": 2, "save": 2, "miss": 2, "foul": 1, "kickoff": 1}
const VOICES := 8
const CROWD_DB := -13.0
const MUSIC_DB := -9.0

var game: SoccerMatch
## 0..1 how loud the crowd is; spikes on goals and chances, settles back.
var excitement := 0.0
## How many effects / lines have played, by name (used by the tests).
var played := {}
var _streams := {}
var _lines := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _crowd: AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice: AudioStreamPlayer
var _voice_priority := 0
var _voice_cooldown := 0.0
var _last_line := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name: String in SFX:
		_streams[name] = load("res://audio/%s.wav" % name)
	for group: String in LINES:
		for clip: String in LINES[group]:
			_lines[clip] = load("res://audio/vo/%s.ogg" % clip)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	var crowd: AudioStreamOggVorbis = load("res://audio/crowd_loop.ogg")
	crowd.loop = true
	_crowd = _loop_player(crowd)
	var music: AudioStreamOggVorbis = load("res://audio/menu_music.ogg")
	music.loop = true
	_music = _loop_player(music)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = 2.0
	add_child(_voice)


func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p


## One-shot effect. `pitch_jitter` varies repeated sounds (kicks) a little.
func play(name: String, volume_db := 0.0, pitch_jitter := 0.0) -> void:
	if not GameSettings.enabled("sound") or not _streams.has(name):
		return
	played[name] = played.get(name, 0) + 1
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[name]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


## A commentator line from a group. `chance` lets frequent events speak only sometimes.
func say(group: String, chance := 1.0) -> void:
	if not GameSettings.enabled("commentary") or not LINES.has(group) or randf() > chance:
		return
	var prio: int = PRIORITY.get(group, 0)
	if _voice.playing and (prio == 0 or prio < _voice_priority):
		return
	if prio == 0 and _voice_cooldown > 0.0:
		return
	var options: Array = LINES[group].duplicate()
	if options.size() > 1:
		options.erase(_last_line)
	_last_line = options.pick_random()
	played["say:" + group] = played.get("say:" + group, 0) + 1
	_voice.stream = _lines[_last_line]
	_voice.play()
	_voice_priority = prio
	_voice_cooldown = 4.0


## New match: drop whatever the commentator was still saying.
func stop_voice() -> void:
	_voice.stop()
	_voice_priority = 0
	_voice_cooldown = 0.0


func cheer(amount: float) -> void:
	excitement = maxf(excitement, amount)


func click() -> void:
	play("click", -6.0, 0.05)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	_voice_cooldown -= real
	excitement = maxf(excitement - real * 0.25, 0.0)
	var in_menu := game.state == SoccerMatch.State.MENU or game.state == SoccerMatch.State.CHALLENGE
	var crowd_db := -60.0
	if GameSettings.enabled("sound") and not in_menu:
		# Louder as the ball gets near either goal, roaring after big moments.
		var near_goal := clampf((absf(game.ball.pos.x) / Config.HALF_L - 0.55) / 0.45, 0.0, 1.0)
		var level := maxf(near_goal * 0.5, excitement)
		if game.state == SoccerMatch.State.FULLTIME:
			level = maxf(level, 0.3)
		crowd_db = CROWD_DB + 10.0 * level
	_crowd.volume_db = move_toward(_crowd.volume_db, crowd_db, real * 30.0)
	_crowd.pitch_scale = 1.0 + 0.06 * excitement
	var music_db := MUSIC_DB if GameSettings.enabled("music") and in_menu else -60.0
	_music.volume_db = move_toward(_music.volume_db, music_db, real * 25.0)

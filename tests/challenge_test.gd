extends SceneTree
## Daily Vision puzzles: determinism, scoring range, and the full tap flow.
## Run: godot --headless --path . --fixed-fps 60 -s tests/challenge_test.gd

var game: SoccerMatch
var f := 0
var wait := 0
var started := false


func _initialize() -> void:
	GameSettings.reset_to_defaults()
	DailyStats.clear()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_check_generation()


func _check_generation() -> void:
	# Same seed -> same puzzle; different days -> different puzzles.
	for kind: Challenge.Kind in ChallengeMode.DAILY_KINDS:
		var a := Challenge.make(kind, Challenge.daily_seed("2026-10-05", 0))
		var b := Challenge.make(kind, Challenge.daily_seed("2026-10-05", 0))
		var c := Challenge.make(kind, Challenge.daily_seed("2026-10-06", 0))
		assert(a.positions == b.positions and a.carrier_number == b.carrier_number)
		assert(a.positions != c.positions)
	# Over many seeds: positions on the pitch, a real spread between answers,
	# the best answer scores 100 and the worst 0.
	var best_answers := {}
	for kind: Challenge.Kind in ChallengeMode.DAILY_KINDS:
		for i in 40:
			var ch := Challenge.make(kind, 1000 + i)
			for t in 2:
				assert(ch.positions[t].size() == 11)
				for n: int in ch.positions[t]:
					var p: Vector2 = ch.positions[t][n]
					assert(absf(p.x) <= Config.HALF_L and absf(p.y) <= Config.HALF_W)
			var cands := ch.candidates()
			assert(cands.size() >= 10)
			cands.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
			assert(cands[0][1] - cands[-1][1] > 0.05, "answers must differ")
			assert(ch.score(cands[0][0], cands) == 100)
			assert(ch.score(cands[-1][0], cands) == 0)
			if kind == Challenge.Kind.PASS:
				best_answers[cands[0][0]] = true
	assert(best_answers.size() >= 4, "best pass should vary between puzzles")
	print("GENERATION OK")


func _process(_d: float) -> bool:
	f += 1
	if not started:
		started = true
		game.menus.show_page("daily")
		assert(not DailyStats.played_today())
		game.menus.show_page("")
		game.challenge.start_daily()
		assert(game.state == SoccerMatch.State.CHALLENGE)
		wait = 150
		return false
	if wait > 0:
		wait -= 1
		return false
	var ch := game.challenge
	if ch.active:
		if ch._phase == "ask":
			# Tap the best answer on screen, as a player would.
			var c := ch.current()
			var target: Vector2 = c.positions[c.me_team][ch._best] if c.kind == Challenge.Kind.PASS else ch._best
			assert(game.handle_screen_tap(game.camera.unproject_position(Config.to_3d(target))))
			print("%s puzzle scored %d" % [Challenge.SHORT_NAMES[c.kind], ch.results[-1]])
			assert(ch.results[-1] >= 90, "tapping the best spot should score near 100")
			wait = 20
		else:
			game.handle_screen_tap(Vector2(10, 10))
			wait = 150
		return false
	assert(game.state == SoccerMatch.State.MENU and game.menus.page == "daily_result")
	assert(DailyStats.played_today() and DailyStats.current_streak() == 1)
	var share := DailyStats.share_text(ch.results, ch.kinds())
	assert(share.contains("Daily Vision") and share.contains("Streak: 1"))
	print(share)
	# A second attempt the same day does not overwrite the first.
	DailyStats.record([0, 0, 0])
	assert(DailyStats.info()["last_scores"] == ch.results)
	DailyStats.clear()
	print("CHALLENGE FLOW OK")
	return true

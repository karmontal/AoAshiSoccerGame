class_name DailyStats
extends RefCounted
## Daily Vision progress, saved to user://daily.cfg: today's result, streak
## and best score, plus the shareable result text.

const PATH := "user://daily.cfg"
const SECTION := "daily"
const PUZZLES := 3
## Puzzle #1 was this day.
const EPOCH := "2026-10-01"


static func today() -> String:
	return Time.get_date_string_from_system()


static func day_number(date := today()) -> int:
	var days := (Time.get_unix_time_from_datetime_string(date) - Time.get_unix_time_from_datetime_string(EPOCH)) / 86400
	return int(days) + 1


static func info() -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return {
		"last_date": cfg.get_value(SECTION, "last_date", ""),
		"last_scores": cfg.get_value(SECTION, "last_scores", []),
		"streak": cfg.get_value(SECTION, "streak", 0),
		"best": cfg.get_value(SECTION, "best", 0),
		"played": cfg.get_value(SECTION, "played", 0),
	}


static func played_today() -> bool:
	return info()["last_date"] == today()


## Current streak, counting it as broken if yesterday was missed.
static func current_streak() -> int:
	var i := info()
	var last: String = i["last_date"]
	return i["streak"] if last == today() or last == _yesterday() else 0


static func record(scores: Array) -> void:
	var i := info()
	var date := today()
	if i["last_date"] == date:
		return  # Only the first attempt of the day counts.
	var total := 0
	for s: int in scores:
		total += s
	var streak: int = i["streak"] + 1 if i["last_date"] == _yesterday() else 1
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "last_date", date)
	cfg.set_value(SECTION, "last_scores", scores)
	cfg.set_value(SECTION, "streak", streak)
	cfg.set_value(SECTION, "best", maxi(i["best"], total))
	cfg.set_value(SECTION, "played", i["played"] + 1)
	cfg.save(PATH)


static func clear() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


static func grade_emoji(score: int) -> String:
	if score >= 80:
		return "🟩"
	if score >= 50:
		return "🟨"
	return "🟥"


## Wordle-style result to paste in a chat.
static func share_text(scores: Array, kinds: Array) -> String:
	var total := 0
	var squares := ""
	var parts := PackedStringArray()
	for i in scores.size():
		total += scores[i]
		squares += grade_emoji(scores[i])
		parts.append("%s %d" % [Challenge.SHORT_NAMES[kinds[i]], scores[i]])
	return "AO SOCCER · Daily Vision #%d\n%s  %d/%d\n%s\nStreak: %d" % [
		day_number(), squares, total, PUZZLES * 100, " · ".join(parts), current_streak()]


static func _yesterday() -> String:
	var t := Time.get_unix_time_from_datetime_string(today()) - 86400
	return Time.get_date_string_from_unix_time(t)

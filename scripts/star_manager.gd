extends Node

# ============================================================================
# Star Manager for Orbital Pop
# Daily star economy: 3 stars per day, 1 consumed per game fail,
# watch ad for 2 more stars
# ============================================================================

signal stars_changed(new_count: int)

const DAILY_STARS: int = 3
const AD_REWARD_STARS: int = 2
const MAX_STARS: int = 10

var stars: int = DAILY_STARS
var _stars_dirty: bool = false

func _ready() -> void:
	load_star_state()

func _get_today_string() -> String:
	var date = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]

func load_star_state() -> void:
	var config = ConfigFile.new()
	var err = config.load("user://save.cfg")
	if err == OK:
		var saved_date = config.get_value("stars", "date", "")
		var today = _get_today_string()
		if saved_date != today:
			# New day - grant daily stars (don't exceed max)
			stars = mini(DAILY_STARS, MAX_STARS)
			save_star_state()
		else:
			stars = config.get_value("stars", "count", DAILY_STARS)
	else:
		# First launch
		stars = DAILY_STARS
		save_star_state()

func save_star_state() -> void:
	_stars_dirty = true
	if is_inside_tree():
		_flush_star_save.call_deferred()
	else:
		_flush_star_save()

func _flush_star_save() -> void:
	if not _stars_dirty:
		return
	_stars_dirty = false
	var config = ConfigFile.new()
	config.load("user://save.cfg")  # Load existing to preserve other sections
	config.set_value("stars", "count", stars)
	config.set_value("stars", "date", _get_today_string())
	config.save("user://save.cfg")

func consume_star() -> bool:
	if stars <= 0:
		return false
	stars -= 1
	save_star_state()
	stars_changed.emit(stars)
	return true

func grant_ad_reward_stars() -> void:
	stars = mini(stars + AD_REWARD_STARS, MAX_STARS)
	save_star_state()
	stars_changed.emit(stars)

func has_stars() -> bool:
	return stars > 0

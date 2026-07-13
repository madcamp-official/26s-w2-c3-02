extends TextureProgressBar

## 경찰(악어) 대시 쿨타임 표시. 도넛이 채워질수록 대시 사용 가능에 가까워진다.
## GameData.phase == "playing"일 때만 표시된다.

const DONUT_SIZE := 72
const DONUT_RADIUS_OUTER := 34.0
const DONUT_RADIUS_INNER := 22.0
const TRACK_COLOR := Color(0.2, 0.2, 0.2, 0.55)
const FILL_COLOR_READY := Color(0.35, 0.85, 0.45, 0.95)
const FILL_COLOR_COOLDOWN := Color(0.85, 0.65, 0.25, 0.95)

@onready var _label: Label = $Label

var _texture_ready: ImageTexture
var _texture_cooldown: ImageTexture


func _ready() -> void:
	fill_mode = TextureProgressBar.FILL_CLOCKWISE
	radial_initial_angle = -90.0
	radial_fill_degrees = 360.0
	min_value = 0.0
	max_value = 1.0
	step = 0.0 # Range 기본 step=1.0이면 0/1로 반올림되어 중간값이 다 사라짐
	value = 0.0
	texture_under = RingTexture.generate(DONUT_SIZE, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER, TRACK_COLOR)
	_texture_ready = RingTexture.generate(DONUT_SIZE, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER, FILL_COLOR_READY)
	_texture_cooldown = RingTexture.generate(DONUT_SIZE, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER, FILL_COLOR_COOLDOWN)
	texture_progress = _texture_cooldown
	set_process(true)


func _process(_delta: float) -> void:
	var should_show := GameData.phase == "playing" and _local_team() == "tagger"
	if should_show != visible:
		visible = should_show
	if not visible:
		return

	var duration: float = max(GameData.dash_cooldown_duration, 0.001)
	var remaining: float = GameData.dash_cooldown_remaining
	var ready_fraction: float = clamp(1.0 - remaining / duration, 0.0, 1.0)
	value = ready_fraction
	texture_progress = _texture_ready if ready_fraction >= 1.0 else _texture_cooldown

	if remaining <= 0.0:
		_label.text = "대시"
	else:
		_label.text = "%.1f" % remaining


func _local_team() -> String:
	for player in GameData.players:
		if str(player.get("playerId", "")) == GameData.local_player_id:
			return str(player.get("team", "duck"))
	return "duck"

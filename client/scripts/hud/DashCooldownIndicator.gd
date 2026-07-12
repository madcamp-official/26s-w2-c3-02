extends Control

## 경찰(악어) 대시 쿨타임 표시. 도넛이 채워질수록 대시 사용 가능에 가까워진다.
## GameData.phase == "playing"일 때만 표시된다.

const DONUT_RADIUS_OUTER := 34.0
const DONUT_RADIUS_INNER := 22.0
const TRACK_COLOR := Color(0.2, 0.2, 0.2, 0.55)
const FILL_COLOR_READY := Color(0.35, 0.85, 0.45, 0.95)
const FILL_COLOR_COOLDOWN := Color(0.85, 0.65, 0.25, 0.95)
const ARC_POINTS := 48
const CENTER := Vector2(36, 36)

@onready var _label: Label = $Label

func _ready() -> void:
	set_process(true)

func _process(_delta: float) -> void:
	var should_show := GameData.phase == "playing" and _local_team() == "tagger"
	if should_show != visible:
		visible = should_show
	if not visible:
		return

	queue_redraw()
	var remaining := GameData.dash_cooldown_remaining
	if remaining <= 0.0:
		_label.text = "대시"
	else:
		_label.text = "%.1f" % remaining

func _local_team() -> String:
	for player in GameData.players:
		if str(player.get("playerId", "")) == GameData.local_player_id:
			return str(player.get("team", "duck"))
	return "duck"

func _draw() -> void:
	var duration: float = max(GameData.dash_cooldown_duration, 0.001)
	var remaining: float = GameData.dash_cooldown_remaining
	var ready_fraction: float = clamp(1.0 - remaining / duration, 0.0, 1.0)

	_draw_arc_filled(CENTER, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER,
		-PI * 0.5, -PI * 0.5 + TAU, TRACK_COLOR)

	if ready_fraction > 0.0:
		var fill_color := FILL_COLOR_READY if ready_fraction >= 1.0 else FILL_COLOR_COOLDOWN
		_draw_arc_filled(CENTER, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER,
			-PI * 0.5, -PI * 0.5 + TAU * ready_fraction, fill_color)

func _draw_arc_filled(center: Vector2, r_outer: float, r_inner: float,
		angle_from: float, angle_to: float, color: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var steps := ARC_POINTS
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := angle_from + (angle_to - angle_from) * t
		pts.append(center + Vector2(cos(a), sin(a)) * r_outer)
	for i in range(steps + 1):
		var t := float(steps - i) / float(steps)
		var a := angle_from + (angle_to - angle_from) * t
		pts.append(center + Vector2(cos(a), sin(a)) * r_inner)
	draw_colored_polygon(pts, color)

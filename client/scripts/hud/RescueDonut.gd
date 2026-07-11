extends Control

## 감옥 탈옥 진행률을 보여주는 도넛(원호) 그래프
## GameData.rescue_progress 가 0.0 초과이면 자동으로 표시된다.

const DONUT_RADIUS_OUTER := 48.0   # 바깥쪽 반지름
const DONUT_RADIUS_INNER := 30.0   # 안쪽(구멍) 반지름
const TRACK_COLOR     := Color(0.2, 0.2, 0.2, 0.55)  # 배경 트랙
const FILL_COLOR      := Color(0.35, 0.85, 0.45, 0.95) # 진행 아크
const TEXT_COLOR      := Color(1.0, 1.0, 1.0, 1.0)
const ARC_POINTS      := 64        # 아크를 구성하는 점 수 (클수록 부드러움)
const CENTER          := Vector2(50, 50)  # 컨트롤 내 중심 (크기 100×100 기준)

@onready var _pct_label: Label = $PctLabel

func _ready() -> void:
	visible = false
	set_process(true)

func _process(_delta: float) -> void:
	var progress := GameData.rescue_progress
	var should_show := progress > 0.0
	if should_show != visible:
		visible = should_show
	if visible:
		queue_redraw()
		_pct_label.text = "%d%%" % int(round(progress * 100.0))

func _draw() -> void:
	var progress := GameData.rescue_progress

	# ── 배경 트랙 (전체 원) ──────────────────────────────────────────────────
	_draw_arc_filled(CENTER, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER,
		-PI * 0.5, -PI * 0.5 + TAU, TRACK_COLOR)

	# ── 진행 아크 ─────────────────────────────────────────────────────────────
	if progress > 0.0:
		_draw_arc_filled(CENTER, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER,
			-PI * 0.5, -PI * 0.5 + TAU * progress, FILL_COLOR)

func _draw_arc_filled(center: Vector2, r_outer: float, r_inner: float,
		angle_from: float, angle_to: float, color: Color) -> void:
	# 아크 외곽선 점들 + 내곽선 점들을 이어서 폴리곤을 그린다.
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

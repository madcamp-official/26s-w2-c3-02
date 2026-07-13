extends TextureProgressBar

## 감옥 탈옥 진행률을 보여주는 도넛(원호) 그래프.
## GameData.rescue_progress 가 0.0 초과이면 자동으로 표시된다.

const DONUT_SIZE := 100
const DONUT_RADIUS_OUTER := 48.0
const DONUT_RADIUS_INNER := 30.0
const TRACK_COLOR := Color(0.2, 0.2, 0.2, 0.55)
const FILL_COLOR := Color(0.35, 0.85, 0.45, 0.95)

@onready var _pct_label: Label = $PctLabel


func _ready() -> void:
	visible = false
	fill_mode = TextureProgressBar.FILL_CLOCKWISE
	radial_initial_angle = -90.0
	radial_fill_degrees = 360.0
	min_value = 0.0
	max_value = 1.0
	step = 0.0 # Range 기본 step=1.0이면 0/1로 반올림되어 중간값이 다 사라짐
	value = 0.0
	texture_under = RingTexture.generate(DONUT_SIZE, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER, TRACK_COLOR)
	texture_progress = RingTexture.generate(DONUT_SIZE, DONUT_RADIUS_OUTER, DONUT_RADIUS_INNER, FILL_COLOR)
	set_process(true)


func _process(_delta: float) -> void:
	var progress := GameData.rescue_progress
	var should_show := progress > 0.0
	if should_show != visible:
		visible = should_show
	if visible:
		value = progress
		_pct_label.text = "%d%%" % int(round(progress * 100.0))

extends MeshInstance3D

## 물 위를 이동할 때 뒤에 남는 V자(보트 웨이크 모양) 물결 자국 하나. 생성 시점의
## 위치/방향에 고정된 채 시간이 지날수록 커지고 옅어지다가 스스로 사라진다.
## 사각 쿼드 대신 뾰족한 두 팔이 뒤로 벌어지는 화살촉 모양 메쉬를 직접 그려서
## 각진 느낌 없이 자연스러운 V자 실루엣을 만든다.

const LIFETIME := 1.4
const START_SCALE := 0.6
const END_SCALE := 1.8
const START_ALPHA := 0.5

const ARM_HALF_ANGLE := deg_to_rad(24.0) # 진행 방향(-Z) 기준 V자 팔이 벌어지는 각도
const ARM_LENGTH := 2.51
const ARM_WIDTH_START := 0.215 # 꼭짓점(진행 방향 앞쪽) 부근은 뾰족하게
const ARM_WIDTH_END := 1.97    # 뒤로 갈수록 굵고 옅게 퍼지도록
const APEX_FORWARD := 0.45     # 꼭짓점을 원점보다 살짝 앞으로 빼서 캐릭터 발끝에 맞춘다

# 스폰한 쪽(player.gd)에서 add_child 전에 설정 — 캐릭터 몸집에 맞춰 웨이크 크기를 키운다.
var size_scale := 1.0

var _time := 0.0
var _material: StandardMaterial3D

func _ready() -> void:
	mesh = _build_mesh()
	_material = (material_override as StandardMaterial3D).duplicate()
	material_override = _material
	scale = Vector3.ONE * START_SCALE * size_scale

func _process(delta: float) -> void:
	_time += delta
	var t: float = clamp(_time / LIFETIME, 0.0, 1.0)
	var s: float = lerp(START_SCALE, END_SCALE, t) * size_scale
	scale = Vector3(s, 1.0, s)
	_material.albedo_color.a = START_ALPHA * (1.0 - t)
	if t >= 1.0:
		queue_free()

func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_arm(st, 1.0)
	_add_arm(st, -1.0)
	st.generate_normals()
	return st.commit()

func _add_arm(st: SurfaceTool, side: float) -> void:
	# 로컬 -Z가 "진행 방향"이 되도록 맞춰 두면(캐릭터 모델과 동일한 forward 규약),
	# 꼭짓점은 앞쪽(-Z)에 두고 두 팔이 뒤(+Z)로 갈수록 벌어지며 옅어지게 만든다.
	var start_center := Vector3(0, 0, -APEX_FORWARD)
	var dir := Vector3(sin(ARM_HALF_ANGLE) * side, 0, cos(ARM_HALF_ANGLE))
	var end_center := start_center + dir * ARM_LENGTH
	var perp := Vector3(dir.z, 0, -dir.x)

	var start_left := start_center - perp * (ARM_WIDTH_START * 0.5)
	var start_right := start_center + perp * (ARM_WIDTH_START * 0.5)
	var end_left := end_center - perp * (ARM_WIDTH_END * 0.5)
	var end_right := end_center + perp * (ARM_WIDTH_END * 0.5)

	var c_start := Color(1, 1, 1, 1)
	var c_end := Color(1, 1, 1, 0)

	st.set_color(c_start)
	st.add_vertex(start_left)
	st.set_color(c_end)
	st.add_vertex(end_left)
	st.set_color(c_end)
	st.add_vertex(end_right)

	st.set_color(c_start)
	st.add_vertex(start_left)
	st.set_color(c_end)
	st.add_vertex(end_right)
	st.set_color(c_start)
	st.add_vertex(start_right)

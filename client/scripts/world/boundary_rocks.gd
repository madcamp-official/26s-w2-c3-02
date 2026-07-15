extends Node3D

const ROCK_SCENE_PATH := "res://assets/rock_fbx/Low_Poly_Rock_001.fbx"

const MAP_HALF_SIZE := 104.0
const EDGE_CENTER_OFFSET := Vector2(-3.07, -2.09)
const EDGE_INSET := 0
const EDGE_ROCKS_PER_SIDE := 55
const EDGE_JITTER := 0.40
const ROCK_SCALE := 5.5
const RANDOM_SEED := 20260713
# 220개(4면 x 55개)를 한 프레임에 다 인스턴스화하면 카운트다운 진입 시점에 스파이크가
# 몰려 버벅임으로 보인다. 여러 프레임에 나눠 스폰하되, 이 시간 안에는 무조건 전부
# 끝나도록 남은 시간 대비 남은 개수로 매 프레임 배치 크기를 다시 계산한다.
const BOUNDARY_ROCK_SPAWN_DURATION := 1.0

var _rock_scenes: Array[PackedScene] = []
var _rock_material: StandardMaterial3D = null

func _ready() -> void:
	_create_rock_material()
	_load_rock_scenes()
	_spawn_boundary_rocks_async()

func _create_rock_material() -> void:
	_rock_material = StandardMaterial3D.new()
	_rock_material.albedo_color = Color(0.55, 0.53, 0.5, 1)
	_rock_material.roughness = 0.95

func _load_rock_scenes() -> void:
	var scene := load(ROCK_SCENE_PATH)
	if scene is PackedScene:
		_rock_scenes.append(scene as PackedScene)

func _spawn_boundary_rocks_async() -> void:
	if _rock_scenes.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = RANDOM_SEED
	var edge := MAP_HALF_SIZE - EDGE_INSET
	var spacing := (edge * 2.0) / float(EDGE_ROCKS_PER_SIDE)

	var positions: Array[Vector3] = []
	for side in 4:
		for i in EDGE_ROCKS_PER_SIDE:
			var t := -edge + spacing * (float(i) + 0.5)
			positions.append(_edge_position(side, t, edge, rng))

	var start_ms := Time.get_ticks_msec()
	var total := positions.size()
	var spawned := 0
	while spawned < total:
		var elapsed := (Time.get_ticks_msec() - start_ms) / 1000.0
		var remaining_time := BOUNDARY_ROCK_SPAWN_DURATION - elapsed
		var remaining_count := total - spawned
		var batch_size: int
		if remaining_time <= 0.0:
			# 마감 시간을 넘었으면 프레임 분산을 포기하고 남은 걸 전부 이번 프레임에 끝낸다
			# (버벅임보단 낫고, 3초 보장이 우선이다).
			batch_size = remaining_count
		else:
			var estimated_frames_left: float = max(remaining_time * 60.0, 1.0)
			batch_size = max(1, ceili(remaining_count / estimated_frames_left))

		for _n in batch_size:
			if spawned >= total:
				break
			_spawn_rock(positions[spawned], rng)
			spawned += 1

		if spawned < total:
			await get_tree().process_frame

func _edge_position(side: int, t: float, edge: float, rng: RandomNumberGenerator) -> Vector3:
	var along_jitter := rng.randf_range(-EDGE_JITTER, EDGE_JITTER)
	var inward_jitter := rng.randf_range(-0.45, 0.45)
	match side:
		0:
			return Vector3(EDGE_CENTER_OFFSET.x + t + along_jitter, 0.1, EDGE_CENTER_OFFSET.y - edge + inward_jitter)
		1:
			return Vector3(EDGE_CENTER_OFFSET.x + t + along_jitter, 0.1, EDGE_CENTER_OFFSET.y + edge + inward_jitter)
		2:
			return Vector3(EDGE_CENTER_OFFSET.x - edge + inward_jitter, 0.1, EDGE_CENTER_OFFSET.y + t + along_jitter)
		_:
			return Vector3(EDGE_CENTER_OFFSET.x + edge + inward_jitter, 0.1, EDGE_CENTER_OFFSET.y + t + along_jitter)

func _spawn_rock(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var scene := _rock_scenes[0]
	var rock := scene.instantiate()
	if not rock is Node3D:
		rock.queue_free()
		return

	var rock_3d := rock as Node3D
	add_child(rock_3d)
	rock_3d.name = "BoundaryRock"
	rock_3d.position = pos
	rock_3d.rotation_degrees = Vector3(
		rng.randf_range(-4.0, 4.0),
		rng.randf_range(0.0, 360.0),
		rng.randf_range(-4.0, 4.0)
	)

	rock_3d.scale = Vector3.ONE * ROCK_SCALE
	_prepare_visual_rock(rock_3d)

func _prepare_visual_rock(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.material_override = _rock_material
	for child in node.get_children():
		_prepare_visual_rock(child)

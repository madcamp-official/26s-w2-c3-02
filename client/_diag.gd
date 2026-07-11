extends Node

func _ready() -> void:
	print("=== DIAG START ===")
	await _probe_menu()
	await _probe_game()
	print("=== DIAG END ===")
	get_tree().quit()

func _probe_menu() -> void:
	var scene: PackedScene = load("res://scenes/menu/MainMenu.tscn")
	var n: Node = scene.instantiate()
	add_child(n)
	for i in range(10):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	_report("MENU(main viewport composite)", img)
	# also grab the SubViewport's own texture directly
	var sv := n.get_node_or_null("LiveBackground/MenuViewport")
	if sv:
		var svimg: Image = sv.get_texture().get_image()
		_report("MENU(subviewport raw)", svimg)
	n.queue_free()
	await get_tree().process_frame

func _probe_game() -> void:
	var scene: PackedScene = load("res://scenes/world/Game.tscn")
	var n: Node = scene.instantiate()
	add_child(n)
	GameData.phase = "playing"
	for i in range(10):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	_report("GAME(main viewport)", img)
	n.queue_free()

func _report(label: String, img: Image) -> void:
	# sample a horizontal band around vertical middle (open water region)
	var w := img.get_width()
	var h := img.get_height()
	var avg := Color(0, 0, 0)
	var samples := 0
	var y := int(h * 0.5)
	for x in range(0, w, 4):
		avg += img.get_pixel(x, y)
		samples += 1
	avg /= samples
	print(label, " size=", Vector2i(w, h), " mid_row_avg=", avg)

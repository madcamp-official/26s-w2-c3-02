extends Node

const LOBBY_BGM_PATH := "res://assets/audio/bgm/lobby_bgm_loop.mp3"
const GAME_BGM_PATH := "res://assets/audio/bgm/game_bgm_loop.mp3"
const WARNING_BGM_PATH := "res://assets/audio/bgm/warning_bgm_loop.mp3"
const CLICK_SFX_PATH := "res://assets/audio/sfx/click.ogg"
const DASH_SFX_PATH := "res://assets/audio/sfx/dash_sound.mp3"
const DELIVERY_SFX_PATH := "res://assets/audio/sfx/delivery_sound.mp3"
const FREE_DUCK_SFX_PATH := "res://assets/audio/sfx/free_duck_sound.mp3"
const LOCKED_SFX_PATH := "res://assets/audio/sfx/locked_sound.mp3"
const QUACK_SFX_PATH := "res://assets/audio/sfx/quack_sound.mp3"
const MIN_VOLUME_DB := -80.0
const QUACK_INTERVAL := 5.0

var _bgm_player: AudioStreamPlayer
var _dash_sfx_player: AudioStreamPlayer
var _sfx_streams: Dictionary = {}
var _active_sfx_players: Array[AudioStreamPlayer] = []
var _current_bgm := ""
var _bgm_volume := 0.75
var _sfx_volume := 0.85
var _quack_timer := 0.0


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	_bgm_player.bus = "Master"
	add_child(_bgm_player)

	_dash_sfx_player = AudioStreamPlayer.new()
	_dash_sfx_player.name = "DashSfxPlayer"
	_dash_sfx_player.bus = "Master"
	add_child(_dash_sfx_player)

	_sfx_streams = {
		"click": load(CLICK_SFX_PATH),
		"dash": load(DASH_SFX_PATH),
		"delivery": load(DELIVERY_SFX_PATH),
		"free_duck": load(FREE_DUCK_SFX_PATH),
		"locked": load(LOCKED_SFX_PATH),
		"quack": load(QUACK_SFX_PATH),
	}
	_apply_volumes()

	if not GameData.game_event.is_connected(_on_game_event):
		GameData.game_event.connect(_on_game_event)
	get_tree().node_added.connect(_on_node_added)
	_connect_buttons_recursive(get_tree().root)
	play_lobby_bgm()
	set_process(true)


func play_lobby_bgm() -> void:
	_quack_timer = 0.0
	_play_bgm("lobby", LOBBY_BGM_PATH)


func play_game_bgm() -> void:
	_quack_timer = 0.0
	_play_bgm("game", GAME_BGM_PATH)


func play_warning_bgm() -> void:
	_quack_timer = 0.0
	_play_bgm("warning", WARNING_BGM_PATH)


func set_bgm_volume(value: float) -> void:
	_bgm_volume = clamp(value, 0.0, 1.0)
	_apply_volumes()


func set_sfx_volume(value: float) -> void:
	_sfx_volume = clamp(value, 0.0, 1.0)
	_apply_volumes()


func get_bgm_volume() -> float:
	return _bgm_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func play_click() -> void:
	play_sfx("click")


func play_sfx(key: String) -> void:
	if _sfx_volume <= 0.0:
		return
	var stream := _sfx_streams.get(key) as AudioStream
	if stream == null:
		return
	if key == "dash":
		_play_dash_sfx(stream)
		return
	_play_sfx_stream(stream)


func _process(delta: float) -> void:
	if (_current_bgm != "game" and _current_bgm != "warning") or (GameData.phase != "countdown" and GameData.phase != "playing"):
		return
	_quack_timer += delta
	if _quack_timer >= QUACK_INTERVAL:
		_quack_timer = 0.0
		play_sfx("quack")


func _play_bgm(key: String, path: String) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("AudioManager cannot load BGM: %s (%s)" % [key, path])
		return
	if _current_bgm == key and _bgm_player.playing:
		return
	_set_stream_loop(stream, true)
	_current_bgm = key
	_bgm_player.stop()
	_bgm_player.stream = null
	_bgm_player.stream = stream
	_apply_volumes()
	_bgm_player.play()


func _apply_volumes() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.volume_db = _linear_to_db(_bgm_volume)
	if is_instance_valid(_dash_sfx_player):
		_dash_sfx_player.volume_db = _linear_to_db(_sfx_volume)
	for player in _active_sfx_players:
		if is_instance_valid(player):
			player.volume_db = _linear_to_db(_sfx_volume)


func _play_dash_sfx(stream: AudioStream) -> void:
	_dash_sfx_player.stop()
	_dash_sfx_player.stream = stream
	_dash_sfx_player.volume_db = _linear_to_db(_sfx_volume)
	_dash_sfx_player.play()


func _play_sfx_stream(stream: AudioStream) -> void:
	var player := AudioStreamPlayer.new()
	player.name = "SfxPlayer"
	player.stream = stream
	player.volume_db = _linear_to_db(_sfx_volume)
	add_child(player)
	_active_sfx_players.append(player)
	player.finished.connect(_on_sfx_player_finished.bind(player))
	player.play()


func _on_sfx_player_finished(player: AudioStreamPlayer) -> void:
	_active_sfx_players.erase(player)
	player.queue_free()


func _linear_to_db(value: float) -> float:
	if value <= 0.0:
		return MIN_VOLUME_DB
	return linear_to_db(value)


func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	if stream == null:
		return
	for property in stream.get_property_list():
		var property_name := str(property.get("name", ""))
		if property_name == "loop":
			stream.set("loop", enabled)
		elif property_name == "loop_mode":
			stream.set("loop_mode", 1 if enabled else 0)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)


func _connect_buttons_recursive(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node as BaseButton)
	for child in node.get_children():
		_connect_buttons_recursive(child)


func _connect_button(button: BaseButton) -> void:
	if button.pressed.is_connected(_on_button_pressed):
		return
	button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_click()


func _on_game_event(event: String, _data: Dictionary) -> void:
	match event:
		"duckling_delivered":
			play_sfx("delivery")
		"player_rescued":
			play_sfx("free_duck")
		"player_jailed":
			play_sfx("locked")

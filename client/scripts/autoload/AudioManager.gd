extends Node

const LOBBY_BGM_PATH := "res://assets/audio/bgm/lobby_bgm_loop.mp3"
const GAME_BGM_PATH := "res://assets/audio/bgm/game_bgm_loop.mp3"
const CLICK_SFX_PATH := "res://assets/audio/sfx/click.ogg"
const MIN_VOLUME_DB := -80.0

var _bgm_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _lobby_bgm: AudioStream
var _game_bgm: AudioStream
var _click_sfx: AudioStream
var _current_bgm := ""
var _bgm_volume := 0.75
var _sfx_volume := 0.85


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "BgmPlayer"
	add_child(_bgm_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "SfxPlayer"
	add_child(_sfx_player)

	_lobby_bgm = load(LOBBY_BGM_PATH)
	_game_bgm = load(GAME_BGM_PATH)
	_click_sfx = load(CLICK_SFX_PATH)
	_set_stream_loop(_lobby_bgm, true)
	_set_stream_loop(_game_bgm, true)
	_apply_volumes()

	get_tree().node_added.connect(_on_node_added)
	_connect_buttons_recursive(get_tree().root)
	play_lobby_bgm()


func play_lobby_bgm() -> void:
	_play_bgm("lobby", _lobby_bgm)


func play_game_bgm() -> void:
	_play_bgm("game", _game_bgm)


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
	if _click_sfx == null or _sfx_volume <= 0.0:
		return
	_sfx_player.stream = _click_sfx
	_sfx_player.play()


func _play_bgm(key: String, stream: AudioStream) -> void:
	if stream == null:
		return
	if _current_bgm == key and _bgm_player.playing:
		return
	_current_bgm = key
	_bgm_player.stop()
	_bgm_player.stream = stream
	_bgm_player.play()


func _apply_volumes() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.volume_db = _linear_to_db(_bgm_volume)
	if is_instance_valid(_sfx_player):
		_sfx_player.volume_db = _linear_to_db(_sfx_volume)


func _linear_to_db(value: float) -> float:
	if value <= 0.0:
		return MIN_VOLUME_DB
	return linear_to_db(value)


func _set_stream_loop(stream: AudioStream, enabled: bool) -> void:
	if stream == null:
		return
	for property in stream.get_property_list():
		if str(property.get("name", "")) == "loop":
			stream.set("loop", enabled)
			return


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

## AudioManager.gd
## Global autoload — persists across scenes, manages background music.
extends Node

## Map scene paths to music tracks. Scenes not listed here stop music.
const SCENE_MUSIC: Dictionary = {
	"res://ui/MainMenu.tscn": "res://assets/audio/ost/main_screen.mp3",
	"res://ui/CollectionScene.tscn": "res://assets/audio/ost/main_screen.mp3",
	"res://ui/HeroSelectScene.tscn": "res://assets/audio/ost/main_screen.mp3",
	"res://ui/DeckBuilderScene.tscn": "res://assets/audio/ost/deck_build_screen.mp3",
	"res://talents/TalentSelectScene.tscn": "res://assets/audio/ost/deck_build_screen.mp3",
	"res://map/MapScene.tscn": "res://assets/audio/ost/deck_build_screen.mp3",
	"res://shop/ShopScene.tscn": "res://assets/audio/ost/shop.mp3",
}

## Scenes that pick music based on current act.
const COMBAT_SCENES: Array[String] = [
	"res://map/EncounterLoadingScene.tscn",
	"res://combat/board/CombatScene.tscn",
	"res://rewards/RewardScene.tscn",
	"res://relics/RelicRewardScene.tscn",
]

## Act number → combat music track.
const ACT_MUSIC: Dictionary = {
	1: "res://assets/audio/ost/act1_combat.mp3",
	2: "res://assets/audio/ost/act2_combat.mp3",
	3: "res://assets/audio/ost/act3_combat.mp3",
	4: "res://assets/audio/ost/act4_combat.mp3",
}

## Fade duration in seconds when switching tracks.
const FADE_DURATION: float = 1.0

var _current_track: String = ""
var _player: AudioStreamPlayer = null
var _tween: Tween = null

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	_player.volume_db = -10.0
	add_child(_player)
	get_tree().tree_changed.connect(_on_tree_changed)

func _on_tree_changed() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var path: String = scene.scene_file_path
	if path == "":
		return
	var target_track: String = _resolve_track(path)
	if target_track == _current_track:
		return
	_play_track(target_track)

func _resolve_track(scene_path: String) -> String:
	if scene_path in COMBAT_SCENES:
		var act: int = GameManager.get_current_act()
		return ACT_MUSIC.get(act, "") as String
	return SCENE_MUSIC.get(scene_path, "") as String

func _play_track(track_path: String) -> void:
	_current_track = track_path
	if _tween and _tween.is_valid():
		_tween.kill()
	if track_path == "":
		# Fade out and stop
		_tween = create_tween()
		_tween.tween_property(_player, "volume_db", -40.0, FADE_DURATION)
		_tween.tween_callback(_player.stop)
		return
	# Fade out old, then start new
	if _player.playing:
		_tween = create_tween()
		_tween.tween_property(_player, "volume_db", -40.0, FADE_DURATION * 0.5)
		_tween.tween_callback(_start_new_track.bind(track_path))
	else:
		_start_new_track(track_path)

func _start_new_track(track_path: String) -> void:
	var stream: AudioStream = load(track_path)
	if stream == null:
		push_warning("AudioManager: could not load '%s'" % track_path)
		return
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -10.0, FADE_DURATION * 0.5)

# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

## Play a one-shot sound effect. Automatically frees the player when done.
func play_sfx(path: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("AudioManager: could not load SFX '%s'" % path)
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	sfx.volume_db = volume_db
	sfx.bus = "Master"
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

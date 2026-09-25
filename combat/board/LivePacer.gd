## LivePacer.gd
## The live enemy's Pacer (plan 3.4): after every command, wait for the
## presenter to finish playing the journal, then a short beat so consecutive
## enemy actions read as separate moves. The sim's Pacer is a no-op.
class_name LivePacer
extends Pacer

const ACTION_DELAY := 0.55

var scene: Node = null


func setup(p_scene: Node) -> void:
	scene = p_scene


func after_action(_kind: String) -> void:
	if scene == null or not is_instance_valid(scene) or not scene.is_inside_tree():
		return
	await scene.presenter.pump_and_wait_idle()
	if not is_instance_valid(scene) or not scene.is_inside_tree():
		return
	await scene.get_tree().create_timer(ACTION_DELAY * BaseVfx.time_scale).timeout

extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Engine.time_scale = 1

# Called every frame. 'delta' is the elapsed time since the previous frame.

func frame_freeze(timescale:float, duration:float):
	Engine.time_scale = timescale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1

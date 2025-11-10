class_name sword
extends Node3D


signal attack_is_conected
@export var player:Player
@export var boss:Boss

func give_damage(damage:float):
	pass

func _on_area_3d_area_entered(area: Area3D) -> void:
	player.is_attack_connected = true
	


func _on_area_3d_area_exited(area: Area3D) -> void:
	player.is_attack_connected = false

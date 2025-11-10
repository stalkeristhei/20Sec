class_name Boss
extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var healthbar = $HealthBar
@onready var sprite_3d: Sprite3D = $Armature_049/Skeleton3D/BoneAttachment3D/Sprite3D

@export var player: Player
@export var health: float = 10.0
@export var RUN_RANGE: float = 15.0
@export var MIN_SPEED_FACTOR: float = 0.3
@export var MOVE_SPEED: float = 3.0
@export var ROOT_MOTION_SCALE: float = 50.0  # Make this adjustable in inspector

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var debug_timer: int = 0

func _ready() -> void:
	randomize()
	animation_tree.active = true
	healthbar.init_health(health)
	print("=== BOSS INITIALIZED ===")

func _physics_process(delta: float) -> void:
	debug_timer += 1
	var print_debug: bool = debug_timer % 60 == 0
	
	if not player:
		if print_debug:
			print("DEBUG: No player reference!")
		return

	# --- NAVIGATION SETUP ---
	nav_agent.target_position = player.global_position
	
	var direction = Vector3.ZERO
	if not nav_agent.is_navigation_finished():
		var next_point = nav_agent.get_next_path_position()
		direction = next_point - global_position
		direction.y = 0
		if direction.length() > 0.001:
			direction = direction.normalized()

	# --- ROTATION ---
	if direction != Vector3.ZERO:
		var target_rot_y = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_rot_y, delta * 5.0)

	# --- DISTANCE & MOVEMENT ---
	var distance_to_player = global_position.distance_to(player.global_position)
	var should_move = direction.length() > 0.01 and distance_to_player > 2.0

	# Get root motion data for debugging
	var root_motion = animation_tree.get_root_motion_position()
	
	if print_debug:
		print("=== BOSS DEBUG INFO ===")
		print("Distance to player: ", distance_to_player)
		print("Direction vector: ", direction)
		print("Direction length: ", direction.length())
		print("Should move: ", should_move)
		print("Root motion position: ", root_motion)
		print("Root motion length: ", root_motion.length())
		print("Current velocity: ", velocity)
		print("Is on floor: ", is_on_floor())
		print("Animation conditions - move: ", animation_tree.get("parameters/conditions/move"))
		print("Animation conditions - idle: ", animation_tree.get("parameters/conditions/idle"))
		print("=========================")

	if should_move:
		animation_tree.set("parameters/conditions/move", true)
		animation_tree.set("parameters/conditions/idle", false)
		
		if root_motion.length() > 0:
			# SCALE UP the root motion to make it usable
			root_motion *= ROOT_MOTION_SCALE
			
			if print_debug:
				print("Root motion after scaling: ", root_motion)
				print("Root motion length after scaling: ", root_motion.length())
			
			var current_rot = transform.basis.get_rotation_quaternion()
			velocity = (current_rot.normalized() * root_motion) / delta
		else:
			if print_debug:
				print("NO ROOT MOTION - Using direct movement")
			# Fallback: Use direct navigation movement
			velocity = direction * MOVE_SPEED
	else:
		animation_tree.set("parameters/conditions/move", false)
		animation_tree.set("parameters/conditions/idle", true)
		velocity.x = 0
		velocity.z = 0
		
		if print_debug:
			print("BOSS IDLE - No movement applied")

	# --- GRAVITY ---
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	var pre_move_position = global_position
	move_and_slide()
	var actual_movement = global_position - pre_move_position
	
	if print_debug and should_move:
		print("Actual movement this frame: ", actual_movement)
		print("Actual movement length: ", actual_movement.length())

	# --- Target indicator sprite ---
	sprite_3d.visible = player.is_targeting

func take_damage(damage_received: float) -> void:
	health -= damage_received
	print("Boss HP: ", health)
	if health <= 0:
		queue_free()

# Optional: Add input for manual debugging
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			print_deep_debug_info()

func print_deep_debug_info() -> void:
	print("=== DEEP BOSS DEBUG ===")
	print("Animation Tree Active: ", animation_tree.active)
	print("Animation Player Current Animation: ", animation_player.current_animation)
	print("Navigation Agent Target: ", nav_agent.target_position)
	print("Navigation Finished: ", nav_agent.is_navigation_finished())
	print("Global Position: ", global_position)
	print("Rotation: ", rotation)
	print("ROOT_MOTION_SCALE: ", ROOT_MOTION_SCALE)
	print("=========================")

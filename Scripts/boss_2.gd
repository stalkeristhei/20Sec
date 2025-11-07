class_name Boss
extends CharacterBody3D

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var animation_tree: AnimationTree = $AnimationTree

@export var player: CharacterBody3D
@export var WALK_SPEED: float = 1.5
@export var RUN_SPEED: float = 3.5
@export var GRAVITY: float = 9.8
@export var ATTACK_RANGE: float = 4.0
@export var RUN_RANGE: float = 10.0 # Start running when within this range

@export var health = 10
@onready var healthbar = $HealthBar 

enum STATE { WALK, RUN, JUMP_ATTACK, SLASH }
var state: STATE = STATE.WALK


func _ready() -> void:
	#healthp = healthp
	healthbar.init_health(health)
	
	animation_tree.active = true
	animation_tree.animation_finished.connect(_on_animation_finished)
	randomize() # Seed RNG for attack randomness

#func _set_health(value):
	#super._set_health(value)
	#if health <=0:
	#	print("dead")
		
	healthbar.health = health

func _physics_process(delta: float) -> void:
	if not player:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var current_velocity = self.velocity

	# --- Apply gravity ---
	if not is_on_floor():
		current_velocity.y -= GRAVITY * delta
	else:
		current_velocity.y = 0.0

	var distance_to_player = global_position.distance_to(player.global_position)

	match state:
		STATE.WALK, STATE.RUN:
			# --- Navigation logic ---
			nav_agent.target_position = player.global_position

			var direction = Vector3.ZERO
			if not nav_agent.is_navigation_finished():
				var next_point = nav_agent.get_next_path_position()
				direction = next_point - global_position

			direction.y = 0
			if direction.length() > 0.001:
				direction = direction.normalized()

			# Face player
			var look_at_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
			if global_position.distance_to(look_at_pos) > 0.1:
				look_at(look_at_pos, Vector3.UP)

			# ✅ This logic correctly uses the state to set speed
			var speed = RUN_SPEED if state == STATE.RUN else WALK_SPEED
			self.velocity = Vector3(direction.x * speed, current_velocity.y, direction.z * speed)

			# --- State transitions (FIXED) ---
			if distance_to_player < ATTACK_RANGE:
				choose_attack()
			elif distance_to_player < RUN_RANGE and state != STATE.RUN:
				# Player is close, so WALK
				state = STATE.WALK
			else:
				# Player is far, so RUN
				state = STATE.RUN

		STATE.JUMP_ATTACK, STATE.SLASH:
			# During attack — just face the player and stay still horizontally
			var look_at_pos = Vector3(player.global_position.x, global_position.y, player.global_position.z)
			look_at(look_at_pos, Vector3.UP)
			self.velocity = Vector3(0.0, current_velocity.y, 0.0)

	move_and_slide()
	handle_animations()
	update_animation(self.velocity)


# --- Random attack chooser ---
func choose_attack() -> void:
	var attack_choices = [STATE.JUMP_ATTACK, STATE.SLASH]
	state = attack_choices[randi() % attack_choices.size()]


# --- Called when any animation finishes ---
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "jump_attack" or anim_name == "slash":
		state = STATE.WALK
		handle_animations()


func handle_animations() -> void:
	# Reset triggers
	animation_tree.set("parameters/conditions/j_attack", false)
	animation_tree.set("parameters/conditions/slash", false)
	animation_tree.set("parameters/conditions/walk", false)
	animation_tree.set("parameters/conditions/run", false)

	match state:
		STATE.JUMP_ATTACK:
			animation_tree.set("parameters/conditions/j_attack", true)
		STATE.SLASH:
			animation_tree.set("parameters/conditions/slash", true)
		STATE.RUN:
			animation_tree.set("parameters/conditions/run", true)
		STATE.WALK:
			animation_tree.set("parameters/conditions/walk", true)


func update_animation(global_velocity: Vector3) -> void:
	var local_velocity = transform.basis.inverse() * global_velocity
	var blend_pos = Vector2(local_velocity.x / RUN_SPEED, local_velocity.z / RUN_SPEED)
	animation_tree.set("parameters/BlendSpace2D/blend_position", blend_pos)


func is_in_range() -> bool:
	return global_position.distance_to(player.global_position) < ATTACK_RANGE
	
	
func take_damage(damage_recieved:float):
	health = health - damage_recieved
	print(health)
	
func give_damage():
	pass

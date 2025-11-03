class_name Player

extends CharacterBody3D

# --- SETTINGS ---
@export var mouse_sensitivity_x: float = 0.5
@export var mouse_sensitivity_y: float = 0.5
@export_range(0, 90, 1) var target_vertical_nudge_limit: float = 20.0
@export_range(0, 90, 1) var target_horizontal_nudge_limit: float = 45.0
@export var SPEED: float = 3.5
@export var RUN_SPEED: float = 6.5
@export var targeting_speed: float = 5.0
@export var DASH_MAX_CHARGE_TIME: float = 1.5
@export var DASH_MIN_SPEED: float = 10.0
@export var DASH_MAX_SPEED: float = 25.0
@export var DASH_DURATION: float = 0.3
@export var ENEMY: CharacterBody3D
@export var dash_cooldown:float= 0.5	#seconds
@export var attack_cooldown:float = 0.4
@export var ATTACK_SPEED:float=1
const JUMP_VELOCITY: float = 4.5
var GRAVITY: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- NODES ---
@onready var gpu_trail_3d: GPUTrail3D = $visuals/Skeleton3D/GPUTrail3D
@onready var visuals: Node3D = $visuals
@onready var camera_mount: Node3D = $"Camera Mount"
@onready var animation_player: AnimationPlayer = $visuals/AnimationPlayer
@onready var combo_timer: Timer = $ComboTimer
# --- NEW: CAMERA SHAKE NODE ---
# !!! IMPORTANT: Update this path if your Camera3D is not a direct child of 'Camera Mount'
@onready var camera_node: Camera3D = $"Camera Mount/Camera3D"

# --- STATES ---
enum STATE { IDLE, WALK, RUN, DASH_CHARGE, DASH, ATTACK, HURT, DEATH }
var state: STATE = STATE.IDLE

# --- DASH ---
var dash_charge_time: float = 0.0
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var is_charging: bool = false
var last_dash_time:float= 0.0
var last_attack_time:float=0.0

# --- COMBO SYSTEM VARIABLES ---
var combo_step: int = 0
var can_queue_next_combo: bool = false
var is_attack_queued: bool = false

# --- COMBO TIMINGS (in seconds) ---
const COMBO_P1_WINDOW_START: float = 0.8  # During 1.4s anim
const COMBO_P2_WINDOW_START: float = 0.4  # During 0.7s anim
const COMBO_P3_WINDOW_START: float = 0.3  # During 0.5s anim

# --- TARGETING ---
var is_targeting: bool = false

# --- NEW: CAMERA SHAKE VARIABLES ---
var original_cam_pos: Vector3 = Vector3.ZERO
var shake_timer: float = 0.0
var shake_max_strength: float = 0.0
var shake_max_duration: float = 1.0

var is_attack_connected:bool=false
# --------------------------------------------------

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hide_trails()
	
	# --- NEW: Store original camera position for shake reset ---
	if camera_node:
		original_cam_pos = camera_node.position
	else:
		# This warning helps you debug if the path is wrong
		push_warning("Camera shake node not found. Did you set the 'camera_node' path correctly?")

# --------------------------------------------------
# -------------------- INPUT -----------------------
# --------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		handle_mouse_motion(event)
	elif event.is_action_pressed("Target"):
		toggle_targeting()
	
	if event.is_action_pressed("Attack"):
		handle_attack()

# Mouse handling
func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var dx = deg_to_rad(event.relative.x)
	var dy = deg_to_rad(event.relative.y)

	if is_targeting:
		# Rotate only the camera mount ("nudge" mode)
		camera_mount.rotate_y(-dx * mouse_sensitivity_x)
		camera_mount.rotate_x(-dy * mouse_sensitivity_y)

		var rot = camera_mount.rotation_degrees
		rot.x = clamp(rot.x, -target_vertical_nudge_limit, target_vertical_nudge_limit)
		rot.y = clamp(rot.y, -target_horizontal_nudge_limit, target_horizontal_nudge_limit)
		camera_mount.rotation_degrees = Vector3(rot.x, rot.y, 0)
	else:
		# Free-look mode
		rotate_y(-dx * mouse_sensitivity_x)
		camera_mount.rotate_x(-dy * mouse_sensitivity_y)

		var x = clamp(camera_mount.rotation_degrees.x, -10, 20)
		camera_mount.rotation_degrees = Vector3(x, 0, 0)

# Toggle lock-on targeting
func toggle_targeting() -> void:
	is_targeting = !is_targeting
	
	var cam_rot_rad = camera_mount.rotation
	
	if is_targeting:
		camera_mount.rotation = Vector3(cam_rot_rad.x, 0, 0)
	else:
		rotate_y(cam_rot_rad.y)
		camera_mount.rotation = Vector3(cam_rot_rad.x, 0, 0)
		visuals.transform.basis = Basis()

func _physics_process(delta: float) -> void:
	handle_gravity_and_jump()
	handle_dash(delta)
	handle_targeting_rotation(delta)
	# --- NEW: Handle camera shake every frame ---
	handle_camera_shake(delta)

	if state != STATE.ATTACK:
		handle_movement(delta)
		handle_animations()

# --------------------------------------------------
# ---------------- CORE LOGIC ----------------------
# --------------------------------------------------

func handle_attack():
	if state == STATE.ATTACK:
		if can_queue_next_combo:
			is_attack_queued = true
			can_queue_next_combo = false 
	
	elif can_start_new_attack():
		state = STATE.ATTACK
		combo_step = 1
		is_attack_queued = false
		can_queue_next_combo = false
		set_anim("sword_combo_p1") 

func handle_gravity_and_jump() -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * get_physics_process_delta_time()
	elif Input.is_action_just_pressed("Jump"):
		velocity.y = JUMP_VELOCITY

# --- DASH LOGIC ---
func handle_dash(delta: float) -> void:
	if state == STATE.DASH:
		dash_timer -= delta
		if dash_timer <= 0:
			state = STATE.IDLE
			velocity = Vector3.ZERO
		else:
			move_and_slide()
		return

	if Input.is_action_just_pressed("Dash") and can_move() and can_dash():
		state = STATE.DASH_CHARGE
		is_charging = true
		dash_charge_time = 0.0

	if is_charging:
		if Input.is_action_pressed("Dash"):
			dash_charge_time = clamp(dash_charge_time + delta, 0, DASH_MAX_CHARGE_TIME)
		elif Input.is_action_just_released("Dash"):
			is_charging = false
			start_dash()

# --- TARGETING ROTATION ---
func handle_targeting_rotation(delta: float) -> void:
	if not is_targeting:
		return

	if not is_instance_valid(ENEMY):
		is_targeting = false
		return

	var target_pos = ENEMY.global_position
	var look_pos = Vector3(target_pos.x, global_position.y, target_pos.z)
	var target_basis = transform.looking_at(look_pos, Vector3.UP).basis

	transform.basis = transform.basis.slerp(target_basis, delta * targeting_speed).orthonormalized()
	
# --- MOVEMENT ---
func handle_movement(delta: float) -> void:
	if state == STATE.DASH:
		if velocity.length_squared() > 0:
			visuals.look_at(position + velocity.normalized())
		return

	var input_dir = Input.get_vector("Left", "Right", "Fwd", "Bkwd")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var moving = direction != Vector3.ZERO
	var running = Input.is_action_pressed("Sprint")

	if can_move():
		state = (
			STATE.RUN if moving and running else
			STATE.WALK if moving else
			STATE.IDLE
		)

	if moving:
		visuals.look_at(position + direction)
	elif is_targeting:
		if state == STATE.DASH_CHARGE:
			pass
		else:
			visuals.transform.basis = visuals.transform.basis.slerp(Basis(), delta * targeting_speed)

	if moving and can_move():
		var speed = RUN_SPEED if running else SPEED
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
# --------------------------------------------------
# ----------------- HELPERS ------------------------
# --------------------------------------------------

func _on_animation_player_animation_finished(anim_name):
	if not (anim_name in ["sword_combo_p1", "sword_combo_p2", "sword_combo_p3"]):
		return 

	combo_timer.stop()
	can_queue_next_combo = false

	if is_attack_queued:
		is_attack_queued = false 
		
		if anim_name == "sword_combo_p1":
			combo_step = 2
			set_anim("sword_combo_p2")
		elif anim_name == "sword_combo_p2":
			combo_step = 3
			set_anim("sword_combo_p3")
		elif anim_name == "sword_combo_p3":
			combo_step = 1
			set_anim("sword_combo_p1")
			
	else:
		combo_step = 0
		if state != STATE.DEATH and state != STATE.HURT:
			state = STATE.IDLE
		
		last_attack_time = Time.get_ticks_msec()


func can_move() -> bool:
	return not (state in [STATE.ATTACK, STATE.HURT, STATE.DEATH, STATE.DASH_CHARGE])

func can_dash():
	return Time.get_ticks_msec() - last_dash_time >= dash_cooldown*1000
	
func start_dash() -> void:
	state = STATE.DASH
	last_dash_time = Time.get_ticks_msec()
	var charge_ratio = dash_charge_time / DASH_MAX_CHARGE_TIME
	var dash_speed = lerp(DASH_MIN_SPEED, DASH_MAX_SPEED, charge_ratio)

	var input_dir = Input.get_vector("Left", "Right", "Fwd", "Bkwd")
	dash_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if dash_direction == Vector3.ZERO:
		dash_direction = -visuals.global_transform.basis.z.normalized()

	velocity = dash_direction * dash_speed
	dash_timer = DASH_DURATION
	handle_animations()

# --------------------------------------------------
# ---------------- ANIMATIONS ----------------------
# --------------------------------------------------

func handle_animations() -> void:
	match state:
		STATE.IDLE:		set_anim("mixamo_com")
		STATE.WALK:		set_anim("walk")
		STATE.RUN:		set_anim("run")
		STATE.HURT:		set_anim("hurt")
		STATE.DEATH:		set_anim("death")
		STATE.DASH_CHARGE: set_anim("dash_charge")
		STATE.DASH:
			set_anim("dash_mid_end")
			show_trails()
			return
	
	if state != STATE.ATTACK:
		hide_trails()

func set_anim(anim: String) -> void:
	# Only play if it's not already playing
	if animation_player.current_animation != anim:
		animation_player.play(anim)
	
	# --- APPLY ATTACK SPEED SCALING ---
	if anim in ["sword_combo_p1", "sword_combo_p2", "sword_combo_p3"]:
		animation_player.speed_scale = ATTACK_SPEED
	else:
		animation_player.speed_scale = 1.0
	# --- END SPEED CONTROL ---

	# Handle combo timing
	combo_timer.stop()
	can_queue_next_combo = false
	
	if anim in ["sword_combo_p1", "sword_combo_p2", "sword_combo_p3"]:
		var speed_scale = ATTACK_SPEED
		if anim == "sword_combo_p1":
			combo_timer.start(COMBO_P1_WINDOW_START/speed_scale)
		elif anim == "sword_combo_p2":
			combo_timer.start(COMBO_P2_WINDOW_START/speed_scale)
		elif anim == "sword_combo_p3":
			combo_timer.start(COMBO_P3_WINDOW_START/speed_scale)


# --------------------------------------------------
# ---------------- TRAILS --------------------------
# --------------------------------------------------

func show_trails() -> void:
	if gpu_trail_3d:
		gpu_trail_3d.visible = true
		gpu_trail_3d.emitting = true

func can_start_new_attack():
	var is_cooldown_ready = Time.get_ticks_msec() - last_attack_time >= attack_cooldown * 1000
	var is_in_valid_state = state in [STATE.IDLE, STATE.WALK, STATE.RUN]
	return is_cooldown_ready and is_in_valid_state
	
func _on_combo_timer_timeout():
	can_queue_next_combo = true

func hide_trails() -> void:
	if gpu_trail_3d:
		gpu_trail_3d.emitting = false
		gpu_trail_3d.visible = false

# --------------------------------------------------
# ----------------- GAME JUICE ---------------------
# --------------------------------------------------

func attack_connected():
	Global.frame_freeze(0.1, 0.2)
	# --- NEW: Example of how to call the shake function! ---
	start_camera_shake(0.15, 0.2)


# --- NEW: Call this function to start the shake ---
# strength: How far the camera can move (e.g., 0.1 to 0.5 is good)
# duration: How long the shake lasts in seconds (e.g., 0.2)
func start_camera_shake(strength: float = 0.2, duration: float = 0.3):
	# Don't override a stronger shake
	if strength > shake_max_strength:
		shake_max_strength = strength
	
	shake_max_duration = duration
	shake_timer = duration

# --- NEW: This function runs every frame to apply the shake ---
func handle_camera_shake(delta: float):
	if not camera_node:
		return # Don't try to shake if node is invalid

	if shake_timer > 0:
		shake_timer -= delta
		if shake_timer <= 0:
			# --- Shake finished ---
			shake_timer = 0.0
			camera_node.position = original_cam_pos
			shake_max_strength = 0.0 # Reset max strength
		else:
			# --- Still shaking ---
			# Calculate current strength with a nice falloff (ease-out)
			# This is the "damping"
			var decay_ratio = shake_timer / shake_max_duration
			var current_strength = shake_max_strength * (decay_ratio * decay_ratio)

			# Generate random offset and apply it
			var offset = Vector3( \
				randf_range(-1.0, 1.0), \
				randf_range(-1.0, 1.0), \
				randf_range(-1.0, 1.0) \
				).normalized() * current_strength
				
			camera_node.position = original_cam_pos + offset
	elif camera_node.position != original_cam_pos:
		# Ensure it's reset if timer is 0
		camera_node.position = original_cam_pos
		
func small_camera_shake():
	# Feel free to tweak these values!
	start_camera_shake(0.01, 0.4) # Low strength, short duration


# --- MODIFIED: Preset for a successful "hit" ---
func big_camera_shake():
	# --- ...to here! ---
	# This function now handles BOTH the frame freeze and the shake.
	Global.frame_freeze(0.1, 0.2) 
	
	# Feel free to tweak these values!
	start_camera_shake(0.1, 0.1) # Higher strength, longer duration

func hit_or_miss_camera_shake():#this function is being called via the animation player
	if is_attack_connected:#this value is being set by the sword scene inm the hand, when the swords detects enemy it changes this value to true
		big_camera_shake()
		print("attack_connected")
	else:
		print("attack_not_connected")
		small_camera_shake()

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
@export var dash_cooldown:float= 0.5   #seconds
const JUMP_VELOCITY: float = 4.5
var GRAVITY: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# --- NODES ---
@onready var gpu_trail_3d: GPUTrail3D = $visuals/Skeleton3D/GPUTrail3D
@onready var visuals: Node3D = $visuals
@onready var camera_mount: Node3D = $"Camera Mount"
@onready var animation_player: AnimationPlayer = $visuals/AnimationPlayer

# --- STATES ---
enum STATE { IDLE, WALK, RUN, DASH_CHARGE, DASH, ATTACK, HURT, DEATH }
var state: STATE = STATE.IDLE

# --- DASH ---
var dash_charge_time: float = 0.0
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO
var is_charging: bool = false
var last_dash_time:float= 0.0

# --- TARGETING ---
var is_targeting: bool = false

# --------------------------------------------------

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hide_trails()

# --------------------------------------------------
# -------------------- INPUT -----------------------
# --------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		handle_mouse_motion(event)
	elif event.is_action_pressed("Target"):
		toggle_targeting()

# Mouse handling
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
		
		# <-- REMOVE THIS LINE -->
		# visuals.rotate_y(dx * mouse_sensitivity_x) # This conflicts with handle_movement
		
		camera_mount.rotate_x(-dy * mouse_sensitivity_y)

		var x = clamp(camera_mount.rotation_degrees.x, -10, 20)
		camera_mount.rotation_degrees = Vector3(x, 0, 0)
# Toggle lock-on targeting
# Toggle lock-on targeting
func toggle_targeting() -> void:
	is_targeting = !is_targeting
	
	# Get the camera's current rotation in RADIANS (for math)
	var cam_rot_rad = camera_mount.rotation
	
	if is_targeting:
		# --- JUST ENABLED TARGETING ---
		# We are switching TO targeting.
		# We should reset the camera mount's horizontal rotation, but keep the vertical.
		camera_mount.rotation = Vector3(cam_rot_rad.x, 0, 0)
	else:
		# --- JUST DISABLED TARGETING ---
		# This is where we fix the snap.
		
		# 1. Apply the camera's horizontal "nudge" (cam_rot_rad.y)
		#    to the ENTIRE player body.
		rotate_y(cam_rot_rad.y)
		
		# 2. Now that the body is rotated, reset the camera mount's
		#    local rotation, keeping the vertical (x) component.
		camera_mount.rotation = Vector3(cam_rot_rad.x, 0, 0)
		
		# 3. Reset the visuals to align with the newly rotated body.
		visuals.transform.basis = Basis()

func _physics_process(delta: float) -> void:
	handle_gravity_and_jump()
	handle_dash(delta)
	handle_targeting_rotation(delta)
	handle_movement(delta)
	handle_animations()

# --------------------------------------------------
# ---------------- CORE LOGIC ----------------------
# --------------------------------------------------

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

	# This line is correct and rotates the root body
	transform.basis = transform.basis.slerp(target_basis, delta * targeting_speed)
	
	# <-- REMOVE THIS LINE -->
	# We no longer want this function to control the visuals.
	# visuals.transform.basis = visuals.transform.basis.slerp(Basis(), delta * targeting_speed)
# --- MOVEMENT ---
# --- MOVEMENT ---
func handle_movement(delta: float) -> void:
	if state == STATE.DASH:
		if velocity.length_squared() > 0:
			visuals.look_at(position + velocity.normalized())
		return
	
	var input_dir = Input.get_vector("Left", "Right", "Fwd", "Bkwd")
	# This correctly gets the world-space direction based on the root node's rotation
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var moving = direction != Vector3.ZERO
	var running = Input.is_action_pressed("Sprint")

	if can_move():
		state = (
			STATE.RUN if moving and running else
			STATE.WALK if moving else
			STATE.IDLE
		)

	if moving and can_move():
		# <-- MODIFIED SECTION START -->
		# We removed the 'if not is_targeting:' check.
		# Now, the visuals will ALWAYS look in the direction of movement.
		visuals.look_at(position + direction)
		# <-- MODIFIED SECTION END -->
		
		var speed = RUN_SPEED if running else SPEED
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Not moving
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
		
		# <-- ADDED SECTION -->
		# If we are targeting BUT NOT moving, slerp the visuals
		# back to face the target (i.e., align with the root node).
		if is_targeting:
			visuals.transform.basis = visuals.transform.basis.slerp(Basis(), delta * targeting_speed)
		# <-- ADDED SECTION END -->

	move_and_slide()
# --------------------------------------------------
# ----------------- HELPERS ------------------------
# --------------------------------------------------



func can_move() -> bool:
	return not (state in [STATE.HURT, STATE.DEATH, STATE.DASH_CHARGE])

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
		# --- THIS IS THE FIX ---
		# Dash in the direction the VISUALS are facing,
		# not the root physics body.
		dash_direction = -visuals.global_transform.basis.z.normalized()
		# -----------------------

	velocity = dash_direction * dash_speed
	dash_timer = DASH_DURATION
	handle_animations()

# --------------------------------------------------
# ---------------- ANIMATIONS ----------------------
# --------------------------------------------------

func handle_animations() -> void:
	match state:
		STATE.IDLE:        set_anim("mixamo_com")
		STATE.WALK:        set_anim("walk")
		STATE.RUN:         set_anim("run")
		STATE.HURT:        set_anim("hurt")
		STATE.DEATH:       set_anim("death")
		STATE.DASH_CHARGE: set_anim("dash_charge")
		STATE.DASH:
			set_anim("dash_mid_end")
			show_trails()
			return
	hide_trails()

func set_anim(anim: String) -> void:
	if animation_player.current_animation != anim:
		animation_player.play(anim)

# --------------------------------------------------
# ---------------- TRAILS --------------------------
# --------------------------------------------------

func show_trails() -> void:
	if gpu_trail_3d:
		gpu_trail_3d.visible = true
		gpu_trail_3d.emitting = true

func hide_trails() -> void:
	if gpu_trail_3d:
		gpu_trail_3d.emitting = false
		gpu_trail_3d.visible = false

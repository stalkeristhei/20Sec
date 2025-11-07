# This script controls the main (green) health bar.
# It assumes it has three children:
# 1. A Timer node named "Timer"
# 2. A ProgressBar node named "DamageBar" (the red bar)
# 3. It is a direct child of the Boss node.

extends ProgressBar

@onready var timer = $Timer
@onready var damagebar = $DamageBar
@onready var boss = get_parent()

# Store the tween so we can reuse it
var damage_tween: Tween


func _ready() -> void:
	# Make sure the health bar is set up when the boss spawns
	init_health(boss.health)


func _process(_delta: float) -> void:
	# Constantly update the bar's value to match the boss's health
	_set_health(boss.health)


# Sets the health of the green bar and decides what to do
# with the red (damage) bar.
func _set_health(new_health: float) -> void:
	var prev_health = value
	value = clamp(new_health, 0, max_value)

	if value <= 0:
		queue_free()  # Optional: Hides the bar when the boss is dead
	
	if value < prev_health:
		# --- FIX (Part 1) ---
		# Damage was taken. Start the timer for the damage bar to catch up.
		# We NO LONGER update the damage bar here.
		timer.start()
		
	elif value > prev_health:
		# --- FIX (Part 2) ---
		# We are healing.
		# Snap the damage bar UP immediately to match the new health.
		damagebar.value = value


# Initialize all values at the start.
func init_health(_health: float) -> void:
	max_value = _health
	value = _health
	damagebar.max_value = _health
	damagebar.value = _health


# This function runs when the Timer finishes.
func _on_timer_timeout() -> void:
	# --- ENHANCEMENT ---
	# Instead of snapping, create a smooth animation.
	
	# If a tween is already running, kill it.
	if damage_tween:
		damage_tween.kill()

	# Create a new tween to animate the damage bar
	damage_tween = get_tree().create_tween()
	
	# Animate the 'damagebar's 'value' property TO the current 'value' (green bar)
	# over 0.4 seconds, using a smooth curve (ease-out).
	damage_tween.tween_property(damagebar, "value", value, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

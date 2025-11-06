
extends CharacterBody3D

var player = null
var nav_agent = null
const SPEED = 4.0

@export var player_path: NodePath

func _ready():
	# Get player node
	player =get_node(player_path)
	nav_agent = $NavigationAgent3D

func _process(delta):
	# Ensure nav_agent and player are valid
	if nav_agent and player:
		# Set target position for the navigation agent
		nav_agent.set_target_position(player.global_transform.origin)
		
		# Get the next navigation point
		var next_nav_point = nav_agent.get_next_path_position()
		# Calculate velocity
		var direction = (next_nav_point - global_transform.origin).normalized()
		velocity = direction * SPEED
		# Move the character
		move_and_slide()

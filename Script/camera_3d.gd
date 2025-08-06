# TopDownCamera.gd
extends Camera3D

# Camera settings
@export var camera_height: float = 15.0
@export var camera_angle: float = -45.0  # Degrees from horizontal
@export var camera_distance: float = 10.0

# Panning settings
@export var pan_speed: float = 10.0
@export var pan_smoothing: float = 5.0

# Movement boundaries (optional)
@export var boundary_enabled: bool = true
@export var boundary_min: Vector2 = Vector2(-20, -20)
@export var boundary_max: Vector2 = Vector2(20, 20)

# Internal variables
var is_panning: bool = false
var last_mouse_position: Vector2
var target_position: Vector3

func _ready():
	
	# Setup initial camera position and rotation
	setup_camera_angle()
	
	# Set target position to current position
	target_position = global_position

func setup_camera_angle():
	# Position camera at angle like Clash of Clans
	var angle_rad = deg_to_rad(camera_angle)
	
	# Calculate camera position based on angle and distance
	var camera_pos = Vector3(
		0,
		camera_height,
		camera_distance
	)
	
	# Set camera position
	global_position = camera_pos
	
	# Make camera look down at an angle
	rotation_degrees = Vector3(camera_angle, 0, 0)
	
	

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				start_panning(event.position)
			else:
				stop_panning()
	
	elif event is InputEventMouseMotion and is_panning:
		handle_panning(event.position)

func start_panning(mouse_pos: Vector2):
	is_panning = true
	last_mouse_position = mouse_pos
	Input.set_default_cursor_shape(Input.CURSOR_MOVE)

func stop_panning():
	is_panning = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func handle_panning(mouse_pos: Vector2):
	# Calculate mouse delta
	var delta = last_mouse_position - mouse_pos
	last_mouse_position = mouse_pos
	
	# Convert screen movement to world movement
	var movement = screen_to_world_movement(delta)
	
	# Update target position
	target_position += movement
	
	# Apply boundaries if enabled
	if boundary_enabled:
		target_position.x = clamp(target_position.x, boundary_min.x, boundary_max.x)
		target_position.z = clamp(target_position.z, boundary_min.y, boundary_max.y)
	

func screen_to_world_movement(screen_delta: Vector2) -> Vector3:
	# Simple conversion for top-down camera
	var move_speed = pan_speed * 0.01
	
	# Convert screen space to world space
	# X screen = X world, Y screen = Z world (since we're looking down)
	var movement = Vector3(
		screen_delta.x * move_speed,
		0,
		screen_delta.y * move_speed
	)
	
	return movement

func _process(delta):
	# Smooth camera movement 
	if target_position != global_position:
		global_position = global_position.lerp(target_position, pan_smoothing * delta)

# Helper function to set camera focus on specific position
func focus_on_position(pos: Vector3):
	target_position = Vector3(pos.x, camera_height, pos.z + camera_distance)

# Helper function to get world position under mouse cursor
func get_mouse_world_position() -> Vector3:
	var mouse_pos = get_viewport().get_mouse_position()
	var from = project_ray_origin(mouse_pos)
	var to = from + project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2  # Ground layer
	var result = space_state.intersect_ray(query)
	
	if result:
		return result.position
	return Vector3.ZERO

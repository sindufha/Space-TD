extends Camera2D

# Top-Down Camera Controller
# Allows WASD/Arrow key movement with customizable speed and boundaries

@export_group("Movement Settings")
@export var move_speed: float = 200.0
@export var smooth_movement: bool = true
@export var smooth_factor: float = 5.0

@export_group("Boundary Settings")
@export var enable_boundaries: bool = true
@export var boundary_left: float = -500.0
@export var boundary_right: float = 500.0
@export var boundary_top: float = -300.0
@export var boundary_bottom: float = 300.0

@export_group("Zoom Settings")
@export var enable_zoom: bool = true
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

@export_group("Input Settings")
@export var use_wasd: bool = true
@export var use_arrow_keys: bool = true
@export var use_mouse_drag: bool = false
@export var mouse_drag_button: MouseButton = MOUSE_BUTTON_MIDDLE

# Internal variables
var target_position: Vector2
var is_dragging: bool = false
var drag_start_pos: Vector2
var drag_start_camera_pos: Vector2

func _ready():
	# Set initial target position to current camera position
	target_position = global_position
	
	# Make sure camera is enabled
	enabled = true
	
	# Connect mouse signals if mouse drag is enabled
	if use_mouse_drag:
		pass
		# These will be handled in _input instead for better control

func _input(event):
	# Handle mouse drag
	if use_mouse_drag:
		handle_mouse_drag(event)
	
	# Handle zoom
	if enable_zoom:
		handle_zoom(event)

func handle_mouse_drag(event):
	if event is InputEventMouseButton:
		if event.button_index == mouse_drag_button:
			if event.pressed:
				# Start dragging
				is_dragging = true
				drag_start_pos = event.global_position
				drag_start_camera_pos = global_position
			else:
				# Stop dragging
				is_dragging = false
	
	elif event is InputEventMouseMotion and is_dragging:
		# Calculate drag offset
		var mouse_delta = event.global_position - drag_start_pos
		var new_pos = drag_start_camera_pos - mouse_delta / zoom
		
		# Apply boundaries
		if enable_boundaries:
			new_pos = apply_boundaries(new_pos)
		
		# Update target position
		target_position = new_pos

func handle_zoom(event):
	if event is InputEventMouseButton:
		var zoom_change = 0.0
		
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_change = zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_change = -zoom_speed
		
		if zoom_change != 0.0:
			var new_zoom = zoom + Vector2(zoom_change, zoom_change)
			new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
			new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
			zoom = new_zoom

func _process(delta):
	# Handle keyboard movement
	handle_keyboard_input(delta)
	
	# Apply smooth movement or instant movement
	if smooth_movement:
		global_position = global_position.lerp(target_position, smooth_factor * delta)
	else:
		global_position = target_position

func handle_keyboard_input(delta):
	# Skip if currently dragging with mouse
	if is_dragging:
		return
	
	var input_vector = Vector2.ZERO
	
	# WASD Controls
	if use_wasd:
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			input_vector.x -= 1
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			input_vector.x += 1
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			input_vector.y -= 1
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			input_vector.y += 1
	
	# Arrow Keys (if WASD is disabled or as additional input)
	if use_arrow_keys and not use_wasd:
		if Input.is_action_pressed("ui_left"):
			input_vector.x -= 1
		if Input.is_action_pressed("ui_right"):
			input_vector.x += 1
		if Input.is_action_pressed("ui_up"):
			input_vector.y -= 1
		if Input.is_action_pressed("ui_down"):
			input_vector.y += 1
	
	# Normalize diagonal movement
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()
		
		# Calculate movement considering zoom level
		var movement = input_vector * move_speed * delta / zoom.x
		target_position += movement
		
		# Apply boundaries
		if enable_boundaries:
			target_position = apply_boundaries(target_position)

func apply_boundaries(pos: Vector2) -> Vector2:
	var bounded_pos = pos
	bounded_pos.x = clamp(bounded_pos.x, boundary_left, boundary_right)
	bounded_pos.y = clamp(bounded_pos.y, boundary_top, boundary_bottom)
	return bounded_pos

# Utility functions for external use

func set_camera_position(new_pos: Vector2, instant: bool = false):
	"""Set camera to specific position"""
	target_position = new_pos
	if enable_boundaries:
		target_position = apply_boundaries(target_position)
	
	if instant:
		global_position = target_position

func get_camera_bounds() -> Rect2:
	"""Get current camera viewport bounds in world coordinates"""
	var viewport_size = get_viewport().get_visible_rect().size
	var world_size = viewport_size / zoom
	var top_left = global_position - world_size / 2
	return Rect2(top_left, world_size)

func set_boundaries(left: float, right: float, top: float, bottom: float):
	"""Set camera movement boundaries"""
	boundary_left = left
	boundary_right = right
	boundary_top = top
	boundary_bottom = bottom
	
	# Apply boundaries to current position
	if enable_boundaries:
		target_position = apply_boundaries(target_position)

func focus_on_point(point: Vector2, duration: float = 1.0):
	"""Smoothly focus camera on a specific point"""
	var tween = create_tween()
	tween.tween_method(set_camera_position.bind(true), global_position, point, duration)

func shake_camera(intensity: float, duration: float):
	"""Create camera shake effect"""
	var original_pos = global_position
	var tween = create_tween()
	
	# Create shake effect
	for i in range(int(duration * 30)):  # 30 shakes per second
		var shake_offset = Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		tween.tween_callback(func(): global_position = original_pos + shake_offset)
		tween.tween_delay(1.0 / 30.0)
	
	# Return to original position
	tween.tween_callback(func(): global_position = original_pos)

func set_zoom_level(new_zoom: float, instant: bool = false):
	"""Set camera zoom level"""
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)
	var target_zoom = Vector2(new_zoom, new_zoom)
	
	if instant:
		zoom = target_zoom
	else:
		var tween = create_tween()
		tween.tween_property(self, "zoom", target_zoom, 0.3)

# Debug functions
func _draw():
	if Engine.is_editor_hint() or OS.is_debug_build():
		draw_debug_info()

func draw_debug_info():
	if not enable_boundaries:
		return
	
	# Draw boundary rectangle
	var boundary_rect = Rect2(
		Vector2(boundary_left, boundary_top),
		Vector2(boundary_right - boundary_left, boundary_bottom - boundary_top)
	)
	
	# Convert to screen coordinates
	var top_left = to_local(boundary_rect.position)
	var bottom_right = to_local(boundary_rect.position + boundary_rect.size)
	var screen_rect = Rect2(top_left, bottom_right - top_left)
	
	# Draw boundary lines (this won't work in Camera2D, but kept for reference)
	# In practice, you'd want to draw this on a CanvasLayer or debug overlay

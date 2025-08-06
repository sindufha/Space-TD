extends Node2D

# Galaxy Portal Animation 64x64
# Smooth rotating portal with navy blue galaxy theme

@export var portal_size: float = 64.0
@export var rotation_speed: float = 1.0
@export var pulse_strength: float = 0.2
@export var particle_count: int = 30
@export var portal_position: Vector2 = Vector2(0, 0) : set = set_portal_position

var time: float = 0.0
var outer_ring: Node2D
var middle_ring: Node2D
var inner_core: Node2D
var particles: Array = []

# Galaxy colors (Navy blue theme)
var colors = {
	"dark_navy": Color(0.1, 0.15, 0.3, 1.0),
	"medium_navy": Color(0.2, 0.3, 0.6, 1.0),
	"bright_blue": Color(0.3, 0.5, 0.9, 1.0),
	"cyan_glow": Color(0.4, 0.8, 1.0, 1.0),
	"white_core": Color(0.9, 0.95, 1.0, 1.0)
}

func _ready():
	setup_portal()
	setup_particles()
	# Set initial position
	update_portal_position()

func set_portal_position(new_position: Vector2):
	portal_position = new_position
	if is_inside_tree():
		update_portal_position()

func update_portal_position():
	position = portal_position

func setup_portal():
	# Create outer rotating ring
	outer_ring = Node2D.new()
	add_child(outer_ring)
	
	# Create middle rotating ring
	middle_ring = Node2D.new()
	add_child(middle_ring)
	
	# Create inner core
	inner_core = Node2D.new()
	add_child(inner_core)

func setup_particles():
	# Create floating particles around portal
	particles.clear()
	for i in range(particle_count):
		var particle = {
			"pos": Vector2(randf_range(-portal_size, portal_size), randf_range(-portal_size, portal_size)),
			"speed": randf_range(0.5, 2.0),
			"size": randf_range(1.0, 3.0),
			"alpha": randf_range(0.3, 0.8),
			"orbit_radius": randf_range(20, 35),
			"angle": randf() * TAU
		}
		particles.append(particle)

func _process(delta):
	time += delta
	animate_portal(delta)
	animate_particles(delta)
	queue_redraw()

func animate_portal(delta):
	# Rotate rings at different speeds
	if outer_ring:
		outer_ring.rotation += rotation_speed * delta * 0.5
	if middle_ring:
		middle_ring.rotation -= rotation_speed * delta * 0.8
	if inner_core:
		inner_core.rotation += rotation_speed * delta * 1.2

func animate_particles(delta):
	for particle in particles:
		# Orbit motion
		particle.angle += particle.speed * delta
		var orbit_offset = Vector2(
			cos(particle.angle) * particle.orbit_radius,
			sin(particle.angle) * particle.orbit_radius
		)
		particle.pos = orbit_offset
		
		# Pulsing alpha
		particle.alpha = 0.3 + 0.5 * (sin(time * 3.0 + particle.angle) + 1.0) / 2.0

func _draw():
	draw_portal()
	draw_particles()

func draw_portal():
	var center = Vector2.ZERO
	var pulse = 1.0 + pulse_strength * sin(time * 4.0)
	
	# Outer ring - Dark navy with spiral pattern
	draw_outer_ring(center, pulse)
	
	# Middle ring - Medium navy with rotating segments
	draw_middle_ring(center, pulse)
	
	# Inner core - Bright glowing center
	draw_inner_core(center, pulse)
	
	# Add glow effect
	draw_glow_effect(center, pulse)

func draw_outer_ring(center: Vector2, pulse: float):
	var radius = (portal_size * 0.4) * pulse
	var segments = 64
	
	for i in range(segments):
		var angle1 = (float(i) / segments) * TAU + outer_ring.rotation
		var angle2 = (float(i + 1) / segments) * TAU + outer_ring.rotation
		
		var point1 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var point2 = center + Vector2(cos(angle2), sin(angle2)) * radius
		
		# Create spiral effect
		var spiral_offset = sin(angle1 * 4.0 + time * 2.0) * 3.0
		var adjusted_radius = radius + spiral_offset
		point1 = center + Vector2(cos(angle1), sin(angle1)) * adjusted_radius
		
		# Gradient color based on position
		var color_intensity = (sin(angle1 * 3.0 + time) + 1.0) / 2.0
		var ring_color = colors.dark_navy.lerp(colors.medium_navy, color_intensity)
		
		draw_line(point1, point2, ring_color, 2.0)

func draw_middle_ring(center: Vector2, pulse: float):
	var radius = (portal_size * 0.25) * pulse
	var segments = 32
	
	for i in range(0, segments, 2):  # Skip every other segment for gaps
		var angle1 = (float(i) / segments) * TAU + middle_ring.rotation
		var angle2 = (float(i + 1) / segments) * TAU + middle_ring.rotation
		
		var inner_point1 = center + Vector2(cos(angle1), sin(angle1)) * (radius * 0.7)
		var outer_point1 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var inner_point2 = center + Vector2(cos(angle2), sin(angle2)) * (radius * 0.7)
		var outer_point2 = center + Vector2(cos(angle2), sin(angle2)) * radius
		
		# Create triangular segments
		var points = PackedVector2Array([inner_point1, outer_point1, outer_point2, inner_point2])
		var segment_color = colors.medium_navy.lerp(colors.bright_blue, 0.6)
		draw_colored_polygon(points, segment_color)

func draw_inner_core(center: Vector2, pulse: float):
	var core_radius = (portal_size * 0.12) * pulse
	var core_glow_radius = (portal_size * 0.18) * pulse
	
	# Outer glow
	for i in range(10):
		var alpha = 0.1 - (i * 0.01)
		var glow_color = colors.cyan_glow
		glow_color.a = alpha
		draw_circle(center, core_glow_radius + i * 2, glow_color)
	
	# Main core
	draw_circle(center, core_radius, colors.bright_blue)
	
	# Inner bright spot
	var inner_pulse = 1.0 + pulse_strength * 0.5 * sin(time * 6.0)
	draw_circle(center, core_radius * 0.6 * inner_pulse, colors.white_core)

func draw_glow_effect(center: Vector2, pulse: float):
	# Outer glow rings
	for i in range(3):
		var glow_radius = (portal_size * 0.5 + i * 8) * pulse
		var glow_alpha = 0.05 - (i * 0.015)
		var glow_color = colors.cyan_glow
		glow_color.a = glow_alpha
		draw_arc(center, glow_radius, 0, TAU, 64, glow_color, 3.0)

func draw_particles():
	for particle in particles:
		var particle_color = colors.cyan_glow
		particle_color.a = particle.alpha
		draw_circle(particle.pos, particle.size, particle_color)

# Utility functions for external use
func set_portal_color_theme(theme_name: String):
	match theme_name:
		"galaxy":
			colors = {
				"dark_navy": Color(0.1, 0.15, 0.3, 1.0),
				"medium_navy": Color(0.2, 0.3, 0.6, 1.0),
				"bright_blue": Color(0.3, 0.5, 0.9, 1.0),
				"cyan_glow": Color(0.4, 0.8, 1.0, 1.0),
				"white_core": Color(0.9, 0.95, 1.0, 1.0)
			}
		"purple":
			colors = {
				"dark_navy": Color(0.2, 0.1, 0.3, 1.0),
				"medium_navy": Color(0.4, 0.2, 0.6, 1.0),
				"bright_blue": Color(0.6, 0.3, 0.9, 1.0),
				"cyan_glow": Color(0.8, 0.4, 1.0, 1.0),
				"white_core": Color(0.95, 0.9, 1.0, 1.0)
			}
		"green":
			colors = {
				"dark_navy": Color(0.1, 0.3, 0.2, 1.0),
				"medium_navy": Color(0.2, 0.6, 0.3, 1.0),
				"bright_blue": Color(0.3, 0.9, 0.4, 1.0),
				"cyan_glow": Color(0.4, 1.0, 0.6, 1.0),
				"white_core": Color(0.9, 1.0, 0.95, 1.0)
			}

func set_animation_speed(speed: float):
	rotation_speed = speed

func set_portal_scale(scale_factor: float):
	portal_size = 64.0 * scale_factor
	setup_particles()  # Regenerate particles with new scale

# Helper function to get current portal bounds (useful for collision detection)
func get_portal_bounds() -> Rect2:
	var half_size = portal_size * 0.5
	return Rect2(portal_position - Vector2(half_size, half_size), Vector2(portal_size, portal_size))

# Function to check if a point is inside the portal
func is_point_inside_portal(point: Vector2) -> bool:
	var distance = point.distance_to(portal_position)
	return distance <= (portal_size * 0.4)  # Use outer ring radius

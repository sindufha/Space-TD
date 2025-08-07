extends StaticBody2D
class_name LaserTower

@export var damage:int = 2
@export var fire_rate = 10
@export var range_radius:int = 100
@export var rotation_speed = 180.0
@export var projectile_speed = 600.0
@export var shoot_sounds: Array[AudioStream] = []

var enemies_in_range = []
var current_target: Enemy = null
var can_shoot = true
var shoot_timer: Timer
var grid_position: Vector2i
var target_rotation = 0.0
var is_rotating = false
var shoot_player: AudioStreamPlayer2D
var owned_particles: Array[Node] = []
var owned_tweens: Array[Tween] = []
var is_being_destroyed = false
var active_laser: Line2D = null
var laser_glow: Line2D = null
var muzzle_flash: Node2D = null
var laser_active = false

func _ready():
	setup_tower()
	setup_audio()

func setup_audio():
	shoot_player = AudioStreamPlayer2D.new()
	add_child(shoot_player)
	shoot_player.volume_db = -5
	shoot_player.max_distance = 10000000

func setup_tower():
	shoot_timer = Timer.new()
	add_child(shoot_timer)
	shoot_timer.wait_time = 1.0 / fire_rate
	shoot_timer.timeout.connect(reset_shooting)
	
	$Range.body_entered.connect(_on_enemy_entered)
	$Range.body_exited.connect(_on_enemy_exited)
	
	var range_shape = $Range/CollisionShape2D.shape as CircleShape2D
	if range_shape:
		range_shape.radius = range_radius

func cleanup_effects():
	is_being_destroyed = true
	
	var particles_to_remove = owned_particles.duplicate()
	for particle in particles_to_remove:
		if is_instance_valid(particle):
			if particle.get_parent():
				particle.get_parent().remove_child(particle)
			particle.queue_free()
	owned_particles.clear()
	
	var tweens_to_kill = owned_tweens.duplicate()
	for tween in tweens_to_kill:
		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()
	owned_tweens.clear()
	
	if is_instance_valid(shoot_player):
		shoot_player.stop()
	
	if is_instance_valid(shoot_timer):
		shoot_timer.stop()
	
	enemies_in_range.clear()
	current_target = null
	laser_active = false

func _process(delta):
	if is_being_destroyed:
		return
	
	update_target()
	update_rotation(delta)
	
	if current_target and is_target_in_sight():
		if not laser_active:
			start_continuous_laser()
		update_laser_beam()
		if can_shoot:
			deal_damage()
	else:
		stop_laser()

func update_target():
	if not is_instance_valid(current_target) or not enemies_in_range.has(current_target):
		current_target = null
		find_new_target()

func find_new_target():
	if enemies_in_range.is_empty():
		return
	
	var best_target = null
	var best_progress = -1.0
	
	for enemy in enemies_in_range:
		if is_instance_valid(enemy) and enemy.path_follow:
			var progress = enemy.path_follow.progress_ratio
			if progress > best_progress:
				best_progress = progress
				best_target = enemy
	
	if best_target:
		set_target(best_target)

func set_target(new_target: Enemy):
	current_target = new_target
	if current_target:
		var direction = current_target.global_position - global_position
		target_rotation = direction.angle()
		is_rotating = true

func update_rotation(delta):
	if not current_target or is_being_destroyed:
		return
	
	var direction = current_target.global_position - global_position
	target_rotation = direction.angle()
	
	var rotation_diff = angle_difference(target_rotation, rotation)
	
	if abs(rotation_diff) > 0.05:
		var rotation_step = rotation_speed * deg_to_rad(1) * delta
		rotation = rotate_toward(rotation, target_rotation, rotation_step)
		is_rotating = true
	else:
		is_rotating = false

func is_target_in_sight() -> bool:
	if not current_target:
		return false
	
	var direction = current_target.global_position - global_position
	var target_angle = direction.angle()
	var angle_diff = abs(angle_difference(rotation, target_angle))
	
	return angle_diff < deg_to_rad(15)

func start_continuous_laser():
	if is_being_destroyed or laser_active:
		return
	
	laser_active = true
	create_continuous_laser()
	play_shoot_sound()

func stop_laser():
	if not laser_active:
		return
	
	laser_active = false
	if is_instance_valid(active_laser):
		owned_particles.erase(active_laser)
		active_laser.queue_free()
		active_laser = null
	
	if is_instance_valid(laser_glow):
		owned_particles.erase(laser_glow)
		laser_glow.queue_free()
		laser_glow = null
	
	if is_instance_valid(muzzle_flash):
		owned_particles.erase(muzzle_flash)
		muzzle_flash.queue_free()
		muzzle_flash = null

func create_continuous_laser():
	if is_being_destroyed or not current_target:
		return
	
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var start_pos = global_position + muzzle_offset
	var target_pos = current_target.global_position
	
	# Create main laser beam (core)
	active_laser = Line2D.new()
	get_tree().current_scene.add_child(active_laser)
	owned_particles.append(active_laser)
	
	active_laser.width = 3.0
	active_laser.default_color = Color(1.0, 0.3, 0.1, 0.9)
	active_laser.begin_cap_mode = Line2D.LINE_CAP_NONE
	active_laser.end_cap_mode = Line2D.LINE_CAP_NONE
	
	# Create laser glow effect (wider, softer)
	laser_glow = Line2D.new()
	get_tree().current_scene.add_child(laser_glow)
	owned_particles.append(laser_glow)
	
	laser_glow.width = 8.0
	laser_glow.default_color = Color(1.0, 0.6, 0.2, 0.3)
	laser_glow.begin_cap_mode = Line2D.LINE_CAP_NONE
	laser_glow.end_cap_mode = Line2D.LINE_CAP_NONE
	
	# Create muzzle flash effect
	create_muzzle_flash(start_pos)
	
	# Set initial points
	active_laser.add_point(start_pos)
	active_laser.add_point(target_pos)
	laser_glow.add_point(start_pos)
	laser_glow.add_point(target_pos)

func create_muzzle_flash(pos: Vector2):
	muzzle_flash = Node2D.new()
	get_tree().current_scene.add_child(muzzle_flash)
	owned_particles.append(muzzle_flash)
	muzzle_flash.global_position = pos
	
	# Bright core flash
	var core = create_polygon_circle(Vector2.ZERO, 4, Color(1.0, 0.8, 0.4, 0.8))
	muzzle_flash.add_child(core)
	
	# Outer glow
	var glow = create_polygon_circle(Vector2.ZERO, 8, Color(1.0, 0.4, 0.2, 0.4))
	muzzle_flash.add_child(glow)
	muzzle_flash.move_child(glow, 0)
	
	# Pulsing animation
	var tween = create_tween()
	owned_tweens.append(tween)
	tween.set_loops()
	tween.set_parallel(true)
	tween.tween_property(core, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(core, "scale", Vector2(0.8, 0.8), 0.1).set_delay(0.1)
	tween.tween_property(glow, "modulate:a", 0.6, 0.15)
	tween.tween_property(glow, "modulate:a", 0.2, 0.15).set_delay(0.15)

func create_polygon_circle(pos: Vector2, radius: float, color: Color) -> Polygon2D:
	var circle = Polygon2D.new()
	circle.position = pos
	circle.color = color
	
	var vertices = PackedVector2Array()
	var segments = 12
	for i in range(segments):
		var angle = 2.0 * PI * i / segments
		vertices.append(Vector2(cos(angle), sin(angle)) * radius)
	
	circle.polygon = vertices
	return circle

func update_laser_beam():
	if not is_instance_valid(active_laser) or not current_target or is_being_destroyed:
		return
	
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var start_pos = global_position + muzzle_offset
	var target_pos = current_target.global_position
	
	# Update main laser
	active_laser.clear_points()
	active_laser.add_point(start_pos)
	active_laser.add_point(target_pos)
	
	# Update glow
	if is_instance_valid(laser_glow):
		laser_glow.clear_points()
		laser_glow.add_point(start_pos)
		laser_glow.add_point(target_pos)
	
	# Update muzzle flash position
	if is_instance_valid(muzzle_flash):
		muzzle_flash.global_position = start_pos
		muzzle_flash.rotation = rotation
	
	# Add subtle laser flicker effect
	if randf() < 0.1:
		active_laser.default_color.a = randf_range(0.7, 1.0)
		if is_instance_valid(laser_glow):
			laser_glow.default_color.a = randf_range(0.2, 0.4)

func deal_damage():
	if is_being_destroyed:
		return
	
	if current_target and is_instance_valid(current_target):
		current_target.take_damage(damage)
		can_shoot = false
		shoot_timer.start()

func play_shoot_sound():
	if is_instance_valid(shoot_player) and shoot_sounds.size() > 0 and not is_being_destroyed:
		var random_sound = shoot_sounds[randi() % shoot_sounds.size()]
		shoot_player.stream = random_sound
		shoot_player.play()

func reset_shooting():
	if not is_being_destroyed:
		can_shoot = true

func _on_enemy_entered(body):
	if body is Enemy and not is_being_destroyed:
		enemies_in_range.append(body)
		if not current_target:
			set_target(body)

func _on_enemy_exited(body):
	if body is Enemy and not is_being_destroyed:
		enemies_in_range.erase(body)
		if current_target == body:
			stop_laser()
			current_target = null
			find_new_target()

func set_grid_position(grid_pos: Vector2i):
	grid_position = grid_pos
	global_position = GridManager.grid_to_world(grid_pos)

func _exit_tree():
	cleanup_effects()

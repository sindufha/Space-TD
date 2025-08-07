extends StaticBody2D
class_name Tower3

@export var damage:int = 5
@export var fire_rate = 1
@export var range_radius:int = 100
@export var rotation_speed = 180.0  # Degrees per second
@export var projectile_speed = 600.0  # Kurangi dari 800 ke 600

# Audio untuk shoot
@export var shoot_sounds: Array[AudioStream] = []  # Drag audio files ke sini di Inspector

var enemies_in_range = []
var current_target: Enemy = null
var can_shoot = true
var shoot_timer: Timer
var grid_position: Vector2i
var target_rotation = 0.0
var is_rotating = false

# Audio player
var shoot_player: AudioStreamPlayer2D

# IMPROVED: Tracking system untuk partikel dari tower ini
var owned_particles: Array[Node] = []  # Array untuk track partikel milik tower ini
var owned_tweens: Array[Tween] = []    # Array untuk track tween milik tower ini
var is_being_destroyed = false         # Flag untuk mencegah operasi baru

func _ready():
	setup_tower()
	setup_audio()

func setup_audio():
	# Buat audio player untuk shoot sound
	shoot_player = AudioStreamPlayer2D.new()
	add_child(shoot_player)
	shoot_player.volume_db = -5 # Agak pelan
	shoot_player.max_distance = 10000000  # Jarak maksimal terdengar

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

# IMPROVED: Cleanup function yang lebih agresif
func cleanup_effects():
	is_being_destroyed = true
	
	# Hapus SEMUA partikel milik tower ini SEKARANG JUGA
	var particles_to_remove = owned_particles.duplicate()
	for particle in particles_to_remove:
		if is_instance_valid(particle):
			# Langsung hapus dari scene tree
			if particle.get_parent():
				particle.get_parent().remove_child(particle)
			particle.queue_free()
	owned_particles.clear()
	
	# Kill SEMUA tween milik tower ini
	var tweens_to_kill = owned_tweens.duplicate()
	for tween in tweens_to_kill:
		if is_instance_valid(tween) and tween.is_valid():
			tween.kill()
	owned_tweens.clear()
	
	# Stop audio
	if is_instance_valid(shoot_player):
		shoot_player.stop()
	
	# Stop timer
	if is_instance_valid(shoot_timer):
		shoot_timer.stop()
	
	# Clear semua references
	enemies_in_range.clear()
	current_target = null

func _process(delta):
	if is_being_destroyed:
		return
		
	update_target()
	update_rotation(delta)
	
	if can_shoot and current_target and is_target_in_sight():
		shoot()

func update_target():
	# Jika target hilang atau mati, cari target baru
	if not is_instance_valid(current_target) or not enemies_in_range.has(current_target):
		current_target = null
		find_new_target()

func find_new_target():
	if enemies_in_range.is_empty():
		return
	
	# Strategi targeting: pilih enemy terdekat ke ujung path
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
		# Hitung rotation ke target
		var direction = current_target.global_position - global_position
		target_rotation = direction.angle()
		is_rotating = true

func update_rotation(delta):
	if not current_target or is_being_destroyed:
		return
	
	# Update target rotation berdasarkan posisi enemy yang bergerak
	var direction = current_target.global_position - global_position
	target_rotation = direction.angle()
	
	# Smooth rotation
	var rotation_diff = angle_difference(target_rotation, rotation)
	
	if abs(rotation_diff) > 0.05:  # Masih perlu rotate
		var rotation_step = rotation_speed * deg_to_rad(1) * delta
		rotation = rotate_toward(rotation, target_rotation, rotation_step)
		is_rotating = true
	else:
		is_rotating = false

func is_target_in_sight() -> bool:
	if not current_target:
		return false
	
	# Cek apakah tower sudah menghadap target (dalam toleransi)
	var direction = current_target.global_position - global_position
	var target_angle = direction.angle()
	var angle_diff = abs(angle_difference(rotation, target_angle))
	
	return angle_diff < deg_to_rad(15)  # Toleransi 15 derajat

func shoot():
	if is_being_destroyed:
		return
		
	if current_target and is_instance_valid(current_target):
		create_laser_beam()
		create_laser_muzzle_flash()
		play_shoot_sound()
		can_shoot = false
		shoot_timer.start()

func play_shoot_sound():
	# Play random shoot sound jika ada
	if is_instance_valid(shoot_player) and shoot_sounds.size() > 0 and not is_being_destroyed:
		var random_sound = shoot_sounds[randi() % shoot_sounds.size()]
		shoot_player.stream = random_sound
		shoot_player.play()

func create_laser_beam():
	if is_being_destroyed:
		return
		
	# Hitung posisi dan arah tembakan
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var start_pos = global_position + muzzle_offset
	var target_pos = current_target.global_position
	var direction = (target_pos - start_pos).normalized()
	
	# Give damage immediately (like the simple version)
	if is_instance_valid(current_target) and not is_being_destroyed:
		current_target.take_damage(damage)
	
	# === MUZZLE FLASH EFFECT ===
	create_advanced_muzzle_blast(start_pos)
	create_advanced_muzzle_particles(start_pos, direction)
	
	# === BULLET TRAIL EFFECT ===
	create_advanced_bullet_trail(start_pos, target_pos)

func create_advanced_muzzle_blast(pos: Vector2):
	if is_being_destroyed:
		return
		
	# Flash utama - lingkaran besar yang mengembang
	var blast = create_circle_shape(Vector2.ZERO, 15, Color(1.0, 0.9, 0.3, 0.8))
	get_tree().current_scene.add_child(blast)
	blast.global_position = pos
	owned_particles.append(blast)
	
	var tween1 = create_tween()
	owned_tweens.append(tween1)
	tween1.set_parallel(true)
	
	# Expand dan fade
	tween1.tween_property(blast, "scale", Vector2(2.0, 2.0), 0.15)
	tween1.tween_property(blast, "modulate:a", 0.0, 0.15)
	tween1.tween_callback(func():
		if is_instance_valid(blast):
			owned_particles.erase(blast)
			blast.queue_free()
	).set_delay(0.15)
	
	# Flash kedua - lebih kecil, lebih terang
	var inner_flash = create_circle_shape(Vector2.ZERO, 8, Color(1.0, 1.0, 0.8, 1.0))
	get_tree().current_scene.add_child(inner_flash)
	inner_flash.global_position = pos
	owned_particles.append(inner_flash)
	
	var tween2 = create_tween()
	owned_tweens.append(tween2)
	tween2.set_parallel(true)
	tween2.tween_property(inner_flash, "scale", Vector2(2.2, 2.2), 0.08)
	tween2.tween_property(inner_flash, "modulate:a", 0.0, 0.08)
	tween2.tween_callback(func():
		if is_instance_valid(inner_flash):
			owned_particles.erase(inner_flash)
			inner_flash.queue_free()
	).set_delay(0.08)

func create_advanced_muzzle_particles(pos: Vector2, direction: Vector2):
	if is_being_destroyed:
		return
		
	# Buat beberapa partikel kecil yang tersebar
	for i in range(6):
		var angle_offset = randf_range(-45, 45)
		var particle_dir = direction.rotated(deg_to_rad(angle_offset))
		var distance = randf_range(20, 40)
		
		var particle = create_circle_shape(Vector2.ZERO, 1.5, Color(1.0, 0.7, 0.2, 0.9))
		get_tree().current_scene.add_child(particle)
		particle.global_position = pos
		owned_particles.append(particle)
		
		var end_pos = pos + particle_dir * distance
		var tween = create_tween()
		owned_tweens.append(tween)
		tween.set_parallel(true)
		tween.tween_property(particle, "global_position", end_pos, 0.12)
		tween.tween_property(particle, "modulate:a", 0.0, 0.12)
		tween.tween_property(particle, "scale", Vector2(0.3, 0.3), 0.12)
		tween.tween_callback(func():
			if is_instance_valid(particle):
				owned_particles.erase(particle)
				particle.queue_free()
		).set_delay(0.12)

func create_advanced_bullet_trail(start_pos: Vector2, end_pos: Vector2):
	if is_being_destroyed:
		return
		
	# Buat trail utama
	var trail = Line2D.new()
	get_tree().current_scene.add_child(trail)
	owned_particles.append(trail)
	
	# Setup trail properties
	trail.add_point(start_pos)
	trail.add_point(end_pos)
	trail.width = 4.0
	trail.default_color = Color(1.0, 0.8, 0.4, 0.9)
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Animasi trail - fade out dengan menyusut
	var tween = create_tween()
	owned_tweens.append(tween)
	tween.set_parallel(true)
	tween.tween_property(trail, "width", 0.0, 0.2)
	tween.tween_property(trail, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func():
		if is_instance_valid(trail):
			owned_particles.erase(trail)
			trail.queue_free()
	).set_delay(0.2)
	
	# Buat trail glow effect
	var glow_trail = Line2D.new()
	get_tree().current_scene.add_child(glow_trail)
	owned_particles.append(glow_trail)
	glow_trail.add_point(start_pos)
	glow_trail.add_point(end_pos)
	glow_trail.width = 8.0
	glow_trail.default_color = Color(1.0, 0.9, 0.5, 0.4)
	glow_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	var glow_tween = create_tween()
	owned_tweens.append(glow_tween)
	glow_tween.set_parallel(true)
	glow_tween.tween_property(glow_trail, "width", 0.0, 0.25)
	glow_tween.tween_property(glow_trail, "modulate:a", 0.0, 0.25)
	glow_tween.tween_callback(func():
		if is_instance_valid(glow_trail):
			owned_particles.erase(glow_trail)
			glow_trail.queue_free()
	).set_delay(0.25)
	
	# Impact effect di target
	create_advanced_impact_effect(end_pos)

func create_laser_line(start_pos: Vector2, end_pos: Vector2) -> Line2D:
	var laser = Line2D.new()
	
	# Setup laser properties
	laser.width = 8.0
	laser.default_color = Color(0.1, 0.9, 1.0, 0.0)  # Cyan terang, mulai transparan
	laser.begin_cap_mode = Line2D.LINE_CAP_ROUND
	laser.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Set points untuk laser beam
	var points = PackedVector2Array()
	points.append(start_pos)
	points.append(end_pos)
	laser.points = points
	
	return laser

func create_laser_particles(container: Node2D, start_pos: Vector2, end_pos: Vector2):
	if is_being_destroyed:
		return
	
	# Hitung direction dan distance
	var direction = (end_pos - start_pos)
	var distance = direction.length()
	var normalized_dir = direction.normalized()
	
	# Buat partikel sepanjang laser beam
	var particle_count = int(distance / 15.0) + 3  # Partikel setiap 15 pixel
	
	for i in range(particle_count):
		var t = float(i) / float(particle_count - 1)
		var particle_pos = start_pos.lerp(end_pos, t)
		
		# Buat laser particle
		var particle = create_laser_particle()
		container.add_child(particle)
		particle.global_position = particle_pos
		
		# Random offset sedikit untuk variasi
		var offset = Vector2(randf_range(-3, 3), randf_range(-3, 3))
		particle.position += offset
		
		# Animasi particle
		var particle_tween = create_tween()
		owned_tweens.append(particle_tween)
		
		particle_tween.set_parallel(true)
		# Particle muncul dengan delay berdasarkan posisi
		var delay = t * 0.03
		particle_tween.tween_property(particle, "modulate:a", 1.0, 0.05).set_delay(delay)
		particle_tween.tween_property(particle, "modulate:a", 0.0, 0.15).set_delay(delay + 0.05)
		particle_tween.tween_property(particle, "scale", Vector2(1.5, 1.5), 0.1).set_delay(delay)
		particle_tween.tween_property(particle, "scale", Vector2(0.3, 0.3), 0.1).set_delay(delay + 0.1)

func create_laser_particle() -> Node2D:
	var particle = Node2D.new()
	
	# Core particle - bright cyan
	var core = create_circle_shape(Vector2.ZERO, 2, Color(0.3, 1.0, 1.0, 0.0))
	particle.add_child(core)
	
	# Glow around particle
	var glow = create_circle_shape(Vector2.ZERO, 4, Color(0.1, 0.7, 1.0, 0.0))
	particle.add_child(glow)
	particle.move_child(glow, 0)  # Glow behind core
	
	return particle

func create_advanced_impact_effect(pos: Vector2):
	if is_being_destroyed:
		return
		
	# Ring impact effect
	var impact_ring = create_circle_shape(Vector2.ZERO, 5, Color(1.0, 0.5, 0.2, 0.8))
	get_tree().current_scene.add_child(impact_ring)
	impact_ring.global_position = pos
	owned_particles.append(impact_ring)
	
	var tween = create_tween()
	owned_tweens.append(tween)
	tween.set_parallel(true)
	tween.tween_property(impact_ring, "scale", Vector2(2.5, 2.5), 0.1)
	tween.tween_property(impact_ring, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func():
		if is_instance_valid(impact_ring):
			owned_particles.erase(impact_ring)
			impact_ring.queue_free()
	).set_delay(0.1)
	
	# Sparks dari impact
	for i in range(4):
		create_advanced_impact_spark(pos)

func create_advanced_impact_spark(pos: Vector2):
	if is_being_destroyed:
		return
		
	var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance = randf_range(15, 25)
	
	# Create spark as small rectangle
	var spark = create_spark_shape(Vector2.ZERO, Vector2(2, 6), Color(1.0, 0.6, 0.1, 1.0))
	get_tree().current_scene.add_child(spark)
	spark.global_position = pos
	spark.rotation = random_dir.angle()
	owned_particles.append(spark)
	
	var end_pos = pos + random_dir * distance
	var tween = create_tween()
	owned_tweens.append(tween)
	tween.set_parallel(true)
	tween.tween_property(spark, "global_position", end_pos, 0.15)
	tween.tween_property(spark, "modulate:a", 0.0, 0.15)
	tween.tween_property(spark, "scale", Vector2(0.5, 0.5), 0.15)
	tween.tween_callback(func():
		if is_instance_valid(spark):
			owned_particles.erase(spark)
			spark.queue_free()
	).set_delay(0.15)

func create_spark_shape(pos: Vector2, size: Vector2, color: Color) -> Node2D:
	# Create rectangular spark using Polygon2D
	var spark = Polygon2D.new()
	spark.position = pos
	spark.color = color
	
	# Create rectangle vertices
	var vertices = PackedVector2Array()
	var half_width = size.x / 2
	var half_height = size.y / 2
	
	vertices.append(Vector2(-half_width, -half_height))
	vertices.append(Vector2(half_width, -half_height))
	vertices.append(Vector2(half_width, half_height))
	vertices.append(Vector2(-half_width, half_height))
	
	spark.polygon = vertices
	return spark

func create_laser_spark() -> Node2D:
	var spark = Node2D.new()
	
	# Small bright core
	var core = create_circle_shape(Vector2.ZERO, 1.5, Color(0.9, 1.0, 1.0, 1.0))
	spark.add_child(core)
	
	# Trail effect
	var trail = Line2D.new()
	trail.width = 2.0
	trail.default_color = Color(0.3, 0.9, 1.0, 0.8)
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	spark.add_child(trail)
	
	var points = PackedVector2Array()
	points.append(Vector2.ZERO)
	points.append(Vector2.ZERO)
	trail.points = points
	
	return spark

func create_electric_ring() -> Node2D:
	var ring = Node2D.new()
	
	var line = Line2D.new()
	ring.add_child(line)
	line.width = 2.5
	line.default_color = Color(0.2, 0.8, 1.0, 0.9)
	line.closed = true
	
	# Create electric-looking ring dengan sedikit zigzag
	var points = PackedVector2Array()
	var segments = 16
	var base_radius = 6
	
	for i in range(segments):
		var angle = 2.0 * PI * i / segments
		var radius_variation = randf_range(0.8, 1.2)  # Variasi radius untuk efek electric
		var radius = base_radius * radius_variation
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	
	line.points = points
	
	return ring

func create_laser_muzzle_flash():
	if is_being_destroyed:
		return
		
	# Simple bright muzzle flash
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var muzzle_pos = global_position + muzzle_offset
	
	var flash = create_circle_shape(Vector2.ZERO, 6, Color(1.0, 1.0, 0.8, 1.0))
	get_tree().current_scene.add_child(flash)
	flash.global_position = muzzle_pos
	owned_particles.append(flash)
	
	var flash_tween = create_tween()
	owned_tweens.append(flash_tween)
	
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.08)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.08)
	flash_tween.tween_callback(func():
		if is_instance_valid(flash):
			owned_particles.erase(flash)
			flash.queue_free()
	).set_delay(0.08)

func create_circle_shape(pos: Vector2, radius: float, color: Color) -> Node2D:
	# Buat shape circle menggunakan Polygon2D
	var circle = Polygon2D.new()
	circle.position = pos
	circle.color = color
	
	# Buat vertices untuk circle yang smooth
	var vertices = PackedVector2Array()
	var segments = 16
	for i in range(segments):
		var angle = 2.0 * PI * i / segments
		vertices.append(Vector2(cos(angle), sin(angle)) * radius)
	
	circle.polygon = vertices
	return circle

func reset_shooting():
	if not is_being_destroyed:
		can_shoot = true

func _on_enemy_entered(body):
	if body is Enemy and not is_being_destroyed:
		enemies_in_range.append(body)
		# Jika belum ada target, set sebagai target
		if not current_target:
			set_target(body)

func _on_enemy_exited(body):
	if body is Enemy and not is_being_destroyed:
		enemies_in_range.erase(body)
		# Jika target keluar range, cari target baru
		if current_target == body:
			current_target = null
			find_new_target()

func set_grid_position(grid_pos: Vector2i):
	grid_position = grid_pos
	global_position = GridManager.grid_to_world(grid_pos)

# Override _exit_tree untuk cleanup otomatis
func _exit_tree():
	cleanup_effects()

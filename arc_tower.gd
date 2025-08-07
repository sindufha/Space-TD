extends StaticBody2D
class_name Towerarc

@export var damage:int = 5
@export var fire_rate = 1
@export var range_radius:int = 100
@export var rotation_speed = 180.0  # Degrees per second
@export var projectile_speed = 600.0  # Kurangi dari 800 ke 600
@export var chain_range = 80.0  # Jarak maksimal untuk chain lightning
@export var max_chains = 3  # Maksimal berapa kali bisa chain

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
		create_arc_lightning()
		create_muzzle_flash()
		play_shoot_sound()
		can_shoot = false
		shoot_timer.start()

func play_shoot_sound():
	# Play random shoot sound jika ada
	if is_instance_valid(shoot_player) and shoot_sounds.size() > 0 and not is_being_destroyed:
		var random_sound = shoot_sounds[randi() % shoot_sounds.size()]
		shoot_player.stream = random_sound
		shoot_player.play()

func create_arc_lightning():
	if is_being_destroyed:
		return
		
	# Hitung posisi dan arah tembakan
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var start_pos = global_position + muzzle_offset
	
	# Array untuk track target yang sudah terkena (prevent infinite chain)
	var hit_targets = []
	
	# Mulai chain lightning dari target utama
	fire_lightning_chain(start_pos, current_target, hit_targets, 0)

func fire_lightning_chain(from_pos: Vector2, target: Enemy, hit_targets: Array, chain_level: int):
	if is_being_destroyed or not is_instance_valid(target) or chain_level > max_chains:
		return
	
	# Tambahkan target ke hit list
	hit_targets.append(target)
	
	# Berikan damage
	target.take_damage(damage)
	
	# Buat efek lightning arc ke target
	create_lightning_arc(from_pos, target.global_position, chain_level)
	
	# Cari target berikutnya untuk chain (dalam range chain_range dari target saat ini)
	var next_target = find_chain_target(target.global_position, hit_targets)
	
	if next_target and chain_level < max_chains:
		# Delay sedikit sebelum chain ke target berikutnya
		var chain_timer = Timer.new()
		get_tree().current_scene.add_child(chain_timer)
		chain_timer.wait_time = 0.05 + (chain_level * 0.02)  # Delay bertambah per chain level
		chain_timer.one_shot = true
		chain_timer.timeout.connect(func():
			if is_instance_valid(next_target) and not is_being_destroyed:
				fire_lightning_chain(target.global_position, next_target, hit_targets, chain_level + 1)
			chain_timer.queue_free()
		)
		chain_timer.start()

func find_chain_target(from_pos: Vector2, exclude_targets: Array) -> Enemy:
	var closest_target = null
	var closest_distance = chain_range + 1
	
	# Cari di enemies_in_range dulu
	for enemy in enemies_in_range:
		if is_instance_valid(enemy) and not exclude_targets.has(enemy):
			var distance = from_pos.distance_to(enemy.global_position)
			if distance <= chain_range and distance < closest_distance:
				closest_distance = distance
				closest_target = enemy
	
	# Jika tidak ada di enemies_in_range, cari di semua enemy (lebih luas)
	if not closest_target:
		var all_enemies = get_tree().get_nodes_in_group("enemies")
		for enemy in all_enemies:
			if is_instance_valid(enemy) and not exclude_targets.has(enemy):
				var distance = from_pos.distance_to(enemy.global_position)
				if distance <= chain_range and distance < closest_distance:
					closest_distance = distance
					closest_target = enemy
	
	return closest_target

func create_lightning_arc(start_pos: Vector2, end_pos: Vector2, chain_level: int):
	if is_being_destroyed:
		return
	
	# Warna lightning berubah berdasarkan chain level
	var base_color: Color
	match chain_level:
		0: base_color = Color(0.9, 0.9, 1.0, 1.0)      # Putih kebiruan (primary)
		1: base_color = Color(0.7, 0.8, 1.0, 0.9)      # Biru muda (first chain)
		2: base_color = Color(0.5, 0.7, 1.0, 0.8)      # Biru (second chain)
		_: base_color = Color(0.3, 0.6, 1.0, 0.7)      # Biru tua (further chains)
	
	# Buat main lightning line dengan zigzag pattern
	var lightning = create_lightning_line(start_pos, end_pos, base_color)
	get_tree().current_scene.add_child(lightning)
	owned_particles.append(lightning)
	
	# Buat glow effect
	var glow = create_lightning_glow(start_pos, end_pos, base_color)
	get_tree().current_scene.add_child(glow)
	owned_particles.append(glow)
	
	# Animasi lightning
	animate_lightning(lightning, glow, chain_level)
	
	# Impact effect di target
	create_lightning_impact(end_pos, base_color, chain_level)

func create_lightning_line(start_pos: Vector2, end_pos: Vector2, color: Color) -> Line2D:
	var lightning = Line2D.new()
	lightning.width = randf_range(1.5, 2.5)  # Thickness tipis
	lightning.default_color = color
	lightning.begin_cap_mode = Line2D.LINE_CAP_ROUND
	lightning.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Buat zigzag pattern untuk lightning
	var points = create_zigzag_points(start_pos, end_pos, 8)  # 8 segments
	lightning.points = points
	
	return lightning

func create_lightning_glow(start_pos: Vector2, end_pos: Vector2, base_color: Color) -> Line2D:
	var glow = Line2D.new()
	glow.width = randf_range(4.0, 6.0)  # Lebih tebal untuk glow
	var glow_color = base_color
	glow_color.a *= 0.3  # Lebih transparan
	glow.default_color = glow_color
	glow.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Gunakan points yang sama tapi sedikit di-smooth
	var points = create_zigzag_points(start_pos, end_pos, 4)  # Fewer segments untuk glow
	glow.points = points
	
	return glow

func create_zigzag_points(start_pos: Vector2, end_pos: Vector2, segments: int) -> PackedVector2Array:
	var points = PackedVector2Array()
	var direction = end_pos - start_pos
	var distance = direction.length()
	var normalized_dir = direction.normalized()
	var perpendicular = Vector2(-normalized_dir.y, normalized_dir.x)
	
	# Mulai dari start
	points.append(start_pos)
	
	# Buat zigzag points
	for i in range(1, segments):
		var t = float(i) / float(segments)
		var base_point = start_pos + direction * t
		
		# Random offset perpendicular ke arah lightning
		var offset_strength = randf_range(5, 15) * (1.0 - t * 0.5)  # Berkurang mendekati target
		var random_offset = perpendicular * randf_range(-offset_strength, offset_strength)
		
		points.append(base_point + random_offset)
	
	# Akhiri di target
	points.append(end_pos)
	
	return points

# FIXED: Fungsi flicker dengan parameter yang benar
func flicker_lightning_effect(lightning: Line2D, value: float):
	if is_instance_valid(lightning) and not is_being_destroyed:
		# Random flicker dengan intensitas yang menurun
		var flicker_alpha = randf_range(0.3, 1.0) * value
		lightning.modulate.a = flicker_alpha
		
		# Random width variation
		var base_width = 2.0
		lightning.width = base_width * randf_range(0.7, 1.3) * value

func animate_lightning(lightning: Line2D, glow: Line2D, chain_level: int):
	if is_being_destroyed:
		return
	
	# Duration berdasarkan chain level (chain semakin cepat)
	var duration = 0.15 - (chain_level * 0.02)
	duration = max(duration, 0.08)
	
	# Tween untuk lightning utama
	var lightning_tween = create_tween()
	owned_tweens.append(lightning_tween)
	lightning_tween.set_parallel(true)
	
	# FIXED: Gunakan callable yang benar untuk tween_method
	lightning_tween.tween_method(
		func(value: float): flicker_lightning_effect(lightning, value),
		1.0,
		0.0,
		duration
	)
	lightning_tween.tween_property(lightning, "modulate:a", 0.0, duration * 0.7).set_delay(duration * 0.3)
	lightning_tween.tween_callback(func():
		if is_instance_valid(lightning):
			owned_particles.erase(lightning)
			lightning.queue_free()
	).set_delay(duration)
	
	# Tween untuk glow
	var glow_tween = create_tween()
	owned_tweens.append(glow_tween)
	glow_tween.set_parallel(true)
	glow_tween.tween_property(glow, "modulate:a", 0.0, duration * 1.2)
	glow_tween.tween_property(glow, "width", 0.0, duration * 1.2)
	glow_tween.tween_callback(func():
		if is_instance_valid(glow):
			owned_particles.erase(glow)
			glow.queue_free()
	).set_delay(duration * 1.2)

func create_lightning_impact(pos: Vector2, color: Color, chain_level: int):
	if is_being_destroyed:
		return
	
	# Electric spark ring
	var spark_ring = create_electric_spark_ring(pos, color, chain_level)
	get_tree().current_scene.add_child(spark_ring)
	owned_particles.append(spark_ring)
	
	# Animate spark ring
	var ring_tween = create_tween()
	owned_tweens.append(ring_tween)
	ring_tween.set_parallel(true)
	ring_tween.tween_property(spark_ring, "scale", Vector2(1.5, 1.5), 0.1)
	ring_tween.tween_property(spark_ring, "modulate:a", 0.0, 0.1)
	ring_tween.tween_callback(func():
		if is_instance_valid(spark_ring):
			owned_particles.erase(spark_ring)
			spark_ring.queue_free()
	).set_delay(0.1)
	
	# Small electric particles
	for i in range(3 + chain_level):
		create_electric_particle(pos, color)

func create_electric_spark_ring(pos: Vector2, color: Color, chain_level: int) -> Node2D:
	var ring = Node2D.new()
	ring.global_position = pos
	
	# Buat beberapa garis pendek membentuk ring electric
	var line_count = 6
	var radius = 8.0 - (chain_level * 1.0)  # Ring semakin kecil untuk chain
	
	for i in range(line_count):
		var angle = (2.0 * PI * i) / line_count + randf_range(-0.3, 0.3)
		var start_radius = radius * 0.7
		var end_radius = radius * 1.3
		
		var start_point = Vector2(cos(angle), sin(angle)) * start_radius
		var end_point = Vector2(cos(angle), sin(angle)) * end_radius
		
		var spark_line = Line2D.new()
		spark_line.width = 1.5
		spark_line.default_color = color
		spark_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		spark_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		
		var points = PackedVector2Array()
		points.append(start_point)
		points.append(end_point)
		spark_line.points = points
		
		ring.add_child(spark_line)
	
	return ring

func create_electric_particle(pos: Vector2, color: Color):
	if is_being_destroyed:
		return
	
	var particle = create_circle_shape(Vector2.ZERO, 1.0, color)
	get_tree().current_scene.add_child(particle)
	particle.global_position = pos
	owned_particles.append(particle)
	
	# Random movement
	var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance = randf_range(10, 20)
	var end_pos = pos + random_dir * distance
	
	var particle_tween = create_tween()
	owned_tweens.append(particle_tween)
	particle_tween.set_parallel(true)
	particle_tween.tween_property(particle, "global_position", end_pos, 0.12)
	particle_tween.tween_property(particle, "modulate:a", 0.0, 0.12)
	particle_tween.tween_property(particle, "scale", Vector2(0.3, 0.3), 0.12)
	particle_tween.tween_callback(func():
		if is_instance_valid(particle):
			owned_particles.erase(particle)
			particle.queue_free()
	).set_delay(0.12)

func create_muzzle_flash():
	if is_being_destroyed:
		return
	
	# Electric muzzle flash
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var muzzle_pos = global_position + muzzle_offset
	
	# Electric spark burst
	for i in range(4):
		var spark_angle = randf_range(0, 2 * PI)
		var spark_distance = randf_range(8, 15)
		var spark_end = muzzle_pos + Vector2(cos(spark_angle), sin(spark_angle)) * spark_distance
		
		var spark_line = Line2D.new()
		spark_line.width = 1.0
		spark_line.default_color = Color(0.8, 0.9, 1.0, 1.0)
		spark_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		spark_line.end_cap_mode = Line2D.LINE_CAP_ROUND
		
		var points = PackedVector2Array()
		points.append(muzzle_pos)
		points.append(spark_end)
		spark_line.points = points
		
		get_tree().current_scene.add_child(spark_line)
		owned_particles.append(spark_line)
		
		var spark_tween = create_tween()
		owned_tweens.append(spark_tween)
		spark_tween.tween_property(spark_line, "modulate:a", 0.0, 0.06)
		spark_tween.tween_callback(func():
			if is_instance_valid(spark_line):
				owned_particles.erase(spark_line)
				spark_line.queue_free()
		).set_delay(0.06)

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

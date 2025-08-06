extends StaticBody2D
class_name Tower2

@export var damage = 5
@export var fire_rate = 0.1
@export var range_radius = 100
@export var rotation_speed = 180.0  # Degrees per second

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

func _ready():
	setup_tower()
	setup_audio()

func setup_audio():
	# Buat audio player untuk shoot sound
	shoot_player = AudioStreamPlayer2D.new()
	add_child(shoot_player)
	shoot_player.volume_db = -2 # Agak pelan
	shoot_player.max_distance = 500 # Jarak maksimal terdengar

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

func _process(delta):
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
	if not current_target:
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
	if current_target and is_instance_valid(current_target):
		current_target.take_damage(damage)
		create_advanced_muzzle_flash()
		play_shoot_sound()  # Tambahan: play audio
		can_shoot = false
		shoot_timer.start()

func play_shoot_sound():
	# Play random shoot sound jika ada
	if shoot_player and shoot_sounds.size() > 0:
		var random_sound = shoot_sounds[randi() % shoot_sounds.size()]
		shoot_player.stream = random_sound
		
		# Variasi pitch sedikit untuk lebih natural
		shoot_player.play()

func create_advanced_muzzle_flash():
	# Hitung posisi dan arah tembakan
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var muzzle_pos = global_position + muzzle_offset
	var target_pos = current_target.global_position
	var direction = (target_pos - muzzle_pos).normalized()
	
	# === MUZZLE FLASH EFFECT ===
	create_muzzle_blast(muzzle_pos)
	create_muzzle_particles(muzzle_pos, direction)
	
	# === BULLET TRAIL EFFECT ===
	create_bullet_trail(muzzle_pos, target_pos)
	
	# === SCREEN SHAKE (optional) ===
	add_screen_shake()

func create_muzzle_blast(pos: Vector2):
	# Flash utama - lingkaran besar yang mengembang
	var blast = ColorRect.new()
	get_tree().current_scene.add_child(blast)
	blast.global_position = pos - Vector2(15, 15)
	blast.size = Vector2(30, 30)
	blast.color = Color(1.0, 0.9, 0.3, 0.8)  # Kuning terang
	
	# Buat bentuk bulat dengan shader atau manual
	var tween1 = create_tween()
	tween1.set_parallel(true)
	
	# Expand dan fade
	tween1.tween_property(blast, "size", Vector2(60, 60), 0.15)
	tween1.tween_property(blast, "global_position", pos - Vector2(30, 30), 0.15)
	tween1.tween_property(blast, "modulate:a", 0.0, 0.15)
	tween1.tween_callback(blast.queue_free).set_delay(0.15)
	
	# Flash kedua - lebih kecil, lebih terang
	var inner_flash = ColorRect.new()
	get_tree().current_scene.add_child(inner_flash)
	inner_flash.global_position = pos - Vector2(8, 8)
	inner_flash.size = Vector2(16, 16)
	inner_flash.color = Color(1.0, 1.0, 0.8, 1.0)  # Putih kekuningan
	
	var tween2 = create_tween()
	tween2.set_parallel(true)
	tween2.tween_property(inner_flash, "size", Vector2(35, 35), 0.08)
	tween2.tween_property(inner_flash, "global_position", pos - Vector2(17.5, 17.5), 0.08)
	tween2.tween_property(inner_flash, "modulate:a", 0.0, 0.08)
	tween2.tween_callback(inner_flash.queue_free).set_delay(0.08)

func create_muzzle_particles(pos: Vector2, direction: Vector2):
	# Buat beberapa partikel kecil yang tersebar
	for i in range(6):
		var particle = ColorRect.new()
		get_tree().current_scene.add_child(particle)
		
		var angle_offset = randf_range(-45, 45)
		var particle_dir = direction.rotated(deg_to_rad(angle_offset))
		var distance = randf_range(20, 40)
		
		particle.global_position = pos
		particle.size = Vector2(3, 3)
		particle.color = Color(1.0, 0.7, 0.2, 0.9)
		
		var end_pos = pos + particle_dir * distance
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "global_position", end_pos, 0.12)
		tween.tween_property(particle, "modulate:a", 0.0, 0.12)
		tween.tween_property(particle, "size", Vector2(1, 1), 0.12)
		tween.tween_callback(particle.queue_free).set_delay(0.12)

func create_bullet_trail(start_pos: Vector2, end_pos: Vector2):
	# Buat trail utama
	var trail = Line2D.new()
	get_tree().current_scene.add_child(trail)
	
	# Setup trail properties
	trail.add_point(start_pos)
	trail.add_point(end_pos)
	trail.width = 4.0
	trail.default_color = Color(1.0, 0.8, 0.4, 0.9)
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	# Animasi trail - fade out dengan menyusut
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(trail, "width", 0.0, 0.2)
	tween.tween_property(trail, "modulate:a", 0.0, 0.2)
	tween.tween_callback(trail.queue_free).set_delay(0.2)
	
	# Buat trail glow effect
	var glow_trail = Line2D.new()
	get_tree().current_scene.add_child(glow_trail)
	glow_trail.add_point(start_pos)
	glow_trail.add_point(end_pos)
	glow_trail.width = 8.0
	glow_trail.default_color = Color(1.0, 0.9, 0.5, 0.4)
	glow_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	
	var glow_tween = create_tween()
	glow_tween.set_parallel(true)
	glow_tween.tween_property(glow_trail, "width", 0.0, 0.25)
	glow_tween.tween_property(glow_trail, "modulate:a", 0.0, 0.25)
	glow_tween.tween_callback(glow_trail.queue_free).set_delay(0.25)
	
	# Impact effect di target
	create_impact_effect(end_pos)

func create_impact_effect(pos: Vector2):
	# Ring impact effect
	var impact_ring = ColorRect.new()
	get_tree().current_scene.add_child(impact_ring)
	impact_ring.global_position = pos - Vector2(5, 5)
	impact_ring.size = Vector2(10, 10)
	impact_ring.color = Color(1.0, 0.5, 0.2, 0.8)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(impact_ring, "size", Vector2(25, 25), 0.1)
	tween.tween_property(impact_ring, "global_position", pos - Vector2(12.5, 12.5), 0.1)
	tween.tween_property(impact_ring, "modulate:a", 0.0, 0.1)
	tween.tween_callback(impact_ring.queue_free).set_delay(0.1)
	
	# Sparks dari impact
	for i in range(4):
		create_impact_spark(pos)

func create_impact_spark(pos: Vector2):
	var spark = ColorRect.new()
	get_tree().current_scene.add_child(spark)
	
	var random_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance = randf_range(15, 25)
	
	spark.global_position = pos
	spark.size = Vector2(2, 6)
	spark.color = Color(1.0, 0.6, 0.1, 1.0)
	spark.rotation = random_dir.angle()
	
	var end_pos = pos + random_dir * distance
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "global_position", end_pos, 0.15)
	tween.tween_property(spark, "modulate:a", 0.0, 0.15)
	tween.tween_property(spark, "size", Vector2(1, 3), 0.15)
	tween.tween_callback(spark.queue_free).set_delay(0.15)

func add_screen_shake():
	# Optional: Tambahkan sedikit screen shake untuk impact
	# Implementasi tergantung pada sistem camera yang digunakan
	pass

func reset_shooting():
	can_shoot = true

func _on_enemy_entered(body):
	if body is Enemy:
		enemies_in_range.append(body)
		# Jika belum ada target, set sebagai target
		if not current_target:
			set_target(body)

func _on_enemy_exited(body):
	if body is Enemy:
		enemies_in_range.erase(body)
		# Jika target keluar range, cari target baru
		if current_target == body:
			current_target = null
			find_new_target()

func set_grid_position(grid_pos: Vector2i):
	grid_position = grid_pos
	global_position = GridManager.grid_to_world(grid_pos)

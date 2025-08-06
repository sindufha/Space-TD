extends StaticBody2D
class_name Tower

@export var damage = 5
@export var fire_rate = 1
@export var range_radius = 100
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
		create_projectile()
		create_simple_muzzle_flash()
		play_shoot_sound()
		can_shoot = false
		shoot_timer.start()

func play_shoot_sound():
	# Play random shoot sound jika ada
	if shoot_player and shoot_sounds.size() > 0:
		var random_sound = shoot_sounds[randi() % shoot_sounds.size()]
		shoot_player.stream = random_sound
		
		# Variasi pitch sedikit untuk lebih natural
		shoot_player.play()

func create_projectile():
	# Hitung posisi dan arah tembakan
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var start_pos = global_position + muzzle_offset
	var target_pos = current_target.global_position
	var direction = (target_pos - start_pos).normalized()
	
	# Buat projectile (bola kecil)
	var projectile = create_projectile_ball()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = start_pos
	
	# Hitung waktu untuk mencapai target
	var distance = start_pos.distance_to(target_pos)
	var travel_time = distance / projectile_speed
	
	# Animasi projectile terbang ke target
	var tween = create_tween()
	tween.tween_property(projectile, "global_position", target_pos, travel_time)
	
	# Hancurkan projectile saat sampai dan berikan damage
	tween.tween_callback(func(): hit_target(projectile, target_pos))

func create_projectile_ball() -> Node2D:
	# Buat container untuk projectile
	var projectile = Node2D.new()
	
	# Buat bola utama (core) - warna cyan cerah
	var core = create_circle_shape(Vector2.ZERO, 5, Color(0.2, 0.8, 1.0, 1.0))
	projectile.add_child(core)
	
	# Buat glow effect di sekitar bola - warna biru electric
	var glow = create_circle_shape(Vector2.ZERO, 8, Color(0.4, 0.6, 1.0, 0.7))
	projectile.add_child(glow)
	projectile.move_child(glow, 0)  # Glow di belakang core
	
	# Tambahkan trail effect
	var trail = Line2D.new()
	trail.width = 4.0
	trail.default_color = Color(0.3, 0.7, 1.0, 0.8)
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	projectile.add_child(trail)
	
	# Animasi glow yang berkedip
	var glow_tween = create_tween()
	glow_tween.set_loops()
	glow_tween.tween_property(glow, "modulate:a", 0.4, 0.12)
	glow_tween.tween_property(glow, "modulate:a", 0.9, 0.12)
	
	return projectile

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

func hit_target(projectile: Node2D, hit_pos: Vector2):
	# Berikan damage ke target jika masih valid
	if current_target and is_instance_valid(current_target):
		current_target.take_damage(damage)
	
	# Buat particle explosion effect yang keren
	create_particle_explosion(hit_pos)
	
	# Hapus projectile
	projectile.queue_free()

func create_particle_explosion(pos: Vector2):
	# Buat banyak partikel dengan berbagai warna dan ukuran
	var particle_colors = [
		Color(1.0, 0.3, 0.1),    # Orange terang
		Color(1.0, 0.7, 0.2),    # Kuning orange
		Color(0.9, 0.9, 0.3),    # Kuning cerah
		Color(1.0, 0.4, 0.4),    # Merah pink
		Color(0.8, 0.2, 0.8),    # Ungu
		Color(0.2, 0.8, 1.0),    # Cyan
		Color(1.0, 1.0, 1.0)     # Putih
	]
	
	# Buat main explosion flash
	var main_flash = create_circle_shape(Vector2.ZERO, 12, Color(1.0, 1.0, 0.9, 1.0))
	get_tree().current_scene.add_child(main_flash)
	main_flash.global_position = pos
	
	var flash_tween = create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(main_flash, "scale", Vector2(3.5, 3.5), 0.18)
	flash_tween.tween_property(main_flash, "modulate:a", 0.0, 0.18)
	flash_tween.tween_callback(main_flash.queue_free).set_delay(0.18)
	
	# Buat 15 partikel yang beterbangan
	for i in range(15):
		create_explosion_particle(pos, particle_colors)
	
	# Buat 8 partikel kecil tambahan
	for i in range(8):
		create_small_particle(pos, particle_colors)
	
	# Buat shockwave ring
	create_shockwave_ring(pos)

func create_explosion_particle(pos: Vector2, colors: Array):
	var random_color = colors[randi() % colors.size()]
	var particle_size = randf_range(3, 7)
	var particle = create_circle_shape(Vector2.ZERO, particle_size, random_color)
	
	get_tree().current_scene.add_child(particle)
	particle.global_position = pos
	
	# Random direction dan distance
	var angle = randf() * 2 * PI
	var distance = randf_range(25, 55)
	var direction = Vector2(cos(angle), sin(angle))
	var end_pos = pos + direction * distance
	
	# Random duration
	var duration = randf_range(0.3, 0.6)
	
	var particle_tween = create_tween()
	particle_tween.set_parallel(true)
	
	# Movement dengan gravity effect - FIXED: gunakan callable yang benar
	var mid_pos = pos + direction * distance * 0.7 + Vector2(0, -randf_range(10, 25))
	particle_tween.tween_method(bezier_move_particle.bind(particle, pos, mid_pos, end_pos), 0.0, 1.0, duration)
	
	# Fade out
	particle_tween.tween_property(particle, "modulate:a", 0.0, duration)
	
	# Scale down
	particle_tween.tween_property(particle, "scale", Vector2(0.2, 0.2), duration)
	
	# Rotation
	particle_tween.tween_property(particle, "rotation", randf_range(-4, 4), duration)
	
	particle_tween.tween_callback(particle.queue_free).set_delay(duration)

func create_small_particle(pos: Vector2, colors: Array):
	var random_color = colors[randi() % colors.size()]
	random_color.a = 0.8
	var particle = create_circle_shape(Vector2.ZERO, randf_range(1.5, 3), random_color)
	
	get_tree().current_scene.add_child(particle)
	particle.global_position = pos
	
	# Gerak yang lebih cepat dan pendek
	var angle = randf() * 2 * PI
	var distance = randf_range(15, 35)
	var direction = Vector2(cos(angle), sin(angle))
	var end_pos = pos + direction * distance
	
	var duration = randf_range(0.2, 0.4)
	
	var small_tween = create_tween()
	small_tween.set_parallel(true)
	small_tween.tween_property(particle, "global_position", end_pos, duration)
	small_tween.tween_property(particle, "modulate:a", 0.0, duration)
	small_tween.tween_property(particle, "scale", Vector2(0.1, 0.1), duration)
	small_tween.tween_callback(particle.queue_free).set_delay(duration)

func create_shockwave_ring(pos: Vector2):
	# Buat ring shockwave
	var ring = Node2D.new()
	get_tree().current_scene.add_child(ring)
	ring.global_position = pos
	
	# Buat outline ring
	var line = Line2D.new()
	ring.add_child(line)
	line.width = 3.0
	line.default_color = Color(1.0, 0.8, 0.4, 0.9)
	line.closed = true
	
	# Buat points untuk ring
	var points = PackedVector2Array()
	var segments = 24
	var radius = 8
	for i in range(segments):
		var angle = 2.0 * PI * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	line.points = points
	
	# Animasi ring mengembang
	var ring_tween = create_tween()
	ring_tween.set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector2(4.0, 4.0), 0.25)
	ring_tween.tween_property(line, "modulate:a", 0.0, 0.25)
	ring_tween.tween_property(line, "width", 1.0, 0.25)
	ring_tween.tween_callback(ring.queue_free).set_delay(0.25)

# FIXED: Buat fungsi terpisah untuk bezier movement
func bezier_move_particle(particle: Node2D, start: Vector2, control: Vector2, end: Vector2, t: float):
	# Bezier curve movement untuk efek parabola yang natural
	var pos = start.lerp(control, t).lerp(control.lerp(end, t), t)
	particle.global_position = pos

func create_simple_muzzle_flash():
	# Flash sederhana di muzzle dengan warna cyan
	var muzzle_offset = Vector2(35, 0).rotated(rotation)
	var muzzle_pos = global_position + muzzle_offset
	
	var flash = create_circle_shape(Vector2.ZERO, 8, Color(0.4, 0.9, 1.0, 0.9))
	get_tree().current_scene.add_child(flash)
	flash.global_position = muzzle_pos
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(2.5, 2.5), 0.12)
	tween.tween_property(flash, "modulate:a", 0.0, 0.12)
	tween.tween_callback(flash.queue_free).set_delay(0.12)

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

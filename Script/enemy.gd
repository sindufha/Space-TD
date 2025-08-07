extends CharacterBody2D
class_name Enemy

@export var max_health = 100
@export var speed = 50
@export var reward = 10
@export var fragment_count = 8  # Jumlah kepingan saat hancur

@export_group("Death Effect Colors")
@export var fragment_colors: Array[Color] = [Color.RED, Color.ORANGE, Color.YELLOW, Color.WHITE]  # Warna kepingan
@export var explosion_color: Color = Color(1.0, 0.4, 0.1, 0.8)  # Warna explosion ring
@export var flash_color: Color = Color(1.0, 1.0, 0.8, 1.0)  # Warna inner flash
@export var particle_color: Color = Color(1.0, 0.6, 0.2, 0.9)  # Warna partikel kecil

@onready var progress_bar: ProgressBar = $ProgressBar
var current_health
var path_follow: PathFollow2D
var has_reached_end = false  # Tambah flag ini
var is_dying = false  # Flag untuk mencegah double death

# Helper function untuk membuat tween yang tidak terpengaruh pause
func create_pause_resistant_tween() -> Tween:
	var tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)  # Menggunakan physics process
	return tween

func _ready():
	current_health = max_health
	update_health_bar()

func _physics_process(delta):
	if path_follow and not has_reached_end and not is_dying:
		path_follow.progress += speed * delta
		global_position = path_follow.global_position
		
		# Ganti kondisi ini - lebih toleran
		if path_follow.progress_ratio >= 0.98:  # 98% sudah dianggap sampai
			print("Enemy reached end at progress: ", path_follow.progress_ratio)
			reach_end()

func take_damage(damage):
	if is_dying or has_reached_end:
		return
		
	current_health -= damage
	update_health_bar()
	
	# Flash effect saat terkena damage
	create_damage_flash()
	
	if current_health <= 0:
		die()

func create_damage_flash():
	# Flash merah saat terkena damage
	var flash = ColorRect.new()
	get_tree().current_scene.add_child(flash)
	flash.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	flash.global_position = global_position - Vector2(15, 15)
	flash.size = Vector2(30, 30)
	flash.color = Color(1.0, 0.3, 0.3, 0.6)
	
	var tween = create_pause_resistant_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	# FIX: Gunakan Timer instead of tween_callback untuk cleanup
	create_safe_timer(0.2, func(): 
		if is_instance_valid(flash):
			flash.queue_free()
	)

func update_health_bar():
	if has_node("ProgressBar"):
		$ProgressBar.value = float(current_health) / max_health * 100
	if current_health == 100:
		progress_bar.visible = false
	else:
		progress_bar.visible = true

func die():
	if is_dying or has_reached_end:
		return
		
	is_dying = true
	print("Enemy died, adding money: ", reward)
	GameManager.add_money(reward)
	
	# Disable collision dan detection agar tower tidak menyerang lagi
	disable_enemy_detection()
	
	# Buat efek kematian yang spektakuler
	create_death_explosion()
	create_fragments()
	create_death_particles()
	
	# Sembunyikan enemy asli tapi jangan langsung hapus
	modulate.a = 0.0
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(2.0, func(): 
		if is_instance_valid(self):
			queue_free()
	)

func disable_enemy_detection():
	# Disable collision detection
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	
	# Disable semua CollisionShape2D di enemy
	for child in get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
	
	# Jika enemy punya Area2D untuk detection, disable juga
	for child in get_children():
		if child is Area2D:
			child.set_deferred("monitoring", false)
			child.set_deferred("monitorable", false)
			for area_child in child.get_children():
				if area_child is CollisionShape2D:
					area_child.set_deferred("disabled", true)

func create_death_explosion():
	# Explosion ring utama - gunakan custom color
	var explosion = create_circle_shape(Vector2.ZERO, 15, explosion_color)
	get_tree().current_scene.add_child(explosion)
	explosion.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	explosion.global_position = global_position
	
	var exp_tween = create_pause_resistant_tween()
	exp_tween.set_parallel(true)
	exp_tween.tween_property(explosion, "scale", Vector2(4.0, 4.0), 0.4)
	exp_tween.tween_property(explosion, "modulate:a", 0.0, 0.4)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(0.4, func(): 
		if is_instance_valid(explosion):
			explosion.queue_free()
	)
	
	# Inner explosion flash - gunakan custom color
	var flash = create_circle_shape(Vector2.ZERO, 10, flash_color)
	get_tree().current_scene.add_child(flash)
	flash.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	flash.global_position = global_position
	
	var flash_tween = create_pause_resistant_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(3.0, 3.0), 0.25)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(0.25, func(): 
		if is_instance_valid(flash):
			flash.queue_free()
	)

func create_fragments():
	# Buat kepingan-kepingan yang beterbangan
	for i in range(fragment_count):
		create_single_fragment(i)

func create_single_fragment(index: int):
	# Buat fragment dengan bentuk acak
	var fragment = Node2D.new()
	get_tree().current_scene.add_child(fragment)
	fragment.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	fragment.global_position = global_position
	
	# Buat bentuk fragment (persegi panjang kecil atau segitiga)
	var shape_type = randi() % 3
	var fragment_visual
	
	match shape_type:
		0: # Persegi panjang
			fragment_visual = create_rectangle_fragment()
		1: # Segitiga
			fragment_visual = create_triangle_fragment()
		2: # Persegi kecil
			fragment_visual = create_square_fragment()
	
	fragment.add_child(fragment_visual)
	
	# Random direction dan properties
	var angle = (2.0 * PI * index / fragment_count) + randf_range(-0.5, 0.5)
	var direction = Vector2(cos(angle), sin(angle))
	var distance = randf_range(60, 120)
	var rotation_speed = randf_range(-720, 720)  # Degrees per second
	
	# PENTING: Buat movement dan rotation tween yang terpisah
	var start_pos = global_position
	var end_pos = start_pos + direction * distance
	var gravity_fall = Vector2(0, 40)
	
	# Movement dengan parabolic path menggunakan pause resistant tween
	create_parabolic_movement(fragment, start_pos, end_pos, gravity_fall, 1.5)
	
	# Buat tween terpisah untuk rotation, fade, dan scale
	var visual_tween = create_pause_resistant_tween()
	visual_tween.set_parallel(true)
	
	# Rotation
	visual_tween.tween_property(fragment, "rotation_degrees", rotation_speed, 1.5)
	# Fade out
	visual_tween.tween_property(fragment, "modulate:a", 0.0, 1.5)
	# Scale down
	visual_tween.tween_property(fragment, "scale", Vector2(0.3, 0.3), 1.5)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(1.5, func(): 
		if is_instance_valid(fragment):
			fragment.queue_free()
	)

# FIX: Simplified parabolic movement tanpa lambda yang bermasalah
func create_parabolic_movement(fragment: Node2D, start_pos: Vector2, end_pos: Vector2, gravity: Vector2, duration: float):
	# Gunakan tween property dengan custom method
	var movement_tween = create_pause_resistant_tween()
	movement_tween.set_parallel(false)
	
	# Store data di fragment untuk diakses oleh method
	fragment.set_meta("start_pos", start_pos)
	fragment.set_meta("end_pos", end_pos)
	fragment.set_meta("gravity", gravity)
	
	# Gunakan tween_method dengan method call instead of lambda
	movement_tween.tween_method(_update_fragment_position.bind(fragment), 0.0, 1.0, duration)

# FIX: Method terpisah untuk update position fragment
func _update_fragment_position(fragment: Node2D, progress: float):
	if not is_instance_valid(fragment):
		return
		
	var start_pos = fragment.get_meta("start_pos", Vector2.ZERO)
	var end_pos = fragment.get_meta("end_pos", Vector2.ZERO)
	var gravity = fragment.get_meta("gravity", Vector2.ZERO)
	
	# Simple parabolic calculation
	var current_pos = start_pos.lerp(end_pos, progress)
	# Add parabolic curve (peak di tengah)
	var curve_height = sin(progress * PI) * -30  # Negative untuk naik
	var gravity_effect = gravity * progress * progress  # Quadratic fall
	fragment.global_position = current_pos + Vector2(0, curve_height) + gravity_effect

func create_rectangle_fragment() -> Polygon2D:
	var rect = Polygon2D.new()
	var width = randf_range(6, 12)
	var height = randf_range(4, 8)
	
	rect.polygon = PackedVector2Array([
		Vector2(-width/2, -height/2),
		Vector2(width/2, -height/2),
		Vector2(width/2, height/2),
		Vector2(-width/2, height/2)
	])
	
	# Gunakan custom fragment colors, fallback ke default jika array kosong
	if fragment_colors.size() > 0:
		rect.color = fragment_colors[randi() % fragment_colors.size()]
	else:
		rect.color = Color.RED  # Fallback color
	return rect

func create_triangle_fragment() -> Polygon2D:
	var triangle = Polygon2D.new()
	var size = randf_range(6, 10)
	
	triangle.polygon = PackedVector2Array([
		Vector2(0, -size),
		Vector2(-size * 0.866, size * 0.5),
		Vector2(size * 0.866, size * 0.5)
	])
	
	# Gunakan custom fragment colors, fallback ke default jika array kosong
	if fragment_colors.size() > 0:
		triangle.color = fragment_colors[randi() % fragment_colors.size()]
	else:
		triangle.color = Color.ORANGE  # Fallback color
	return triangle

func create_square_fragment() -> Polygon2D:
	var square = Polygon2D.new()
	var size = randf_range(5, 9)
	
	square.polygon = PackedVector2Array([
		Vector2(-size/2, -size/2),
		Vector2(size/2, -size/2),
		Vector2(size/2, size/2),
		Vector2(-size/2, size/2)
	])
	
	# Gunakan custom fragment colors, fallback ke default jika array kosong
	if fragment_colors.size() > 0:
		square.color = fragment_colors[randi() % fragment_colors.size()]
	else:
		square.color = Color.YELLOW  # Fallback color
	return square

func create_death_particles():
	# Buat partikel-partikel kecil yang beterbangan
	for i in range(20):
		create_death_particle()

func create_death_particle():
	var particle = create_circle_shape(Vector2.ZERO, randf_range(1, 3), particle_color)
	get_tree().current_scene.add_child(particle)
	particle.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	particle.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	
	var direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance = randf_range(40, 80)
	var end_pos = particle.global_position + direction * distance
	var duration = randf_range(0.8, 1.5)
	
	var tween = create_pause_resistant_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "global_position", end_pos, duration)
	tween.tween_property(particle, "modulate:a", 0.0, duration)
	tween.tween_property(particle, "scale", Vector2(0.2, 0.2), duration)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(duration, func(): 
		if is_instance_valid(particle):
			particle.queue_free()
	)

func create_circle_shape(pos: Vector2, radius: float, color: Color) -> Polygon2D:
	# Buat shape circle menggunakan Polygon2D
	var circle = Polygon2D.new()
	circle.position = pos
	circle.color = color
	
	# Buat vertices untuk circle yang smooth
	var vertices = PackedVector2Array()
	var segments = 12
	for i in range(segments):
		var angle = 2.0 * PI * i / segments
		vertices.append(Vector2(cos(angle), sin(angle)) * radius)
	
	circle.polygon = vertices
	return circle

# FIX: Ganti backup cleanup dengan safe timer function
func create_safe_timer(delay: float, callback: Callable):
	var timer = Timer.new()
	get_tree().current_scene.add_child(timer)
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.wait_time = delay
	timer.one_shot = true
	
	# FIX: Gunakan signal connection yang lebih aman
	var cleanup_func = func():
		callback.call()
		if is_instance_valid(timer):
			timer.queue_free()
	
	timer.timeout.connect(cleanup_func, CONNECT_ONE_SHOT)
	timer.start()

func reach_end():
	if has_reached_end or is_dying:  # Prevent double call
		return
		
	has_reached_end = true
	print("Enemy reached end, losing health!")
	GameManager.lose_health(1)
	
	# Disable detection juga untuk reach end
	disable_enemy_detection()
	
	# Efek sederhana untuk reach end (tidak hancur berkeping-keping)
	create_reach_end_effect()
	
	# Fade out simple - gunakan pause resistant tween
	var tween = create_pause_resistant_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(0.5, func(): 
		if is_instance_valid(self):
			queue_free()
	)

func create_reach_end_effect():
	# Efek sederhana - hanya flash hijau dan fade
	var flash = create_circle_shape(Vector2.ZERO, 20, Color(0.2, 1.0, 0.3, 0.6))
	get_tree().current_scene.add_child(flash)
	flash.process_mode = Node.PROCESS_MODE_ALWAYS  # Agar tetap berjalan saat pause
	flash.global_position = global_position
	
	var tween = create_pause_resistant_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.3)
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	
	# FIX: Gunakan safe timer untuk cleanup
	create_safe_timer(0.3, func(): 
		if is_instance_valid(flash):
			flash.queue_free()
	)

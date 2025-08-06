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
	flash.global_position = global_position - Vector2(15, 15)
	flash.size = Vector2(30, 30)
	flash.color = Color(1.0, 0.3, 0.3, 0.6)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free).set_delay(0.2)


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
	
	# Hapus setelah efek selesai
	await get_tree().create_timer(2.0).timeout
	queue_free()

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
	explosion.global_position = global_position
	
	var exp_tween = create_tween()
	exp_tween.set_parallel(true)
	exp_tween.tween_property(explosion, "scale", Vector2(4.0, 4.0), 0.4)
	exp_tween.tween_property(explosion, "modulate:a", 0.0, 0.4)
	exp_tween.tween_callback(explosion.queue_free).set_delay(0.4)
	
	# Inner explosion flash - gunakan custom color
	var flash = create_circle_shape(Vector2.ZERO, 10, flash_color)
	get_tree().current_scene.add_child(flash)
	flash.global_position = global_position
	
	var flash_tween = create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(3.0, 3.0), 0.25)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	flash_tween.tween_callback(flash.queue_free).set_delay(0.25)

func create_fragments():
	# Buat kepingan-kepingan yang beterbangan
	for i in range(fragment_count):
		create_single_fragment(i)

func create_single_fragment(index: int):
	# Buat fragment dengan bentuk acak
	var fragment = Node2D.new()
	get_tree().current_scene.add_child(fragment)
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
	
	# Animasi fragment terbang
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Movement dengan parabolic path - FIXED VERSION
	var start_pos = global_position
	var end_pos = start_pos + direction * distance
	var gravity_fall = Vector2(0, 40)  # Gravity effect
	
	# Buat simple parabolic movement tanpa tween_method yang bermasalah
	create_parabolic_movement(fragment, start_pos, end_pos, gravity_fall, 1.5)
	
	# Rotation
	tween.tween_property(fragment, "rotation_degrees", rotation_speed, 1.5)
	
	# Fade out
	tween.tween_property(fragment, "modulate:a", 0.0, 1.5)
	
	# Scale down
	tween.tween_property(fragment, "scale", Vector2(0.3, 0.3), 1.5)
	
	# Cleanup
	tween.tween_callback(fragment.queue_free).set_delay(1.5)

# FIXED: Buat parabolic movement dengan approach yang lebih sederhana
func create_parabolic_movement(fragment: Node2D, start_pos: Vector2, end_pos: Vector2, gravity: Vector2, duration: float):
	# Gunakan simple tween dengan custom interpolation
	var movement_tween = create_tween()
	
	# SAFETY: Set tween properties to prevent infinite loop
	movement_tween.set_loops(1)  # Explicitly set to run only once
	movement_tween.set_parallel(false)
	
	# Buat callable untuk movement update yang tidak menggunakan bind bermasalah
	var update_func = func(progress: float):
		if is_instance_valid(fragment):
			# Simple parabolic calculation
			var current_pos = start_pos.lerp(end_pos, progress)
			# Add parabolic curve (peak di tengah)
			var curve_height = sin(progress * PI) * -30  # Negative untuk naik
			var gravity_effect = gravity * progress * progress  # Quadratic fall
			fragment.global_position = current_pos + Vector2(0, curve_height) + gravity_effect
	
	movement_tween.tween_method(update_func, 0.0, 1.0, duration)

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
	particle.global_position = global_position + Vector2(randf_range(-10, 10), randf_range(-10, 10))
	
	var direction = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	var distance = randf_range(40, 80)
	var end_pos = particle.global_position + direction * distance
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(particle, "global_position", end_pos, randf_range(0.8, 1.5))
	tween.tween_property(particle, "modulate:a", 0.0, randf_range(0.8, 1.5))
	tween.tween_property(particle, "scale", Vector2(0.2, 0.2), randf_range(0.8, 1.5))
	tween.tween_callback(particle.queue_free).set_delay(1.5)

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
	
	# Fade out simple
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free).set_delay(0.5)

func create_reach_end_effect():
	# Efek sederhana - hanya flash hijau dan fade
	var flash = create_circle_shape(Vector2.ZERO, 20, Color(0.2, 1.0, 0.3, 0.6))
	get_tree().current_scene.add_child(flash)
	flash.global_position = global_position
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.3)
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free).set_delay(0.3)

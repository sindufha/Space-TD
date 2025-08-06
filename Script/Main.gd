extends Node2D

@export_group("Enemy Settings")
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_spawn_weights: Array[float] = []
@export var enemy_spawn_interval: float = 2.0
@export var base_enemies_per_wave: int = 5
@export var enemy_increase_per_wave: int = 2

@export_group("Wave Settings")
@export var max_waves: int = 10
@export var wave_cooldown: float = 3.0
@export var wave_speed_increase: float = 0.1

@export_group("Tower Settings")
@export var tower_scenes: Array[PackedScene] = []
@export var tower_names: Array[String] = ["Basic Tower", "Cannon Tower", "Ice Tower"]
@export var tower_costs: Array[int] = [50, 75, 100]

@export_group("Buildable Tiles")
@export var tilemap_node: TileMap
@export var buildable_layer: int = 0
@export var buildable_source_ids: Array[int] = [0]
@export var show_buildable_debug: bool = false

@export_group("Audio Settings")
@export var background_music: AudioStream
@export var bgm_volume: float = -8.0

@onready var ui_tower: Control = $UICanvas/UITower
@onready var wave_label: Label = $CanvasLayer/UI/HBoxContainer/WaveContainer/WaveLabel
@onready var paused_ui: CanvasLayer = $PausedUI


var spawn_timer: Timer
var wave_timer: Timer
var wave_number: int = 1
var enemies_to_spawn: int = 0
var enemies_alive: int = 0
var wave_in_progress: bool = false
var game_completed: bool = false

var occupied_grid_positions: Array[Vector2i] = []
var path_grid_positions: Array[Vector2i] = []
var buildable_grid_positions: Array[Vector2i] = []

var pending_tower_grid_position: Vector2i
var awaiting_tower_selection: bool = false

# Variabel untuk grid border
var selected_grid_position: Vector2i
var show_grid_border: bool = false

var bgm_player: AudioStreamPlayer
var total_spawn_weight: float = 0.0
@onready var resume_btn: Button = $PausedUI/Panel/VBoxContainer/ResumeBtn

# Variabel untuk tower preview
var tower_preview_sprite: Sprite2D
var current_preview_tower_index: int = -1
var preview_range_radius: float = 0.0

# Menyimpan posisi awal UITower
var ui_tower_original_position: Vector2

func _ready():
	setup_spawner()
	setup_bgm()
	calculate_path_grid_positions()
	calculate_buildable_grid_positions()
	setup_enemy_spawn_system()
	setup_ui_tower()
	setup_tower_preview()
	update_ui()
	start_first_wave()
	
	resume_btn.pressed.connect(_on_resume_pressed)
	paused_ui.visible = false
	$PausedUI.process_mode = Node.PROCESS_MODE_WHEN_PAUSED

func setup_tower_preview():
	tower_preview_sprite = Sprite2D.new()
	add_child(tower_preview_sprite)
	tower_preview_sprite.modulate = Color(1.0, 1.0, 1.0, 0.8)  # Lebih terang untuk test
	tower_preview_sprite.visible = false
	tower_preview_sprite.z_index = 2  # Depanin sprite preview
	print("z index : ",tower_preview_sprite.z_index)

func _on_resume_pressed():
	$PausedUI.visible = false
	get_tree().paused=false

func setup_ui_tower():
	if ui_tower:
		ui_tower.visible = false
		# Simpan posisi awal UITower
		ui_tower_original_position = ui_tower.position
		
		# Connect signal hover untuk setiap button tower di UI
		connect_tower_hover_signals()

func connect_tower_hover_signals():
	if not ui_tower:
		return
	
	# Connect hover signals manual untuk setiap tower button
	# Tower 1 (Basic Tower)
	var tower1_path = "MainContainer/TowerList/TowerCard1/Tower1Button"
	if ui_tower.has_node(tower1_path):
		var tower1_btn = ui_tower.get_node(tower1_path)
		if tower1_btn is Button:
			tower1_btn.mouse_entered.connect(_on_tower_button_hover.bind(0))
			tower1_btn.mouse_exited.connect(_on_tower_button_exit_hover)
	var tower2_path = "MainContainer/TowerList/TowerCard3/Tower3Button"
	if ui_tower.has_node(tower2_path):
		var tower2_btn = ui_tower.get_node(tower2_path)
		if tower2_btn is Button:
			tower2_btn.mouse_entered.connect(_on_tower_button_hover.bind(1))
			tower2_btn.mouse_exited.connect(_on_tower_button_exit_hover)
	var tower3_path = "MainContainer/TowerList/TowerCard2/Tower2Button"
	if ui_tower.has_node(tower3_path):
		var tower3_btn = ui_tower.get_node(tower3_path)
		if tower3_btn is Button:
			tower3_btn.mouse_entered.connect(_on_tower_button_hover.bind(2))
			tower3_btn.mouse_exited.connect(_on_tower_button_exit_hover)

func _on_tower_button_hover(tower_index: int):
	if not awaiting_tower_selection:
		return
		
	show_tower_preview(tower_index)

func _on_tower_button_exit_hover():
	hide_tower_preview()

func show_tower_preview(tower_index: int):
	if tower_index < 0 or tower_index >= tower_scenes.size():
		return
		
	current_preview_tower_index = tower_index
	
	# Instantiate tower untuk mendapatkan sprite dan range
	var tower_scene = tower_scenes[tower_index]
	var temp_tower = tower_scene.instantiate()
	
	# Cari sprite di tower (asumsi tower punya Sprite2D sebagai child)
	var sprite_node = find_sprite_in_node(temp_tower)
	if sprite_node and sprite_node.texture:
		tower_preview_sprite.texture = sprite_node.texture
		tower_preview_sprite.position = GridManager.grid_to_world(pending_tower_grid_position)
		tower_preview_sprite.scale = Vector2(0.5, 0.5)  # Scale ke 0.612
		tower_preview_sprite.rotation_degrees = -90  # Rotate ke atas (menghadap atas)
		tower_preview_sprite.visible = true
	
	# Ambil range_radius dari tower untuk preview range
	if temp_tower.has_method("get") and temp_tower.get("range_radius") != null:
		preview_range_radius = temp_tower.range_radius
	elif temp_tower.has_method("get_range_radius"):
		preview_range_radius = temp_tower.get_range_radius()
	else:
		preview_range_radius = 100.0  # Default range jika tidak ditemukan
	
	# Hapus temporary tower
	temp_tower.queue_free()
	
	# Trigger redraw untuk menampilkan range circle
	queue_redraw()

func find_sprite_in_node(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node
	
	for child in node.get_children():
		var result = find_sprite_in_node(child)
		if result:
			return result
	
	return null

func hide_tower_preview():
	tower_preview_sprite.visible = false
	current_preview_tower_index = -1
	preview_range_radius = 0.0
	queue_redraw()  # Redraw untuk hide range circle

func setup_enemy_spawn_system():
	if enemy_scenes.size() == 0:
		return
	
	if enemy_spawn_weights.size() != enemy_scenes.size():
		enemy_spawn_weights.clear()
		for i in range(enemy_scenes.size()):
			enemy_spawn_weights.append(1.0)
	
	total_spawn_weight = 0.0
	for weight in enemy_spawn_weights:
		total_spawn_weight += weight

func get_random_enemy_scene() -> PackedScene:
	if enemy_scenes.size() == 0:
		return null
	
	if enemy_scenes.size() == 1:
		return enemy_scenes[0]
	
	var random_value = randf() * total_spawn_weight
	var current_weight = 0.0
	
	for i in range(enemy_scenes.size()):
		current_weight += enemy_spawn_weights[i]
		if random_value <= current_weight:
			return enemy_scenes[i]
	
	return enemy_scenes[0]

func calculate_buildable_grid_positions():
	buildable_grid_positions.clear()
	
	if not tilemap_node:
		return
	
	if buildable_layer >= tilemap_node.get_layers_count():
		return
	
	var tilemap_rect = tilemap_node.get_used_rect()
	
	for x in range(tilemap_rect.position.x, tilemap_rect.position.x + tilemap_rect.size.x):
		for y in range(tilemap_rect.position.y, tilemap_rect.position.y + tilemap_rect.size.y):
			var grid_pos = Vector2i(x, y)
			var source_id = tilemap_node.get_cell_source_id(buildable_layer, grid_pos)
			
			if buildable_source_ids.has(source_id):
				buildable_grid_positions.append(grid_pos)

func setup_spawner():
	spawn_timer = Timer.new()
	add_child(spawn_timer)
	spawn_timer.wait_time = enemy_spawn_interval
	spawn_timer.timeout.connect(spawn_enemy)
	
	wave_timer = Timer.new()
	add_child(wave_timer)
	wave_timer.wait_time = wave_cooldown
	wave_timer.timeout.connect(start_next_wave)
	wave_timer.one_shot = true

func setup_bgm():
	if background_music:
		bgm_player = AudioStreamPlayer.new()
		add_child(bgm_player)
		bgm_player.stream = background_music
		bgm_player.volume_db = bgm_volume
		bgm_player.autoplay = true
		bgm_player.bus = "Master"
		
		if background_music is AudioStreamOggVorbis:
			background_music.loop = true
		elif background_music is AudioStreamMP3:
			background_music.loop = true
		elif background_music is AudioStreamWAV:
			background_music.loop_mode = AudioStreamWAV.LOOP_FORWARD
		
		bgm_player.play()

func calculate_path_grid_positions():
	path_grid_positions.clear()
	
	if has_node("EnemyPath"):
		var path = $EnemyPath
		var curve = path.curve
		if curve:
			var path_length = curve.get_baked_length()
			var sample_distance = 16.0
			var samples = int(path_length / sample_distance)
			
			for i in range(samples + 1):
				var progress = float(i) / float(samples) if samples > 0 else 0.0
				var world_pos = path.global_position + curve.sample_baked(path_length * progress)
				var grid_pos = GridManager.world_to_grid(world_pos)
				
				if GridManager.is_valid_grid_position(grid_pos) and not path_grid_positions.has(grid_pos):
					path_grid_positions.append(grid_pos)

func start_first_wave():
	enemies_to_spawn = base_enemies_per_wave
	enemies_alive = 0
	wave_in_progress = true
	spawn_timer.start()
	update_ui()

func spawn_enemy():
	if enemies_to_spawn > 0:
		var enemy_scene = get_random_enemy_scene()
		if enemy_scene == null:
			return
		
		var enemy = enemy_scene.instantiate()
		var path_follow = PathFollow2D.new()
		$EnemyPath.add_child(path_follow)
		path_follow.add_child(enemy)
		enemy.path_follow = path_follow
		
		enemies_to_spawn -= 1
		enemies_alive += 1
	else:
		spawn_timer.stop()
		await get_tree().create_timer(5.0).timeout
		finish_wave()

func _on_enemy_died():
	enemies_alive -= 1

func finish_wave():
	wave_in_progress = false
	
	if wave_number >= max_waves:
		game_completed = true
		return
	
	start_next_wave()

func start_next_wave():
	if game_completed:
		return
	
	await get_tree().create_timer(wave_cooldown).timeout
	
	wave_number += 1
	
	enemies_to_spawn = base_enemies_per_wave + (wave_number - 1) * enemy_increase_per_wave
	enemies_alive = 0
	wave_in_progress = true
	
	spawn_timer.wait_time = max(0.5, enemy_spawn_interval - (wave_number - 1) * wave_speed_increase)
	spawn_timer.start()
	
	update_ui()

func _input(event):
	if awaiting_tower_selection:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos = get_global_mouse_position()
			handle_tile_click(mouse_pos)

func is_mouse_over_ui(mouse_pos: Vector2) -> bool:
	if has_node("UI"):
		var ui_node = $UI
		if ui_node is Control:
			var ui_rect = ui_node.get_global_rect()
			if ui_rect.has_point(mouse_pos):
				return true
	
	var viewport = get_viewport()
	if viewport:
		var control_at_pos = viewport.gui_find_control(mouse_pos)
		if control_at_pos:
			return true
	
	return false

func handle_tile_click(mouse_pos: Vector2):
	var grid_pos = GridManager.world_to_grid(mouse_pos)
	
	if can_place_tower_at_grid(grid_pos):
		# Tampilkan border grid ketika grid valid diklik
		selected_grid_position = grid_pos
		show_grid_border = true
		queue_redraw()  # Redraw untuk menampilkan border
		
		show_tower_selection(grid_pos)

func show_tower_selection(grid_pos: Vector2i):
	if tower_scenes.size() == 0:
		return
	
	if tower_scenes.size() == 1:
		var cost = tower_costs[0] if tower_costs.size() > 0 else 50
		if GameManager.money >= cost:
			place_tower_at_grid(grid_pos, 0)
		return
	
	pending_tower_grid_position = grid_pos
	awaiting_tower_selection = true
	
	if ui_tower:
		# Reset posisi ke posisi awal sebelum menampilkan
		ui_tower.position = ui_tower_original_position
		
		var viewport_width = get_viewport().get_visible_rect().size.x
		# Set posisi awal di luar layar (kanan)
		ui_tower.position.x = viewport_width
		ui_tower.visible = true
		
		# Animasi slide masuk dari kanan ke posisi awal
		var tween = create_tween()
		tween.tween_property(ui_tower, "position", ui_tower_original_position, 0.3)
		tween.tween_callback(func(): pass)

func _on_tower_selected(tower_index: int):
	awaiting_tower_selection = false
	hide_tower_preview()  # Sembunyikan preview saat tower dipilih
	
	if ui_tower:
		# Slide keluar ke kanan dan hide
		slide_out_ui_tower()
	
	if tower_index >= 0 and tower_index < tower_scenes.size():
		var cost = tower_costs[tower_index] if tower_index < tower_costs.size() else 50
		
		if GameManager.money >= cost:
			place_tower_at_grid(pending_tower_grid_position, tower_index)

func _on_tower_selection_cancelled():
	awaiting_tower_selection = false
	hide_tower_preview()  # Sembunyikan preview saat cancel
	
	# Sembunyikan border grid ketika cancel
	show_grid_border = false
	queue_redraw()
	
	if ui_tower:
		# Slide keluar ke kanan dan hide
		slide_out_ui_tower()

# Fungsi untuk mengatur animasi slide out UITower
func slide_out_ui_tower():
	if not ui_tower:
		return
		
	var tween = create_tween()
	var viewport_width = get_viewport().get_visible_rect().size.x
	var target_pos = ui_tower_original_position
	target_pos.x = viewport_width  # Slide keluar ke kanan layar
	
	tween.tween_property(ui_tower, "position", target_pos, 0.2)
	tween.tween_callback(func(): 
		ui_tower.visible = false
		# Reset posisi ke posisi awal setelah di-hide
		ui_tower.position = ui_tower_original_position
	)

func can_place_tower_at_grid(grid_pos: Vector2i) -> bool:
	if not GridManager.is_valid_tower_position(grid_pos, occupied_grid_positions):
		return false
	
	if path_grid_positions.has(grid_pos):
		return false
	
	if not is_buildable_tile(grid_pos):
		return false
	
	return true

func is_buildable_tile(grid_pos: Vector2i) -> bool:
	if not tilemap_node:
		return true
	
	if buildable_layer >= tilemap_node.get_layers_count():
		return false
	
	var source_id = tilemap_node.get_cell_source_id(buildable_layer, grid_pos)
	var can_build = buildable_source_ids.has(source_id)
	
	return can_build

func place_tower_at_grid(grid_pos: Vector2i, tower_index: int = 0):
	if tower_index < 0 or tower_index >= tower_scenes.size():
		return
	
	var world_pos = GridManager.grid_to_world(grid_pos)
	var tower_scene = tower_scenes[tower_index]
	var cost = tower_costs[tower_index] if tower_index < tower_costs.size() else 50
	
	var tower = tower_scene.instantiate()
	add_child(tower)
	tower.global_position = world_pos
	
	occupied_grid_positions.append(grid_pos)
	
	GameManager.spend_money(cost)
	
	# Sembunyikan border grid ketika tower sudah dibangun
	show_grid_border = false
	queue_redraw()
	
	update_ui()

func remove_tower_at_grid(grid_pos: Vector2i):
	occupied_grid_positions.erase(grid_pos)

func update_ui():
	if has_node("CanvasLayer/UI/HBoxContainer/WaveContainer/WaveLabel"):
		if game_completed:
			wave_label.text = "VICTORY!"
		else:
			wave_label.text = "Wave: " + str(wave_number) + "/" + str(max_waves)
	
	if has_node("UI/MoneyLabel"):
		$UI/MoneyLabel.text = "Money: $" + str(GameManager.money)

func _draw():
	if Engine.is_editor_hint():
		return
	
	var grid_color = Color.WHITE
	grid_color.a = 0.0
	
	for x in range(GridManager.GRID_WIDTH + 1):
		var start_pos = Vector2(x * GridManager.TILE_SIZE, 0)
		var end_pos = Vector2(x * GridManager.TILE_SIZE, GridManager.GRID_HEIGHT * GridManager.TILE_SIZE)
		draw_line(start_pos, end_pos, grid_color)
	
	for y in range(GridManager.GRID_HEIGHT + 1):
		var start_pos = Vector2(0, y * GridManager.TILE_SIZE)
		var end_pos = Vector2(GridManager.GRID_WIDTH * GridManager.TILE_SIZE, y * GridManager.TILE_SIZE)
		draw_line(start_pos, end_pos, grid_color)
	
	for grid_pos in occupied_grid_positions:
		var world_pos = GridManager.grid_to_world(grid_pos)
		draw_circle(world_pos, 8, Color.RED)
	
	if show_buildable_debug:
		for grid_pos in buildable_grid_positions:
			if not occupied_grid_positions.has(grid_pos) and not path_grid_positions.has(grid_pos):
				var world_pos = GridManager.grid_to_world(grid_pos)
				draw_circle(world_pos, 6, Color(0.0, 1.0, 0.0, 0.3))
	

	
	# Draw border grid putih ketika grid valid diklik
	if show_grid_border:
		var world_pos = GridManager.grid_to_world(selected_grid_position)
		var half_tile = GridManager.TILE_SIZE / 2.0
		
		# Buat rectangle untuk border
		var rect_pos = world_pos - Vector2(half_tile, half_tile)
		var rect_size = Vector2(GridManager.TILE_SIZE, GridManager.TILE_SIZE)
		var border_rect = Rect2(rect_pos, rect_size)
		
		# Draw border putih dengan thickness 2 pixel
		var border_color = Color(255,255,255,220)
		var thickness = 2.0
		
		# Draw 4 sisi border
		# Top
		draw_line(border_rect.position, 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y), 
				 border_color, thickness)
		# Bottom
		draw_line(Vector2(border_rect.position.x, border_rect.position.y + border_rect.size.y), 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
		# Left
		draw_line(border_rect.position, 
				 Vector2(border_rect.position.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
		# Right
		draw_line(Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y), 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
	
	# Draw tower range preview jika ada tower yang di-hover - PINDAH KE AKHIR BIAR PALING DEPAN
	if awaiting_tower_selection and current_preview_tower_index >= 0 and preview_range_radius > 0:
		var world_pos = GridManager.grid_to_world(pending_tower_grid_position)
		var range_color = Color(0.0, 0.2, 0.2, 0.3)  # Hijau transparan
		draw_circle(world_pos, preview_range_radius, range_color)
		

func _on_paused_button_pressed() -> void:
	paused_ui.visible=true
	get_tree().paused=true

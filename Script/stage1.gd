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
@onready var resume_btn: Button = $PausedUI/Panel/VBoxContainer/ResumeBtn
@onready var exit_btn: Button = $PausedUI/Panel/VBoxContainer/ExitBtn

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
var towers_at_grid: Dictionary = {}
var pending_tower_grid_position: Vector2i
var awaiting_tower_selection: bool = false
var selected_grid_position: Vector2i
var show_grid_border: bool = false
var bgm_player: AudioStreamPlayer
var total_spawn_weight: float = 0.0
var tower_preview_sprite: Sprite2D
var current_preview_tower_index: int = -1
var preview_range_radius: float = 0.0
var ui_tower_original_position: Vector2
var selected_tower_ui: CanvasLayer
var currently_selected_tower_grid: Vector2i
var currently_selected_tower_instance: Node

# NEW: Dynamic tower button system
var tower_buttons: Array[Button] = []
var tower_button_containers: Array[Control] = []

func _ready():
	setup_spawner()
	setup_bgm()
	calculate_path_grid_positions()
	calculate_buildable_grid_positions()
	setup_enemy_spawn_system()
	setup_ui_tower()
	setup_tower_preview()
	setup_selected_tower_ui()
	setup_dynamic_tower_buttons()  # NEW: Setup dynamic buttons
	update_ui()
	start_first_wave()
	resume_btn.pressed.connect(_on_resume_pressed)
	paused_ui.visible = false
	$PausedUI.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	exit_btn.pressed.connect(_on_exit_button)

# NEW: Dynamic tower button setup system
func setup_dynamic_tower_buttons():
	if not ui_tower:
		print("UI Tower not found!")
		return
	
	# Clear existing button references
	tower_buttons.clear()
	tower_button_containers.clear()
	
	# Find all tower buttons dynamically
	find_tower_buttons_recursive(ui_tower)
	
	print("Found ", tower_buttons.size(), " tower buttons")
	
	# Connect buttons to their respective tower indices
	for i in range(tower_buttons.size()):
		var button = tower_buttons[i]
		var container = tower_button_containers[i]
		
		if button and is_instance_valid(button):
			# Connect button press
			if button.pressed.is_connected(_on_dynamic_tower_button_pressed):
				button.pressed.disconnect(_on_dynamic_tower_button_pressed)
			button.pressed.connect(_on_dynamic_tower_button_pressed.bind(i))
			
			# Connect hover events
			if button.mouse_entered.is_connected(_on_tower_button_hover):
				button.mouse_entered.disconnect(_on_tower_button_hover)
			if button.mouse_exited.is_connected(_on_tower_button_exit_hover):
				button.mouse_exited.disconnect(_on_tower_button_exit_hover)
			
			button.mouse_entered.connect(_on_tower_button_hover.bind(i))
			button.mouse_exited.connect(_on_tower_button_exit_hover)
			
			# Update button info if possible
			update_tower_button_info(i, button, container)
			
			print("Connected tower button ", i, ": ", button.name)

# NEW: Recursively find tower buttons
func find_tower_buttons_recursive(node: Node):
	# Check if current node is a button with tower-related name
	if node is Button:
		var button_name = node.name.to_lower()
		if "tower" in button_name and ("button" in button_name or "btn" in button_name):
			tower_buttons.append(node)
			tower_button_containers.append(node.get_parent())
			return
	
	# Check children
	for child in node.get_children():
		find_tower_buttons_recursive(child)

# NEW: Update tower button display info
func update_tower_button_info(tower_index: int, button: Button, container: Control):
	if tower_index >= tower_scenes.size() or tower_index >= tower_names.size() or tower_index >= tower_costs.size():
		# Hide button if no corresponding tower data
		if container:
			container.visible = false
		return
	
	# Update button text if it's just a text button
	
	# Try to find and update labels in the container
	if container:
		update_tower_card_info(container, tower_index)

# NEW: Update tower card information
func update_tower_card_info(container: Control, tower_index: int):
	# Find and update various labels in the tower card
	var labels_to_update = {
		"name": tower_names[tower_index],
		"cost": "$" + str(tower_costs[tower_index]),
		"price": "$" + str(tower_costs[tower_index])
	}
	
	update_labels_recursive(container, labels_to_update, tower_index)

func update_labels_recursive(node: Node, labels_data: Dictionary, tower_index: int):
	if node is Label:
		var label_name = node.name.to_lower()
		
		# Update based on label name
		for key in labels_data.keys():
			if key in label_name:
				node.text = labels_data[key]
				return
		
		# Try to get tower stats
		if "damage" in label_name:
			var damage = get_tower_stat(tower_index, "damage")
			if damage != null:
				node.text = "DMG: " + str(damage)
		elif "range" in label_name:
			var range_val = get_tower_stat(tower_index, "range_radius")
			if range_val != null:
				node.text = "Range: " + str(range_val)
		elif "speed" in label_name or "rate" in label_name:
			var fire_rate = get_tower_stat(tower_index, "fire_rate")
			if fire_rate != null:
				node.text = "Speed: " + str(fire_rate)
	
	# Check children
	for child in node.get_children():
		update_labels_recursive(child, labels_data, tower_index)

# NEW: Get tower stat from scene
func get_tower_stat(tower_index: int, stat_name: String):
	if tower_index >= tower_scenes.size():
		return null
	
	var tower_scene = tower_scenes[tower_index]
	if not tower_scene:
		return null
	
	# Create temporary instance to get stats
	var temp_tower = tower_scene.instantiate()
	var stat_value = null
	
	if temp_tower.has_method("get") and temp_tower.get(stat_name) != null:
		stat_value = temp_tower.get(stat_name)
	
	temp_tower.queue_free()
	return stat_value

# NEW: Dynamic tower button handler
func _on_dynamic_tower_button_pressed(tower_index: int):
	print("Tower button pressed: ", tower_index)
	
	if not awaiting_tower_selection:
		print("Not awaiting tower selection!")
		return
	
	if tower_index >= tower_scenes.size():
		print("Invalid tower index: ", tower_index)
		return
	
	# Check if player has enough money
	var cost = tower_costs[tower_index] if tower_index < tower_costs.size() else 50
	if GameManager.money < cost:
		print("Not enough money! Need: ", cost, " Have: ", GameManager.money)
		return
	
	print("Placing tower ", tower_index, " at position ", pending_tower_grid_position)
	
	# Place the tower
	_on_tower_selected(tower_index)

func setup_selected_tower_ui():
	pass

func show_selected_tower_info(tower_instance: Node, grid_pos: Vector2i):
	if not has_node("SelectedTowerUI"):
		return
	
	if not selected_tower_ui:
		selected_tower_ui = $SelectedTowerUI
		selected_tower_ui.visible = false
		if selected_tower_ui.has_node("Control/SellTowerButton"):
			var sell_button = selected_tower_ui.get_node("Control/SellTowerButton")
			if sell_button is Button:
				if sell_button.pressed.is_connected(_on_sell_tower_button_pressed):
					sell_button.pressed.disconnect(_on_sell_tower_button_pressed)
				sell_button.pressed.connect(_on_sell_tower_button_pressed)
	
	currently_selected_tower_grid = grid_pos
	currently_selected_tower_instance = tower_instance
	
	var tower_index = get_tower_index_from_instance(tower_instance)
	var tower_name = "Unknown Tower"
	if tower_index >= 0 and tower_index < tower_names.size():
		tower_name = tower_names[tower_index]
	
	var damage = str(tower_instance.damage) if "damage" in tower_instance else "N/A"
	var range_text = str(tower_instance.range_radius) if "range_radius" in tower_instance else "N/A"
	var attack_speed = str(tower_instance.fire_rate) if "fire_rate" in tower_instance else "N/A"
	
	if selected_tower_ui.has_node("Control/TowerNameLabel"):
		selected_tower_ui.get_node("Control/TowerNameLabel").text = tower_name
	if selected_tower_ui.has_node("Control/DamageLabel"):
		selected_tower_ui.get_node("Control/DamageLabel").text = "Damage: " + damage
	if selected_tower_ui.has_node("Control/RangeLabel"):
		selected_tower_ui.get_node("Control/RangeLabel").text = "Range: " + range_text
	if selected_tower_ui.has_node("Control/AttackSpeedLabel"):
		selected_tower_ui.get_node("Control/AttackSpeedLabel").text = "Attack Speed: " + attack_speed
	if selected_tower_ui.has_node("GridPosLabel"):
		selected_tower_ui.get_node("GridPosLabel").text = "Position: " + str(grid_pos)
	
	selected_tower_ui.visible = true

func _on_sell_tower_button_pressed():
	sell_tower(currently_selected_tower_grid, currently_selected_tower_instance)

func sell_tower(grid_pos: Vector2i, tower_instance: Node):
	if not is_instance_valid(tower_instance):
		return
	
	var tower_index = get_tower_index_from_instance(tower_instance)
	var sell_price = 0
	
	if tower_index >= 0 and tower_index < tower_costs.size():
		sell_price = int(tower_costs[tower_index] * 0.7)
	else:
		sell_price = 35
	
	GameManager.add_money(sell_price)
	
	# CRITICAL: Cleanup effects FIRST - ini akan langsung hapus semua partikel milik tower ini
	if tower_instance.has_method("cleanup_effects"):
		tower_instance.cleanup_effects()
	
	# Update data structures
	if towers_at_grid.has(grid_pos):
		towers_at_grid.erase(grid_pos)
	
	occupied_grid_positions.erase(grid_pos)
	
	# Langsung hapus tower - karena partikel sudah dibersihkan
	if is_instance_valid(tower_instance):
		tower_instance.queue_free()
	
	# UI cleanup
	if selected_tower_ui:
		selected_tower_ui.visible = false
	
	currently_selected_tower_grid = Vector2i()
	currently_selected_tower_instance = null
	update_ui()
	queue_redraw()

func get_tower_index_from_instance(tower_instance: Node) -> int:
	var scene_path = tower_instance.scene_file_path
	for i in range(tower_scenes.size()):
		if tower_scenes[i] and tower_scenes[i].resource_path == scene_path:
			return i
	return -1

func setup_tower_preview():
	tower_preview_sprite = Sprite2D.new()
	add_child(tower_preview_sprite)
	tower_preview_sprite.modulate = Color(1.0, 1.0, 1.0, 0.8)
	tower_preview_sprite.visible = false
	tower_preview_sprite.z_index = 2

func _on_resume_pressed():
	$PausedUI.visible = false
	get_tree().paused = false

func _on_exit_button():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func setup_ui_tower():
	if ui_tower:
		ui_tower.visible = false
		ui_tower_original_position = ui_tower.position

# REMOVED: Manual tower hover connection - now handled dynamically

func _on_tower_button_hover(tower_index: int):
	if not awaiting_tower_selection:
		return
	print("Hovering over tower button: ", tower_index)
	show_tower_preview(tower_index)

func _on_tower_button_exit_hover():
	hide_tower_preview()

func show_tower_preview(tower_index: int):
	if tower_index < 0 or tower_index >= tower_scenes.size():
		return
	
	current_preview_tower_index = tower_index
	var tower_scene = tower_scenes[tower_index]
	var temp_tower = tower_scene.instantiate()
	
	var sprite_node = find_sprite_in_node(temp_tower)
	if sprite_node and sprite_node.texture:
		tower_preview_sprite.texture = sprite_node.texture
		tower_preview_sprite.position = GridManager.grid_to_world(pending_tower_grid_position)
		tower_preview_sprite.scale = Vector2(0.5, 0.5)
		tower_preview_sprite.rotation_degrees = -90
		tower_preview_sprite.visible = true
	
	if temp_tower.has_method("get") and temp_tower.get("range_radius") != null:
		preview_range_radius = temp_tower.range_radius
	elif temp_tower.has_method("get_range_radius"):
		preview_range_radius = temp_tower.get_range_radius()
	else:
		preview_range_radius = 100.0
	
	temp_tower.queue_free()
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
	queue_redraw()

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
	if not tilemap_node or buildable_layer >= tilemap_node.get_layers_count():
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
	
	if towers_at_grid.has(grid_pos):
		var tower_instance = towers_at_grid[grid_pos]
		if tower_instance and is_instance_valid(tower_instance):
			show_selected_tower_info(tower_instance, grid_pos)
			return
	
	if can_place_tower_at_grid(grid_pos):
		selected_grid_position = grid_pos
		show_grid_border = true
		queue_redraw()
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
	print("Awaiting tower selection for position: ", grid_pos)
	
	if ui_tower:
		if selected_tower_ui:
			selected_tower_ui.visible = false
		ui_tower.position = ui_tower_original_position
		
		var viewport_width = get_viewport().get_visible_rect().size.x
		ui_tower.position.x = viewport_width
		ui_tower.visible = true
		
		var tween = create_tween()
		tween.tween_property(ui_tower, "position", ui_tower_original_position, 0.3)
		tween.tween_callback(func(): pass)

func _on_tower_selected(tower_index: int):
	awaiting_tower_selection = false
	hide_tower_preview()
	
	if ui_tower:
		slide_out_ui_tower()
	
	if tower_index >= 0 and tower_index < tower_scenes.size():
		var cost = tower_costs[tower_index] if tower_index < tower_costs.size() else 50
		if GameManager.money >= cost:
			place_tower_at_grid(pending_tower_grid_position, tower_index)

func _on_tower_selection_cancelled():
	awaiting_tower_selection = false
	hide_tower_preview()
	show_grid_border = false
	queue_redraw()
	
	if ui_tower:
		slide_out_ui_tower()

func slide_out_ui_tower():
	if not ui_tower:
		return
	
	var tween = create_tween()
	var viewport_width = get_viewport().get_visible_rect().size.x
	var target_pos = ui_tower_original_position
	target_pos.x = viewport_width
	
	tween.tween_property(ui_tower, "position", target_pos, 0.2)
	tween.tween_callback(func(): 
		ui_tower.visible = false
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
	if not tilemap_node or buildable_layer >= tilemap_node.get_layers_count():
		return false
	
	var source_id = tilemap_node.get_cell_source_id(buildable_layer, grid_pos)
	return buildable_source_ids.has(source_id)

func place_tower_at_grid(grid_pos: Vector2i, tower_index: int = 0):
	if tower_index < 0 or tower_index >= tower_scenes.size():
		print("Invalid tower index for placement: ", tower_index)
		return
	
	var world_pos = GridManager.grid_to_world(grid_pos)
	var tower_scene = tower_scenes[tower_index]
	var cost = tower_costs[tower_index] if tower_index < tower_costs.size() else 50
	
	print("Placing tower ", tower_index, " at ", world_pos, " cost: ", cost)
	
	var tower = tower_scene.instantiate()
	add_child(tower)
	tower.global_position = world_pos
	
	towers_at_grid[grid_pos] = tower
	occupied_grid_positions.append(grid_pos)
	GameManager.spend_money(cost)
	show_grid_border = false
	queue_redraw()
	update_ui()
	
	print("Tower placed successfully!")

func remove_tower_at_grid(grid_pos: Vector2i):
	if towers_at_grid.has(grid_pos):
		var tower = towers_at_grid[grid_pos]
		if is_instance_valid(tower):
			# IMPROVED: Call cleanup before removing
			if tower.has_method("cleanup_effects"):
				tower.cleanup_effects()
			tower.queue_free()
		towers_at_grid.erase(grid_pos)
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
	
	if show_buildable_debug:
		for grid_pos in buildable_grid_positions:
			if not occupied_grid_positions.has(grid_pos) and not path_grid_positions.has(grid_pos):
				var world_pos = GridManager.grid_to_world(grid_pos)
				draw_circle(world_pos, 6, Color(0.0, 1.0, 0.0, 0.3))
	
	if show_grid_border:
		var world_pos = GridManager.grid_to_world(selected_grid_position)
		var half_tile = GridManager.TILE_SIZE / 2.0
		var rect_pos = world_pos - Vector2(half_tile, half_tile)
		var rect_size = Vector2(GridManager.TILE_SIZE, GridManager.TILE_SIZE)
		var border_rect = Rect2(rect_pos, rect_size)
		var border_color = Color(1.0, 1.0, 1.0, 0.8)
		var thickness = 2.0
		
		draw_line(border_rect.position, 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y), 
				 border_color, thickness)
		draw_line(Vector2(border_rect.position.x, border_rect.position.y + border_rect.size.y), 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
		draw_line(border_rect.position, 
				 Vector2(border_rect.position.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
		draw_line(Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y), 
				 Vector2(border_rect.position.x + border_rect.size.x, border_rect.position.y + border_rect.size.y), 
				 border_color, thickness)
	
	if awaiting_tower_selection and current_preview_tower_index >= 0 and preview_range_radius > 0:
		var world_pos = GridManager.grid_to_world(pending_tower_grid_position)
		var range_color = Color(0.0, 0.2, 0.2, 0.3)
		draw_circle(world_pos, preview_range_radius, range_color)

func _on_paused_button_pressed() -> void:
	paused_ui.visible = true
	get_tree().paused = true

func _on_selectedUI_close_button_pressed() -> void:
	$SelectedTowerUI.visible = false

extends Control

signal tower_selected(tower_index: int)
signal tower_selection_cancelled


@onready var button1: Button = $MainContainer/TowerList/TowerCard1/Tower1Button
@onready var cancel_button: Button = $"MainContainer/Cancel Button"
@onready var button2: Button = $MainContainer/TowerList/TowerCard3/Tower3Button
@onready var button3: Button = $MainContainer/TowerList/TowerCard2/Tower2Button

var main_scene: Node2D
var tower_costs: Array[int] = []
var tower_names: Array[String] = []

func _ready():
	print("Button1 found: ", button1 != null)
	if button1:
		print("button1 mouse filter : ",button1.mouse_filter)
		print("button1 disabled : ",button1.disabled)
	# Hubungkan signal dari button-button
	if button1:
		button1.pressed.connect(_on_button1_pressed)
	if button2:
		button2.pressed.connect(_on_button2_pressed)
	if button3:
		button3.pressed.connect(_on_button3_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_button_pressed)
	
	# Cari main scene (parent yang memiliki script tower defense)
	find_main_scene()
	
	# Update button text dan status
	update_buttons()

func find_main_scene():
	var current = get_parent()
	while current != null:
		if current.has_method("_on_tower_selected"):
			main_scene = current
			break
		current = current.get_parent()
	
	# Koneksi signal ke main scene
	if main_scene:
		tower_selected.connect(main_scene._on_tower_selected)
		tower_selection_cancelled.connect(main_scene._on_tower_selection_cancelled)

func update_buttons():
	if not main_scene:
		return
	
	# Ambil data tower dari main scene
	if main_scene.has_method("get") and main_scene.get("tower_costs"):
		tower_costs = main_scene.tower_costs
	if main_scene.has_method("get") and main_scene.get("tower_names"):
		tower_names = main_scene.tower_names
	
	# Update button 1
	if button1:
		if tower_names.size() > 0 and tower_costs.size() > 0:
			
			button1.disabled = GameManager.money < tower_costs[0]
		else:
			
			button1.disabled = GameManager.money < 50
	
	# Update button 2
	if button2:
		if tower_names.size() > 1 and tower_costs.size() > 1:
			
			button2.disabled = GameManager.money < tower_costs[1]
			button2.visible = true
		else:
			button2.visible = false
	
	# Update button 3
	if button3:
		if tower_names.size() > 2 and tower_costs.size() > 2:
			
			button3.disabled = GameManager.money < tower_costs[2]
			button3.visible = true
		else:
			button3.visible = false

func _on_button1_pressed():
	print("Button1 Pressed")
	tower_selected.emit(0)

func _on_button2_pressed():
	tower_selected.emit(1)

func _on_button3_pressed():
	tower_selected.emit(2)

func _on_cancel_button_pressed():
	tower_selection_cancelled.emit()

func _on_visibility_changed():
	if visible:
		update_buttons()

# Fungsi untuk update button ketika money berubah
func refresh_buttons():
	update_buttons()

# Fungsi untuk set position UI relative ke mouse atau grid position
func show_at_position(world_pos: Vector2):
	# Convert world position ke screen position
	var screen_pos = get_viewport().get_camera_2d().to_screen_space_transform() * world_pos
	
	# Adjust position agar tidak keluar dari screen
	var viewport_size = get_viewport().get_visible_rect().size
	var ui_size = size
	
	screen_pos.x = clamp(screen_pos.x, 0, viewport_size.x - ui_size.x)
	screen_pos.y = clamp(screen_pos.y, 0, viewport_size.y - ui_size.y)
	
	position = screen_pos

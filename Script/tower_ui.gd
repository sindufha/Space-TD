extends Control

@onready var buttons_container = $Background/ButtonsContainer
@onready var cancel_button = $Background/CancelButton

var main_scene: Node2D

func _ready():
	visible = false
	
	# PENTING: Add ke group untuk blocking mouse input
	add_to_group("ui_blocking")
	
	# PERBAIKAN: Set mouse filter untuk memastikan UI dapat di-interact
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# DEBUG: Check UI nodes
	print("=== DEBUGGING UI NODES ===")
	print("buttons_container: ", buttons_container)
	print("cancel_button: ", cancel_button)
	print("mouse_filter: ", mouse_filter)
	print("UI rect: ", get_rect())
	
	# Setup cancel button
	if cancel_button:
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
		cancel_button.pressed.connect(_on_cancel_pressed)
		print("✅ Cancel button connected")
	else:
		print("❌ Cancel button not found!")
	
	# Find main scene - delay untuk memastikan tree sudah ready
	call_deferred("find_main_scene")

func find_main_scene():
	# Method 1: Try current scene first
	main_scene = get_tree().current_scene
	if main_scene and main_scene.has_method("get_tower_data"):
		print("✅ Main scene found via current_scene: ", main_scene.name)
		connect_to_main_scene()
		return
	
	# Method 2: Search up the parent tree
	var current = get_parent()
	while current != null:
		if current.has_method("get_tower_data"):
			main_scene = current
			print("✅ Main scene found via parent search: ", main_scene.name)
			connect_to_main_scene()
			return
		current = current.get_parent()
	
	# Method 3: Search by name or type
	var root = get_tree().current_scene
	if root and (root.name.contains("Main") or root.name.contains("Game")):
		main_scene = root
		print("✅ Main scene found by name: ", main_scene.name)
		connect_to_main_scene()
		return
	
	print("❌ Main scene not found!")

func connect_to_main_scene():
	if not main_scene or not main_scene.has_method("get_tower_data"):
		print("❌ Cannot connect to main scene - invalid reference")
		return
		
	# Connect signals dengan error handling
	if main_scene.has_signal("tower_selection_requested"):
		if not main_scene.tower_selection_requested.is_connected(_on_tower_selection_requested):
			main_scene.tower_selection_requested.connect(_on_tower_selection_requested)
	
	if main_scene.has_signal("tower_selection_cancelled"):
		if not main_scene.tower_selection_cancelled.is_connected(_on_tower_selection_cancelled):
			main_scene.tower_selection_cancelled.connect(_on_tower_selection_cancelled)
	
	if main_scene.has_signal("money_changed"):
		if not main_scene.money_changed.is_connected(_on_money_changed):
			main_scene.money_changed.connect(_on_money_changed)
	
	print("✅ Tower UI connected to: ", main_scene.name)

func _on_tower_selection_requested(grid_pos: Vector2i):
	print("🎯 Tower selection requested at: ", grid_pos)
	update_buttons()
	show_ui()

func _on_tower_selection_cancelled():
	print("🚫 Tower selection cancelled")
	hide_ui()

func _on_money_changed(new_amount: int):
	print("💰 Money changed to: ", new_amount)
	# Update button states ketika money berubah
	if visible:
		update_buttons()

func show_ui():
	print("📋 Showing Tower Selection UI")
	
	# PERBAIKAN: Pastikan UI properties benar
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Set Z-index tinggi untuk memastikan UI di atas
	z_index = 100
	
	# DEBUG: Check UI state
	print("=== UI SHOW DEBUG ===")
	print("UI visible: ", visible)
	print("UI modulate: ", modulate)
	print("UI mouse_filter: ", mouse_filter)
	print("UI z_index: ", z_index)
	print("UI global_rect: ", get_global_rect())
	
	# Smooth show animation
	var tween = create_tween()
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.8, 0.8)
	tween.parallel().tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)
	tween.parallel().tween_property(self, "scale", Vector2(1, 1), 0.2)
	tween.tween_callback(func():
		print("✅ UI show animation complete")
	)

func hide_ui():
	print("📋 Hiding Tower Selection UI")
	
	# Smooth hide animation
	var tween = create_tween()
	tween.parallel().tween_property(self, "modulate", Color(1, 1, 1, 0), 0.15)
	tween.parallel().tween_property(self, "scale", Vector2(0.8, 0.8), 0.15)
	tween.tween_callback(func(): 
		visible = false
		scale = Vector2(1, 1)  # Reset scale
		print("✅ UI hidden")
	)

func update_buttons():
	if not main_scene:
		print("❌ main_scene is null in update_buttons")
		return
	
	var tower_data = main_scene.get_tower_data()
	print("=== BUTTON UPDATE DEBUG ===")
	print("Tower data size: ", tower_data.size())
	print("Buttons container children: ", buttons_container.get_child_count())
	
	# Clear existing connections dan update buttons
	for i in range(buttons_container.get_child_count()):
		var button = buttons_container.get_child(i) as Button
		
		if button and i < tower_data.size():
			var data = tower_data[i]
			
			# PERBAIKAN: Pastikan button properties benar
			button.mouse_filter = Control.MOUSE_FILTER_STOP
			button.focus_mode = Control.FOCUS_ALL
			
			# Update button text dan state
			button.text = data.name + " - $" + str(data.cost)
			button.disabled = not data.can_afford
			
			print("Button ", i, " - Text: ", button.text, " Disabled: ", button.disabled, " Filter: ", button.mouse_filter)
			
			# PERBAIKAN: Disconnect semua connections sebelum connect yang baru
			var connections = button.pressed.get_connections()
			for connection in connections:
				button.pressed.disconnect(connection.callable)
			
			# Connect dengan tower index
			button.pressed.connect(_on_tower_button_pressed.bind(data.index))
			print("✅ Button ", i, " connected with index: ", data.index)
			
			# Visual feedback untuk affordable/not affordable
			if data.can_afford:
				button.modulate = Color.WHITE
				button.self_modulate = Color.WHITE
			else:
				button.modulate = Color(0.6, 0.6, 0.6)
				button.self_modulate = Color(0.6, 0.6, 0.6)

# PERBAIKAN: Override _gui_input untuk memastikan input handling
func _gui_input(event):
	print("🎯 UI _gui_input called: ", event)
	if event is InputEventMouseButton and event.pressed:
		print("🎯 Mouse button in UI: ", event.button_index, " pressed: ", event.pressed)
		# PENTING: Consume the event to prevent it from going to main scene
		get_viewport().set_input_as_handled()
		accept_event()

# PERBAIKAN: Tambah _unhandled_input untuk catch input yang belum di-handle
func _unhandled_input(event):
	if not visible:
		return
		
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_global_mouse_position()
		var ui_rect = get_global_rect()
		
		print("=== UI UNHANDLED INPUT DEBUG ===")
		print("Mouse pos: ", mouse_pos)
		print("UI rect: ", ui_rect)
		print("Contains point: ", ui_rect.has_point(mouse_pos))
		
		if ui_rect.has_point(mouse_pos):
			print("🎯 Mouse in UI bounds - handling input")
			get_viewport().set_input_as_handled()

func _on_tower_button_pressed(tower_index: int):
	print("🎯 Tower button pressed with index: ", tower_index)
	
	if main_scene and main_scene.has_method("build_tower"):
		print("✅ Calling build_tower on main_scene")
		main_scene.build_tower(tower_index)
	else:
		print("❌ Error: main_scene is null or doesn't have build_tower method!")
		# Try to find main scene again
		find_main_scene()

func _on_cancel_pressed():
	print("🚫 Cancel button pressed!")
	
	if main_scene and main_scene.has_method("cancel_tower_selection"):
		print("✅ Calling cancel_tower_selection on main_scene")
		main_scene.cancel_tower_selection()
	else:
		print("❌ Error: main_scene is null or doesn't have cancel_tower_selection method!")
		# Try to find main scene again
		find_main_scene()

# PERBAIKAN: Override _input dengan priority tinggi
func _input(event):
	if not visible:
		return
		
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_global_mouse_position()
		var ui_rect = get_global_rect()
		
		if ui_rect.has_point(mouse_pos):
			print("🎯 UI intercepted input - stopping propagation")
			get_viewport().set_input_as_handled()

# TAMBAHAN: Function untuk debugging UI state
func debug_ui_state():
	print("=== UI DEBUG STATE ===")
	print("Visible: ", visible)
	print("Mouse filter: ", mouse_filter)
	print("Z-index: ", z_index)
	print("Global rect: ", get_global_rect())
	print("In ui_blocking group: ", is_in_group("ui_blocking"))
	
	if buttons_container:
		print("Buttons container children: ", buttons_container.get_child_count())
		for i in range(buttons_container.get_child_count()):
			var button = buttons_container.get_child(i)
			if button is Button:
				print("  Button ", i, ": ", button.text, " disabled: ", button.disabled)

# TAMBAHAN: Function yang dipanggil saat mouse enter/exit UI
func _on_mouse_entered():
	print("🎯 Mouse entered UI")

func _on_mouse_exited():
	print("🎯 Mouse exited UI")

func _notification(what):
	match what:
		NOTIFICATION_MOUSE_ENTER:
			_on_mouse_entered()
		NOTIFICATION_MOUSE_EXIT:
			_on_mouse_exited()

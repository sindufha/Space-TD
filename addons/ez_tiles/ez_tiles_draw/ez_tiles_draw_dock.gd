@tool
extends Control
class_name EZTilesDrawDock

enum NeighbourMode {OVERWRITE, PEERING_BIT, INCLUSIVE, EXCLUSIVE}
enum DragMode {BRUSH, AREA, STAMP, SNAPSHOT}

const EZ_TILE_CUSTOM_META := "_is_ez_tiles_generated"

var StampScene : PackedScene
var StampTileScene : PackedScene
var TerrainPickerEntryScene : PackedScene
var under_edit : TileMapLayer = null
var hint_label : Label
var main_container : Control
var default_editor_check_button : Button
var terrain_list_container : VBoxContainer
var drag_start := Vector2i.ZERO
var drag_mode := DragMode.BRUSH

var remembered_cells := {}
var viewport_has_mouse := false
var lmb_is_down := false
var rmb_is_down := false
var current_terrain_id := 0
var neighbour_mode := NeighbourMode.OVERWRITE
var suppress_preview := false
var using_eraser := false
var undo_redo : EditorUndoRedoManager

var area_draw_tab : AreaDraw
var brush_tab : BrushDraw
var stamp_tab : StampTab

var area_draw_toggle_button : Button
var brush_draw_toggle_button : Button
var stamp_draw_toggle_button : Button
var select_snap_shot_button : Button
var eraser_button : Button

var connect_toggle_button : Button
var connect_icon_connected : Texture2D
var connect_icon_disconnected : Texture2D
var neighbor_mode_option_button : OptionButton

const EZ_NEIGHBOUR_MAP := {
	"....O...." : Vector2i.ZERO,
	"....OX..." : Vector2i(0,3),
	"....O..X." : Vector2i(1,0),
	".X..O..X." : Vector2i(1,1),
	".X..O...." : Vector2i(1,2),
	"...XOX..." : Vector2i(1,3),
	"...XO...." : Vector2i(2,3),
	"....OX.X." : Vector2i(3,0),
	".X..OX.X." : Vector2i(3,1),
	".X..OX..." : Vector2i(3,2),
	"...XOX.X." : Vector2i(4,0),
	".X.XOX.X." : Vector2i(4,1),
	".X.XOX..." : Vector2i(4,2),
	"...XO..X." : Vector2i(5,0),
	".X.XO..X." : Vector2i(5,1),
	".X.XO...." : Vector2i(5,2)
}


func _enter_tree() -> void:
	StampScene = preload("res://addons/ez_tiles/ez_tiles_draw/stamp.tscn")
	StampTileScene = preload("res://addons/ez_tiles/ez_tiles_draw/stamp_tile.tscn")
	TerrainPickerEntryScene = preload("res://addons/ez_tiles/ez_tiles_draw/terrain_picker_entry.tscn")
	hint_label = find_child("HintLabel")
	main_container = find_child("MainVBoxContainer")
	default_editor_check_button = find_child("DefaultEditorCheckButton")
	terrain_list_container = find_child("TerrainListVboxContainer")
	area_draw_tab = find_child("Area Draw")
	brush_tab = find_child("Brush Draw")
	stamp_tab = find_child("Stamp")
	area_draw_toggle_button = find_child("AreaDrawButton")
	brush_draw_toggle_button = find_child("BrushDrawButton")
	stamp_draw_toggle_button = find_child("StampDrawButton")
	select_snap_shot_button = find_child("SelectSnapShotButton")
	eraser_button = find_child("EraserButton")
	connect_toggle_button = find_child("ConnectingToggle")
	connect_icon_disconnected = preload("res://addons/ez_tiles/ez_tiles_draw/icons/Connect1.svg")
	connect_icon_connected = preload("res://addons/ez_tiles/ez_tiles_draw/icons/Connect2.svg")
	neighbor_mode_option_button = find_child("NeighbourModeOptionButton")


func activate(node : TileMapLayer):
	current_terrain_id = 0
	remembered_cells = {}
	under_edit = node
	hint_label.hide()
	main_container.show()

	for child in terrain_list_container.get_children():
		if is_instance_valid(child):
			child.queue_free()

	if under_edit.tile_set.get_terrain_sets_count() > 0:
		for terrain_id in range(under_edit.tile_set.get_terrains_count(0)):
			var entry : TerrainPickerEntry = TerrainPickerEntryScene.instantiate()
			entry.terrain_name = under_edit.tile_set.get_terrain_name(0, terrain_id)
			entry.texture_resource = _get_first_texture_for_terrain(terrain_id)
			entry.terrain_id = terrain_id
			entry.selected.connect(_on_terrain_selected)
			terrain_list_container.add_child(entry)
		area_draw_tab.update_grid_preview(
			_get_first_texture_for_terrain(current_terrain_id),
			under_edit.tile_set.tile_size)

		brush_tab.update_tile_buttons(
			_get_first_tileset_source_for_terrain(current_terrain_id),
			under_edit.tile_set.tile_size)

	if under_edit.has_meta(EZ_TILE_CUSTOM_META):
		default_editor_check_button.button_pressed = true
	else:
		default_editor_check_button.button_pressed = false

	stamp_tab.show_stamps_for_tile_map_layer(under_edit)


func _get_first_source_id_for_terrain(terrain_id : int) -> int:
	for i in range(under_edit.tile_set.get_source_count()):
		var source_id := under_edit.tile_set.get_source_id(i)
		var source : TileSetAtlasSource  = under_edit.tile_set.get_source(source_id)
		if source.get_tiles_count() > 0:
			for j in source.get_tiles_count():
				var tile_data = source.get_tile_data(source.get_tile_id(j), 0)
				if tile_data.terrain == terrain_id:
					return source_id
	printerr("Terrain %d not found in tile set sources: " % terrain_id)
	return terrain_id # assume equal in case of inconsistent data


func _get_first_texture_for_terrain(terrain_id : int) -> Texture2D:
	var source := _get_first_tileset_source_for_terrain(terrain_id)
	if is_instance_valid(source):
		return source.texture
	return null


func _get_first_tileset_source_for_terrain(terrain_id : int) -> TileSetAtlasSource:
	for i in range(under_edit.tile_set.get_source_count()):
		var source_id := under_edit.tile_set.get_source_id(i)
		var source : TileSetAtlasSource  = under_edit.tile_set.get_source(source_id)
		if source.get_tiles_count() > 0:
			for j in source.get_tiles_count():
				var tile_data = source.get_tile_data(source.get_tile_id(j), 0)
				if tile_data.terrain == terrain_id:
					return source
	printerr("Terrain %d not found in tile set sources: " % terrain_id)
	return null


func deactivate():
	under_edit = null
	hint_label.show()
	main_container.hide()


func _on_terrain_selected(id : int) -> void:
	current_terrain_id = id
	area_draw_tab.update_grid_preview(
			_get_first_texture_for_terrain(id), under_edit.tile_set.tile_size)
	brush_tab.update_tile_buttons(
		_get_first_tileset_source_for_terrain(id), under_edit.tile_set.tile_size)
	if neighbour_mode != NeighbourMode.OVERWRITE:
		brush_tab.connect_terrains_button.button_pressed = true

	if stamp_tab.visible:
		brush_tab.show()


func _place_back_remembered_cells() -> void:
	for prev_pos in remembered_cells.keys():
		if remembered_cells[prev_pos][0] > -1:
			under_edit.set_cell(prev_pos, remembered_cells[prev_pos][0], remembered_cells[prev_pos][1])
		else:
			under_edit.erase_cell(prev_pos)
	remembered_cells.clear()


func _remember_cell(tile_pos : Vector2i) -> void:
	if under_edit.get_cell_source_id(tile_pos) > -1:
		remembered_cells[tile_pos] = [under_edit.get_cell_source_id(tile_pos), under_edit.get_cell_atlas_coords(tile_pos)]
	else:
		remembered_cells[tile_pos] = [-1, Vector2i.ZERO]


func _take_snapshot(drag_end : Vector2i) -> void:
	var stamp : Stamp = StampScene.instantiate()
	var from_x := drag_start.x if drag_start.x < drag_end.x else drag_end.x
	var to_x := drag_start.x if drag_start.x > drag_end.x else drag_end.x
	var from_y := drag_start.y if drag_start.y < drag_end.y else drag_end.y
	var to_y := drag_start.y if drag_start.y > drag_end.y else drag_end.y
	stamp.stamp_size = Vector2i(to_x - from_x + 1, to_y - from_y + 1)
	var stamp_tile_size := Vector2(under_edit.tile_set.tile_size)
	while (stamp.stamp_size.x * stamp_tile_size.x) > 512:
		stamp_tile_size *= 0.5

	for y in range(from_y, to_y + 1):
		for x in range(from_x, to_x + 1):
			var tile_pos := Vector2i(x, y)
			var stamp_tile : TextureRect = StampTileScene.instantiate()
			stamp_tile.custom_minimum_size = Vector2i(stamp_tile_size)
			if under_edit.get_cell_source_id(tile_pos) > -1:
				stamp.stamp_cell_data[Vector2i(x - from_x, y - from_y)] = [under_edit.get_cell_source_id(tile_pos), under_edit.get_cell_atlas_coords(tile_pos)]
				stamp_tile.texture = AtlasTexture.new()
				stamp_tile.texture.atlas = under_edit.tile_set.get_source(under_edit.get_cell_source_id(tile_pos)).texture
				stamp_tile.texture.region = Rect2i(
					under_edit.get_cell_atlas_coords(tile_pos) * under_edit.tile_set.tile_size,
					under_edit.tile_set.tile_size)
			else:
				stamp.stamp_cell_data[Vector2i(x - from_x, y - from_y)] = [-1, Vector2i.ZERO]
			stamp.tile_textures.append(stamp_tile)
	stamp.tile_map_layer_under_edit = under_edit
	stamp_tab.add_stamp(stamp)


func _grow_cells(area_cells : Array, diagonal := false,  base_dir := Vector2i.ZERO) -> Array:
	var expanded_region := {}
	for cell in area_cells:
		if cell not in expanded_region:
			expanded_region[cell] = true
		for neighour in _get_neighbors(cell, diagonal, base_dir):
			if neighour not in expanded_region:
				expanded_region[neighour] = true
	return expanded_region.keys()

func _straighten_line_direction(from : Vector2i, to : Vector2i) -> Vector2:
	var angle := fmod(rad_to_deg(Vector2(from).angle_to_point(Vector2(to))), 360)
	if angle < 0:
		angle += 360
	match(snappedi(angle, 45)):
		45:
			return Vector2(0.7071, 0.7071)
		90:
			return Vector2.DOWN
		135:
			return Vector2(-0.7071, 0.7071)
		180:
			return Vector2.LEFT
		225:
			return Vector2(-0.7071, -0.7071)
		270:
			return Vector2.UP
		315:
			return Vector2(0.7071, -0.7071)
		0, 360, _:
			return Vector2.RIGHT

func _get_brush_sized_line(from : Vector2i, cell : Dictionary) -> Dictionary:
	var to := cell.keys()[0] as Vector2i
	var direction = _straighten_line_direction(from, to)
	var cur := Vector2(from)
	var out := {}
	for _i in range(floor(from.distance_to(to))):
		cur += direction
		out.merge(_get_brush_for_cell({Vector2i(cur.floor()): cell.values()[0]}))
	return out


func _get_brush_for_cell(cell : Dictionary) -> Dictionary:
	if brush_tab.brush_size == 1:
		return cell

	var out := Dictionary()
	var cur_keys := []
	if brush_tab.brush_shape == BrushDraw.BrushShape.SQUARE:
		var middle : Vector2i = cell.keys()[0] + Vector2i.ONE
		for x in range(middle.x -  ceil(brush_tab.brush_size / 2.0), middle.x + floor(brush_tab.brush_size / 2.0)):
			for y in range(middle.y -  ceil(brush_tab.brush_size / 2.0), middle.y + floor(brush_tab.brush_size / 2.0)):
				cur_keys.append(Vector2i(x, y))
	elif brush_tab.brush_shape == BrushDraw.BrushShape.CIRCLE:
		var m : Vector2i = cell.keys()[0]
		var sz := brush_tab.brush_size
		for x in range(m.x - sz - 1, m.x + sz + 1):
			for y in range(m.y - sz - 1, m.y + sz + 1):
				if Vector2i(x, y).distance_to(m) <= sz * 0.67:
					cur_keys.append(Vector2i(x, y))
	for k in cur_keys:
		out[k] = cell.values()[0]
	return out


func _get_sized_brush(cell : Dictionary) -> Dictionary:
	if Input.is_key_pressed(KEY_SHIFT):
		return _get_brush_sized_line(drag_start, cell)

	return _get_brush_for_cell(cell)


func _get_stamp_placement_area(stamp : Stamp, tile_pos : Vector2i, include_empty_cells := false) -> Array[Vector2i]:
	var out : Array[Vector2i] = []
	for stamp_tile_pos in stamp.stamp_cell_data.keys():
		if stamp.stamp_cell_data[stamp_tile_pos][0] > -1 or include_empty_cells:
			out.append(tile_pos + stamp_tile_pos)

	return out


func _place_stamp_preview(stamp : Stamp, cursor_tile_pos : Vector2i) -> void:
	var overwrite_with_empty_cells := Input.is_key_pressed(KEY_SHIFT)
	var stamp_plc_area := _get_stamp_placement_area(stamp, cursor_tile_pos, overwrite_with_empty_cells)
	var all_cells = _grow_cells(stamp_plc_area, neighbour_mode == NeighbourMode.PEERING_BIT)
	for tile_pos in all_cells:
		_remember_cell(tile_pos)

	for stamp_tile_pos in stamp.stamp_cell_data.keys():
		if stamp.stamp_cell_data[stamp_tile_pos][0] > -1:
			under_edit.set_cell(cursor_tile_pos + stamp_tile_pos, stamp.stamp_cell_data[stamp_tile_pos][0],
					stamp.stamp_cell_data[stamp_tile_pos][1])
		elif overwrite_with_empty_cells:
				under_edit.erase_cell(cursor_tile_pos + stamp_tile_pos)
		if neighbour_mode != NeighbourMode.PEERING_BIT and neighbour_mode != NeighbourMode.OVERWRITE:
			_update_atlas_coords(_get_neighbors(cursor_tile_pos + stamp_tile_pos))

	if neighbour_mode == NeighbourMode.PEERING_BIT:
		for tile_pos in stamp_plc_area:
			under_edit.set_cells_terrain_connect([tile_pos], 0, under_edit.get_cell_source_id(tile_pos), true)


func _place_cells_preview(cells_in_current_draw_area : Dictionary, terrain_id : int) -> void:
	var all_cells := _grow_cells(cells_in_current_draw_area.keys(), neighbour_mode == NeighbourMode.PEERING_BIT)
	for tile_pos in all_cells:
		_remember_cell(tile_pos)

	for tile_pos in cells_in_current_draw_area:
		if terrain_id < 0:
			under_edit.erase_cell(tile_pos)
		else:
			var coord : Vector2i = (
				cells_in_current_draw_area[tile_pos] if neighbour_mode == NeighbourMode.OVERWRITE 
				else _get_ez_atlas_coord(tile_pos, terrain_id)
			)
			under_edit.set_cell(tile_pos, _get_first_source_id_for_terrain(terrain_id), coord)
		if neighbour_mode != NeighbourMode.PEERING_BIT and neighbour_mode != NeighbourMode.OVERWRITE:
			_update_atlas_coords(_get_neighbors(tile_pos))

	if neighbour_mode == NeighbourMode.PEERING_BIT:
		under_edit.set_cells_terrain_connect(cells_in_current_draw_area.keys(), 0, terrain_id, true)


func _commit_cell_placement(cells_in_current_draw_area : Array) -> void:
	undo_redo.create_action("Update cells in: " + under_edit.name)
	for cell in remembered_cells:
		if remembered_cells[cell][0] < 0:
			undo_redo.add_undo_method(under_edit, "erase_cell", cell)
		else:
			undo_redo.add_undo_method(under_edit, "set_cell", cell, 
					remembered_cells[cell][0], remembered_cells[cell][1])
	remembered_cells.clear()
	for cell in _grow_cells(cells_in_current_draw_area):
		if under_edit.get_cell_source_id(cell) > -1:
			undo_redo.add_do_method(under_edit, "set_cell", cell,
					under_edit.get_cell_source_id(cell),
					under_edit.get_cell_atlas_coords(cell))
		else:
			undo_redo.add_do_method(under_edit, "erase_cell", cell)
	undo_redo.commit_action(false)


func _update_atlas_coords(cells : Array[Vector2i]) -> void:
	for tile_pos in cells:
		under_edit.set_cell(tile_pos, under_edit.get_cell_source_id(tile_pos),
				_get_ez_atlas_coord(tile_pos, under_edit.get_cell_source_id(tile_pos)))


func _erase_cells(cells : Dictionary):
	# prevent current preview placement from being added to the undo list
	if drag_mode == DragMode.BRUSH:
		for cell in cells.keys():
			if cell in remembered_cells and remembered_cells[cell][0] > -1:
				under_edit.set_cell(cell, remembered_cells[cell][0], remembered_cells[cell][1])
			else:
				under_edit.erase_cell(cell)
	_place_cells_preview(cells, -1)


func _get_neighbors(tile_pos : Vector2i, diagonal := false,  base_dir := Vector2i.ZERO) -> Array[Vector2i]:
	if base_dir:
		return [
			tile_pos + base_dir,
			tile_pos + Vector2i(base_dir.x , 0),
			tile_pos + Vector2i(0, base_dir.y)
		]
	if diagonal:
		return [
			tile_pos + Vector2i.LEFT,
			tile_pos + Vector2i.UP,
			tile_pos + Vector2i.DOWN,
			tile_pos + Vector2i.RIGHT,
			tile_pos - Vector2i.ONE,
			tile_pos + Vector2i.ONE,
			tile_pos + Vector2i(-1, 1),
			tile_pos + Vector2i(1, -1)
		]
	return [tile_pos + Vector2i.LEFT, tile_pos + Vector2i.UP, tile_pos + Vector2i.DOWN, tile_pos + Vector2i.RIGHT]


func _consider_a_neighbour(cell : Vector2i, for_source_id : int) -> bool:
	var neighbour_source_id := under_edit.get_cell_source_id(cell)
	match(neighbour_mode):
		NeighbourMode.INCLUSIVE:
			return neighbour_source_id > -1
		NeighbourMode.EXCLUSIVE:
			return neighbour_source_id > -1 and neighbour_source_id == for_source_id
		NeighbourMode.OVERWRITE:
			printerr("illegal state: should not be considering neighbours")
			return false
		NeighbourMode.PEERING_BIT:
			printerr("illegal state: should invoke `under_edit.set_cells_terrain_connect`")
			return false
	return false


func _get_ez_atlas_coord(tile_pos : Vector2i, for_terrain_id : int) -> Vector2i:
	if neighbour_mode == NeighbourMode.PEERING_BIT:
		var source := _get_first_tileset_source_for_terrain(for_terrain_id)
		for id in range(source.get_tiles_count()):
			return source.get_tile_id(id)
		printerr("could not find a tile in terrain: " + str(for_terrain_id))
		return Vector2i.ZERO
	# EZ Tiles considers the source_id to be equal to the terrain_id
	# Therefore, in these modes the complexity of searching the correct texture is lost 
	#   (thus, making things EZ. is a lot less flexible)
	# - In inclusive mode all terrains in neighboring tiles are considered to be  the same terrain
	# - in exclusive mode the terrains from the exact same TileSetSource are considered the same terrain
	var l = "X" if _consider_a_neighbour(tile_pos + Vector2i.LEFT, for_terrain_id) else "."
	var r = "X" if _consider_a_neighbour(tile_pos + Vector2i.RIGHT, for_terrain_id) else ".";
	var t = "X" if _consider_a_neighbour(tile_pos + Vector2i.UP, for_terrain_id) else "."
	var b = "X" if _consider_a_neighbour(tile_pos + Vector2i.DOWN, for_terrain_id) else ".";

	var fmt = ".%s.%sO%s.%s." % [t, l, r, b]
	return EZ_NEIGHBOUR_MAP[fmt]  if fmt in EZ_NEIGHBOUR_MAP else Vector2i.ZERO


func get_draw_rect(tile_pos : Vector2i) -> Rect2i:
	match(drag_mode):
		DragMode.SNAPSHOT:
			if lmb_is_down:
				var from_x := drag_start.x if drag_start.x < tile_pos.x else tile_pos.x
				var to_x := drag_start.x if drag_start.x > tile_pos.x else tile_pos.x
				var from_y := drag_start.y if drag_start.y < tile_pos.y else tile_pos.y
				var to_y := drag_start.y if drag_start.y > tile_pos.y else tile_pos.y
				return Rect2i(Vector2i(from_x, from_y),  Vector2i(to_x, to_y) - Vector2i(from_x, from_y) + Vector2i.ONE)
			else:
				return Rect2i(tile_pos, Vector2i.ONE)
		DragMode.AREA:
			if rmb_is_down or lmb_is_down:
				var from_x := drag_start.x if drag_start.x < tile_pos.x else tile_pos.x
				var to_x := drag_start.x if drag_start.x > tile_pos.x else tile_pos.x
				var from_y := drag_start.y if drag_start.y < tile_pos.y else tile_pos.y
				var to_y := drag_start.y if drag_start.y > tile_pos.y else tile_pos.y
				return Rect2i(Vector2i(from_x, from_y),  Vector2i(to_x, to_y) - Vector2i(from_x, from_y) + Vector2i.ONE)
			else:
				return Rect2i(tile_pos, Vector2i.ONE)
		DragMode.STAMP:
			var stamp := stamp_tab.get_selected_stamp()
			if is_instance_valid(stamp):
				return Rect2i(tile_pos, stamp.stamp_size)
			else:
				Rect2i()
		DragMode.BRUSH, _:
			return Rect2i()
	return Rect2i()


func get_draw_area(tile_pos : Vector2i) -> Array:
	match(drag_mode):
		DragMode.SNAPSHOT:
			return []
		DragMode.AREA:
			if rmb_is_down or lmb_is_down:
				return _get_draw_shape_for_area(drag_start, tile_pos).keys()
			else:
				return []
		DragMode.BRUSH:
			return _get_sized_brush({tile_pos: Vector2.ZERO}).keys()
		_:
			return []

func _get_draw_shape_for_area(p1 : Vector2i, p2 : Vector2i, for_shape : AreaDraw.Shape = area_draw_tab.shape) -> Dictionary:
	var from_x := p1.x if p1.x < p2.x else p2.x
	var to_x := p1.x if p1.x > p2.x else p2.x
	var from_y := p1.y if p1.y < p2.y else p2.y
	var to_y := p1.y if p1.y > p2.y else p2.y

	match(for_shape):
		AreaDraw.Shape.RECTANGLE_BASIC:
			return AreaDraw.get_cells_rectangle_basic(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.HARD_RECTANGLE:
			return AreaDraw.get_cells_rectangle(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.RECTANGLE:
			return AreaDraw.get_cells_rectangle(Vector2i(from_x, from_y), Vector2i(to_x, to_y), true)
		AreaDraw.Shape.SLOPE_TL:
			return AreaDraw.get_cells_slope_tl(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.SLOPE_BL:
			return AreaDraw.get_cells_slope_bl(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.SLOPE_TR:
			return AreaDraw.get_cells_slope_tr(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.SLOPE_BR:
			return AreaDraw.get_cells_slope_br(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.HILL_TOP:
			return AreaDraw.get_cells_hill_top(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.HILL_BOTTOM:
			return AreaDraw.get_cells_hill_bottom(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.HILL_LEFT:
			return AreaDraw.get_cells_hill_left(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.HILL_RIGHT:
			return AreaDraw.get_cells_hill_right(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
		AreaDraw.Shape.ISLAND:
			return AreaDraw.get_cells_island(Vector2i(from_x, from_y), Vector2i(to_x, to_y))
	return {}


func handle_mouse_move(tile_pos : Vector2i) -> void:
	if suppress_preview:
		pass
	if is_instance_valid(under_edit):
		if drag_mode == DragMode.BRUSH:
			_place_back_remembered_cells()
			if using_eraser:
				_place_cells_preview(_get_sized_brush({tile_pos: brush_tab.tile_coords}), -1)
			else:
				_place_cells_preview(_get_sized_brush({tile_pos: brush_tab.tile_coords}), current_terrain_id)
			if lmb_is_down:
				_commit_cell_placement(_get_sized_brush({tile_pos: brush_tab.tile_coords}).keys())

		elif drag_mode == DragMode.AREA:
			_place_back_remembered_cells()
			if rmb_is_down or (using_eraser and lmb_is_down):
				_erase_cells(_get_draw_shape_for_area(drag_start, tile_pos, AreaDraw.Shape.RECTANGLE))
			elif lmb_is_down:
				_place_cells_preview(_get_draw_shape_for_area(drag_start, tile_pos), current_terrain_id)

		elif drag_mode == DragMode.STAMP:
			_place_back_remembered_cells()
			var stamp := stamp_tab.get_selected_stamp()
			if is_instance_valid(stamp):
				_place_stamp_preview(stamp, tile_pos)


func handle_mouse_up(button : MouseButton, tile_pos: Vector2i):
	rmb_is_down = false if button == MouseButton.MOUSE_BUTTON_RIGHT else rmb_is_down
	lmb_is_down = false if button == MouseButton.MOUSE_BUTTON_LEFT else lmb_is_down

	if button == MouseButton.MOUSE_BUTTON_RIGHT or (using_eraser and button == MouseButton.MOUSE_BUTTON_LEFT):
		if drag_mode == DragMode.AREA:
			_commit_cell_placement(_get_draw_shape_for_area(drag_start, tile_pos, AreaDraw.Shape.RECTANGLE).keys())
	elif button == MouseButton.MOUSE_BUTTON_LEFT:
		if drag_mode == DragMode.AREA:
			_commit_cell_placement(_get_draw_shape_for_area(drag_start, tile_pos).keys())
		if drag_mode == DragMode.SNAPSHOT:
			_take_snapshot(tile_pos)
			_on_stamp_snapshot_toggled(false)
		if drag_mode == DragMode.STAMP:
			var stamp := stamp_tab.get_selected_stamp()
			if is_instance_valid(stamp):
				_commit_cell_placement(_get_stamp_placement_area(stamp, tile_pos))




func handle_mouse_down(button : MouseButton, tile_pos: Vector2i):
	drag_start = tile_pos
	rmb_is_down = true if button == MouseButton.MOUSE_BUTTON_RIGHT else rmb_is_down
	lmb_is_down = true if button == MouseButton.MOUSE_BUTTON_LEFT else lmb_is_down

	if using_eraser and button == MouseButton.MOUSE_BUTTON_RIGHT:
			eraser_button.button_pressed = false
			if drag_mode == DragMode.BRUSH:
				_place_back_remembered_cells()
	elif button == MouseButton.MOUSE_BUTTON_RIGHT:
			if drag_mode == DragMode.AREA and not suppress_preview:
				_place_back_remembered_cells()
				_erase_cells(_get_draw_shape_for_area(drag_start, tile_pos))
			elif drag_mode == DragMode.BRUSH:
				_place_back_remembered_cells()
				area_draw_toggle_button.button_pressed = true
				area_draw_tab.show()
			elif drag_mode == DragMode.SNAPSHOT:
				_on_stamp_snapshot_toggled(false)
			elif drag_mode == DragMode.STAMP:
				var stamp := stamp_tab.get_selected_stamp()
				if is_instance_valid(stamp):
					_place_back_remembered_cells()
					stamp.deselect()
	elif button == MouseButton.MOUSE_BUTTON_LEFT:
			if drag_mode == DragMode.AREA and not suppress_preview:
				_place_back_remembered_cells()
				_place_cells_preview(_get_draw_shape_for_area(drag_start, tile_pos), current_terrain_id)
			elif drag_mode == DragMode.BRUSH:
				_commit_cell_placement(_get_sized_brush({tile_pos: brush_tab.tile_coords}).keys())



func handle_mouse_entered():
	viewport_has_mouse = true
	remembered_cells.clear()


func handle_mouse_out():
	viewport_has_mouse = false
	if not lmb_is_down:
		_place_back_remembered_cells()


func _on_area_draw_button_pressed() -> void:
	area_draw_tab.show()


func _on_brush_draw_button_pressed() -> void:
	brush_tab.show()


func _on_stamp_draw_button_pressed() -> void:
	stamp_tab.show()


func _on_stamp_snapshot_toggled(on_off: bool) -> void:
	select_snap_shot_button.button_pressed = on_off
	if on_off:
		stamp_tab.show()
		stamp_tab.start_snapshot()
		drag_mode = DragMode.SNAPSHOT
	else:
		stamp_tab.stop_snapshotting()
		select_snap_shot_button.focus_mode = Control.FOCUS_NONE
		drag_mode = DragMode.STAMP


func _on_default_editor_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		under_edit.set_meta(EZ_TILE_CUSTOM_META, true)
	else:
		under_edit.remove_meta(EZ_TILE_CUSTOM_META)


func _on_tab_container_tab_changed(tab: DragMode) -> void:
	drag_mode = tab
	if tab != DragMode.STAMP:
		stamp_tab.stop_snapshotting()
		select_snap_shot_button.button_pressed = false

	match(drag_mode):
		DragMode.AREA:
			area_draw_toggle_button.button_pressed = true
			eraser_button.disabled = false
		DragMode.BRUSH:
			brush_draw_toggle_button.button_pressed = true
			eraser_button.disabled = false
		DragMode.STAMP:
			stamp_draw_toggle_button.button_pressed = true
			eraser_button.button_pressed = false
			eraser_button.disabled = true


func _on_neighbour_mode_option_button_item_selected(index: NeighbourMode) -> void:
	neighbour_mode = index
	if neighbour_mode == NeighbourMode.OVERWRITE:
		connect_toggle_button.icon = connect_icon_disconnected
		connect_toggle_button.button_pressed = false
		brush_tab.toggle_off_connected_brush()
		area_draw_tab.find_child("TileButton1").button_pressed = true
	else:
		connect_toggle_button.icon = connect_icon_connected
		connect_toggle_button.button_pressed = true
		brush_tab.connect_terrains_button.button_pressed = true
		area_draw_tab.connect_terrains_button.button_pressed = true


func _on_connecting_toggle_toggled(toggled_on: bool) -> void:
	if toggled_on:
		connect_toggle_button.icon = connect_icon_connected
		connect_toggle_button.button_pressed = true
		if neighbour_mode == NeighbourMode.OVERWRITE:
			neighbour_mode = NeighbourMode.PEERING_BIT
			neighbor_mode_option_button.selected = NeighbourMode.PEERING_BIT
			brush_tab.connect_terrains_button.button_pressed = true
			area_draw_tab.connect_terrains_button.button_pressed = true
		# else it's already in a connected mode
	else:
		connect_toggle_button.icon = connect_icon_disconnected
		connect_toggle_button.button_pressed = false
		neighbour_mode = NeighbourMode.OVERWRITE
		neighbor_mode_option_button.selected = NeighbourMode.OVERWRITE
		brush_tab.toggle_off_connected_brush()
		area_draw_tab.find_child("TileButton1").button_pressed = true


func _on_eraser_button_toggled(toggled_on: bool) -> void:
	using_eraser = toggled_on

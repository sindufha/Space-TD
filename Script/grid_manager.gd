# GridManager.gd
extends Node
class_name GridManager

static var TILE_SIZE = 64  # Sesuaikan dengan ukuran sprite
static var GRID_OFFSET = Vector2(0, 0)  # Offset untuk center sprite
static var GRID_WIDTH = 20  # Lebar grid untuk 1280px (1280/64 = 20)
static var GRID_HEIGHT = 11  # Tinggi grid untuk 720px (720/64 ≈ 11)

# Convert world position ke grid position
static func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(world_pos.x / TILE_SIZE),
		int(world_pos.y / TILE_SIZE)
	)

# Convert grid position ke world position (center of grid cell)
static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE/2,
		grid_pos.y * TILE_SIZE + TILE_SIZE/2
	)

# Cek apakah grid position valid untuk tower
static func is_valid_tower_position(grid_pos: Vector2i, occupied_positions: Array[Vector2i]) -> bool:
	# Cek bounds - pastikan dalam area grid
	if grid_pos.x < 0 or grid_pos.y < 0:
		return false
	if grid_pos.x >= GRID_WIDTH or grid_pos.y >= GRID_HEIGHT:
		return false
	
	# Cek apakah sudah occupied
	return not occupied_positions.has(grid_pos)

# Snap world position ke grid terdekat
static func snap_to_grid(world_pos: Vector2) -> Vector2:
	var grid_pos = world_to_grid(world_pos)
	return grid_to_world(grid_pos)

# Get all grid positions dalam radius tertentu
static func get_grid_positions_in_radius(center_grid: Vector2i, radius: int) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	for x in range(center_grid.x - radius, center_grid.x + radius + 1):
		for y in range(center_grid.y - radius, center_grid.y + radius + 1):
			var pos = Vector2i(x, y)
			if is_valid_grid_position(pos):
				positions.append(pos)
	return positions

# Cek apakah grid position dalam bounds
static func is_valid_grid_position(grid_pos: Vector2i) -> bool:
	return grid_pos.x >= 0 and grid_pos.y >= 0 and grid_pos.x < GRID_WIDTH and grid_pos.y < GRID_HEIGHT

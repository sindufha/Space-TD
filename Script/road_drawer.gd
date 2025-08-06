# Script: road_drawer.gd - attach ke Main
extends Node2D

func _ready():
	draw_road()
@onready var enemy_path: Path2D = $"../EnemyPath"

func draw_road():
	var path = enemy_path
	if path and path.curve:
		var curve = path.curve
		var length = curve.get_baked_length()
		
		# Buat segment jalan
		for i in range(int(length / 30)):
			var offset = i * 30
			var point = curve.sample_baked(offset)
			var next_point = curve.sample_baked(offset + 30)
			
			create_road_segment(path.global_position + point, 
							  path.global_position + next_point)

func create_road_segment(from: Vector2, to: Vector2):
	var road_piece = ColorRect.new()
	road_piece.size = Vector2(40, 40)
	road_piece.color = Color(0.4, 0.3, 0.2)  # Coklat
	road_piece.position = from - Vector2(20, 20)
	add_child(road_piece)

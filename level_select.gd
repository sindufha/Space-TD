extends Node2D


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")


func _on_level_1_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Stage1.tscn")

extends CanvasLayer


func _on_exit_btn_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")

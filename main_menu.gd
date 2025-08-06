extends Node2D

@onready var about_panel: Panel = $AboutPanel
@onready var setting_panel: Panel = $SettingPanel

@onready var settings: AcceptDialog = $Settings
@onready var about: AcceptDialog = $About

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://LevelSelect.tscn")
	

func _on_settings_button_pressed() -> void:
	setting_panel.visible=true


func _on_about_button_pressed() -> void:
	about_panel.visible=true


func _on_x_about_button_pressed() -> void:
	about_panel.visible=false


func _on_x_settings_button_pressed() -> void:
	setting_panel.visible=false

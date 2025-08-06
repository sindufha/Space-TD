extends Control

@onready var money_label: Label = $HBoxContainer/MoneyContainer/MoneyLabel
@onready var health_label: Label = $HBoxContainer/HealthContainer/HealthLabel
@onready var damage_label: Label = $HBoxContainer/HealthContainer/DamageLabel


func _ready():
	# Pastikan GameManager sudah ready
	call_deferred("connect_signals")

func connect_signals():
	if GameManager:
		GameManager.money_changed.connect(update_money)
		GameManager.health_changed.connect(update_health)
		GameManager.game_over.connect(show_game_over)
		
		# Update initial values
		update_money(GameManager.money)
		update_health(GameManager.health)
	else:
		print("GameManager not found!")

func update_money(amount):
	money_label.text = str(amount)
	print("UI Money updated: ", amount)  # Debug
	

var is_first_update = true
func update_health(amount):
	if not is_first_update:
		var old_health = int(health_label.text)
		if amount < old_health:
			show_damage_animation()
	health_label.text = str(amount)
	is_first_update = false
	print("UI Health updated: ", amount)
	
func show_game_over():
	print("Game Over UI triggered!")
	# Tambah game over screen
	var game_over_label = Label.new()
	game_over_label.text = "GAME OVER"
	game_over_label.add_theme_font_size_override("font_size", 48)
	game_over_label.anchors_preset = Control.PRESET_CENTER
	$".".add_child(game_over_label)


	get_tree().paused = true


func _on_button_pressed() -> void:
	print("Pressed")# Replace with function body.
func show_damage_animation():
	
	# Reset position & visibility
	damage_label.modulate.a = 1.0
	damage_label.text = "-1"
	damage_label.position = health_label.position + Vector2(0, 20)
	
	# Create tween animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade out sambil gerak ke atas
	tween.tween_property(damage_label, "modulate:a", 0.0, 1.0)
	tween.tween_property(damage_label, "position:y", 
						damage_label.position.y - 30, 1.0)

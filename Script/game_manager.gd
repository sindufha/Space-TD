extends Node

signal money_changed(new_amount)
signal health_changed(new_health)
signal game_over

var money = 1000
var health = 5
var score = 0

func add_money(amount):
	money += amount
	money_changed.emit(money)

func spend_money(amount):
	money -= amount
	money_changed.emit(money)

func lose_health(amount):
	health -= amount
	health_changed.emit(health)
	if health <= 0:
		game_over.emit()

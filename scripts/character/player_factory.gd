extends RefCounted

## Entry point for the world: builds a standalone, ready-to-add player body.

const PlayerController := preload("res://scripts/character/player_controller.gd")


static func create() -> CharacterBody3D:
	var body: CharacterBody3D = PlayerController.new()
	return body

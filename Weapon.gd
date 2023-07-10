extends Node3D
class_name Weapon

@export_enum("Primary", "Secondary", "Melee") var weaponType: String

@onready var damage
@onready var attackRate
@onready var cameraShake


func _ready():
	pass # Replace with function body.


func _process(delta):
	pass

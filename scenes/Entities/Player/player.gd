class_name Player
extends CharacterBody3D

signal healthChanged(health_value)

@onready var Cam = $Head/Camera3d as Camera3D
@onready var gunRay = $Head/Camera3d/RayCast3d as RayCast3D
@onready var gunAnimation = $GunAttack
@onready var muzzleFlash = $Head/Camera3d/Gun/Flash

@export var spray_vectors: Array[Vector2]

@onready var meleeAnimation = $MeleeAttack
@onready var meleeHitbox = $Head/Camera3d/Melee/Hitbox

@export var _bullet_scene : PackedScene

@export var groundAcceleration = 50.0
@export var groundSpeedLimit = 6.0
@export var airAcceleration = 500.0
@export var airSpeedLimit = 0.5
@export var groundFriction = 0.9
@export var crouchSpeed = 3

var currentWeapon = 1
# 1: Primary; 2: Secondary; 3: Melee

var mouseSensitivity = 1200
var mouse_relative_x = 0
var mouse_relative_y = 0
const JUMP_VELOCITY = 7
const MAX_CAM_SHAKE = 0.3

var crouching = false
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")*2.4

var health = 100
const maxHealth = 100

func _ready():
	if not is_multiplayer_authority():
		return
	$Head/Camera3d.current = true
	
	gunRay.add_exception(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
func _physics_process(delta):
	if not is_multiplayer_authority():
		return
	
	movement(delta)
	fire()

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func movement(delta):
	# GRAVITY
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		if not Input.is_action_pressed("Jump"):
			velocity *= groundFriction
		else:velocity.y = JUMP_VELOCITY
	
	# CROUCHING
	var headHeight = $CollisionShape3d.shape.height
	
	if Input.is_action_pressed("crouch") and is_on_floor():
		print($CollisionShape3d.shape.height)
		$CollisionShape3d.shape.height -= crouchSpeed * delta
		crouching = true
	else:
		$CollisionShape3d.shape.height += crouchSpeed * delta
		crouching = false
	$CollisionShape3d.shape.height = clamp($CollisionShape3d.shape.height, 1.3, 2)
	
	# MOVING
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	var basis = $Head/Camera3d.get_global_transform().basis
	var strafeDir = Vector3(0, 0, 0)
	if Input.is_action_pressed("moveUp"):
		strafeDir -= basis.z
	if Input.is_action_pressed("moveDown"):
		strafeDir += basis.z
	if Input.is_action_pressed("moveLeft"):
		strafeDir -= basis.x
	if Input.is_action_pressed("moveRight"):
		strafeDir += basis.x
	strafeDir.y = 0
	strafeDir = strafeDir.normalized()
	
	var strafeAccel = groundAcceleration if is_on_floor() else airAcceleration
	var speedLimit = groundSpeedLimit if is_on_floor() else airSpeedLimit
	if crouching:
		speedLimit *= 0.5
	
	var currentSpeed = strafeDir.dot(velocity)
	var accel = strafeAccel * delta
	accel = max(0, min(accel, speedLimit - currentSpeed))
	
	velocity += strafeDir * accel
	set_floor_stop_on_slope_enabled(false)

	move_and_slide()
	
	var input_dir = Input.get_vector("moveLeft", "moveRight", "moveUp", "moveDown")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	
	if gunAnimation.current_animation == "shoot":
		pass
	elif input_dir != Vector2.ZERO and is_on_floor():
		gunAnimation.play("move")
	else:
		gunAnimation.play("Idle")

func fire():
	if Input.is_action_just_pressed("Shoot"):
		if currentWeapon == 1:
			if gunAnimation.current_animation != "shoot":
				shoot()
				shotfx.rpc()
		if currentWeapon == 3:
			if meleeAnimation.current_animation != "Attack" || "Return":
				stab()
				meleefx.rpc()

@rpc("call_local")
func shotfx():
	gunAnimation.stop()
	gunAnimation.play("shoot")
	muzzleFlash.restart()
	muzzleFlash.emitting = true

@rpc("call_local")
func meleefx():
	meleeAnimation.stop()
	meleeAnimation.play("Attack")
	meleeAnimation.queue("Return")

func _input(event):
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x / mouseSensitivity
		$Head/Camera3d.rotation.x -= event.relative.y / mouseSensitivity
		$Head/Camera3d.rotation.x = clamp($Head/Camera3d.rotation.x, deg_to_rad(-90), deg_to_rad(90) )
		mouse_relative_x = clamp(event.relative.x, -50, 50)
		mouse_relative_y = clamp(event.relative.y, -50, 10)

var shotCount = 0
var sprayChange = Vector3(0, 0, 0)

func shoot():
	shotCount += 1
	sprayChange += Vector3(0, spray_vectors[shotCount].y, spray_vectors[shotCount].x)
	gunRay.target_position = gunRay.target_position + sprayChange
	if not gunRay.is_colliding():
		return
	elif gunRay.get_collider().get_class() == "CharacterBody3D":
		var hit_player = gunRay.get_collider()
		hit_player.receiveDmg.rpc_id(hit_player.get_multiplayer_authority())
	var bulletInst = _bullet_scene.instantiate() as Node3D
	bulletInst.set_as_top_level(true)
	get_parent().add_child(bulletInst)
	bulletInst.global_transform.origin = gunRay.get_collision_point() as Vector3
	bulletInst.look_at((gunRay.get_collision_point()+gunRay.get_collision_normal()),Vector3.BACK)
	
func sprayReset():
	shotCount = 0
	sprayChange = Vector3(0, 0, 0)

func stab():
	for body in meleeHitbox.get_overlapping_bodies():
		if body.get_class() == "CharacterBody3D":
			body.receiveDmg.rpc_id(body.get_multiplayer_authority())

@rpc("any_peer")
func receiveDmg():
	health -= 30
	healthChanged.emit(health)
	if health <= 0:
		queue_free()

func _on_animation_player_animation_finished(anim_name):
	if anim_name == "shoot":
		gunAnimation.play("Idle")

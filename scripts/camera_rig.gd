extends Node3D
## Orbit / pan / zoom / fly camera.
## The rig (this node) is the point the camera orbits around.
## The camera sits `distance` units behind it.

const MIN_DISTANCE := 1.0
const MAX_DISTANCE := 300.0
const ORBIT_SPEED := 0.006
const PAN_SPEED := 0.0016
const LOOK_SPEED := 0.0025

var camera: Camera3D
## Where the view starts, and where reset() puts it back.
const START_YAW := 0.0
const START_PITCH := -0.25
const START_DISTANCE := 9.0

var yaw := START_YAW
var pitch := START_PITCH
var distance := START_DISTANCE
## Set by main while a text field has focus, so typing doesn't fly the camera.
var input_blocked := false


func _init() -> void:
	camera = Camera3D.new()
	camera.far = 1000.0
	add_child(camera)


func _ready() -> void:
	camera.current = true
	_apply()


func _apply() -> void:
	# Default rotation order is YXZ: yaw around Y, then pitch around X.
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)


func orbit(relative: Vector2) -> void:
	yaw -= relative.x * ORBIT_SPEED
	pitch = clampf(pitch - relative.y * ORBIT_SPEED, -1.5, 1.5)
	_apply()


## First-person look: turns the camera in place (the orbit center moves instead).
func look(relative: Vector2) -> void:
	var cam_pos := camera.global_position
	yaw -= relative.x * LOOK_SPEED
	pitch = clampf(pitch - relative.y * LOOK_SPEED, -1.5, 1.5)
	_apply()
	position += cam_pos - camera.global_position


func pan(relative: Vector2) -> void:
	var b := camera.global_transform.basis
	position += (-b.x * relative.x + b.y * relative.y) * distance * PAN_SPEED


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply()


func focus(target: Vector3) -> void:
	position = target
	distance = minf(distance, 6.0)
	_apply()


func _process(delta: float) -> void:
	if input_blocked:
		return
	# Ctrl / Cmd is for shortcuts (Ctrl+S, Ctrl+Z), so it never flies the camera.
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return
	var b := camera.global_transform.basis
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		dir -= b.z
	if Input.is_key_pressed(KEY_S):
		dir += b.z
	if Input.is_key_pressed(KEY_A):
		dir -= b.x
	if Input.is_key_pressed(KEY_D):
		dir += b.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var speed := maxf(distance, 4.0) * 0.8
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 3.0
	position += dir.normalized() * speed * delta


func reset() -> void:
	position = Vector3.ZERO
	yaw = START_YAW
	pitch = START_PITCH
	distance = START_DISTANCE
	_apply()


func to_dict() -> Dictionary:
	return {
		"pos": [position.x, position.y, position.z],
		"yaw": yaw,
		"pitch": pitch,
		"distance": distance,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0.0, 0.0, 0.0])
	if p.size() == 3:
		position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	yaw = float(d.get("yaw", yaw))
	pitch = float(d.get("pitch", pitch))
	distance = clampf(float(d.get("distance", distance)), MIN_DISTANCE, MAX_DISTANCE)
	_apply()

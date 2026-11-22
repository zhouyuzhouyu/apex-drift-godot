class_name GhostCar
extends Node3D

## Holographic translucent Ghost Car for Time Trial mode.
## Smoothly interpolates saved best-lap transform samples [t, px, py, pz, rx, ry, rz].

var frames: Array = []
var playback_time: float = 0.0
var is_playing: bool = false


func setup(p_car_idx: int, p_frames: Array) -> void:
	frames = p_frames
	visible = frames.size() >= 2
	var spec := CarCatalog.get_car(p_car_idx)
	var livery := CarCatalog.get_livery(1)
	CarMeshBuilder.build_car_visuals(self, str(spec["style"]), livery, true)

	# Add holographic wheels
	var wheel_offsets := [
		Vector3(-0.83, 0.34, -1.30),
		Vector3( 0.83, 0.34, -1.30),
		Vector3(-0.83, 0.35,  1.30),
		Vector3( 0.83, 0.35,  1.30)
	]
	for wo in wheel_offsets:
		var wn := Node3D.new()
		wn.position = wo
		add_child(wn)
		CarMeshBuilder.build_wheel_visual(wn, 0.34, 0.28, Color(0.1, 0.9, 1.0), true)

	if visible:
		_apply_frame(0)


func park_at_start() -> void:
	playback_time = 0.0
	is_playing = false
	visible = frames.size() >= 2
	if visible:
		_apply_frame(0)


func start_lap() -> void:
	playback_time = 0.0
	is_playing = frames.size() >= 2
	visible = is_playing
	if is_playing:
		_apply_frame(0)


func _process(delta: float) -> void:
	if not is_playing or frames.size() < 2:
		return
	playback_time += delta
	var last_t := float(frames[frames.size() - 1][0])
	if playback_time >= last_t:
		_apply_frame(frames.size() - 1)
		return

	# Binary search for frame bracket
	var lo := 0
	var hi := frames.size() - 1
	while lo + 1 < hi:
		var mid := (lo + hi) >> 1
		if float(frames[mid][0]) <= playback_time:
			lo = mid
		else:
			hi = mid

	var f0: Array = frames[lo]
	var f1: Array = frames[hi]
	var dt := maxf(float(f1[0]) - float(f0[0]), 0.0001)
	var alpha := clampf((playback_time - float(f0[0])) / dt, 0.0, 1.0)

	var p0 := Vector3(float(f0[1]), float(f0[2]), float(f0[3]))
	var p1 := Vector3(float(f1[1]), float(f1[2]), float(f1[3]))
	var q0 := Quaternion.from_euler(Vector3(float(f0[4]), float(f0[5]), float(f0[6])))
	var q1 := Quaternion.from_euler(Vector3(float(f1[4]), float(f1[5]), float(f1[6])))

	global_position = p0.lerp(p1, alpha)
	global_transform.basis = Basis(q0.slerp(q1, alpha))


func _apply_frame(idx: int) -> void:
	var f: Array = frames[idx]
	global_position = Vector3(float(f[1]), float(f[2]), float(f[3]))
	rotation = Vector3(float(f[4]), float(f[5]), float(f[6]))

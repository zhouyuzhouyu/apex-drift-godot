class_name ChaseCamera
extends Camera3D

## Motorsport Camera Rig supporting Close Chase, Far Chase, Hood Cam, Rear-View Look,
## speed-reactive FOV, nitro punch, drift swing, impact shake, and post-finish orbit.

var target: RaceCar
var camera_mode: int = 0 # 0=Close Chase, 1=Far Chase, 2=Hood Cam
var finish_orbit: bool = false

var _orbit_angle: float = 0.0
var _shake_amount: float = 0.0
var _current_fov: float = 65.0
var _smoothed_forward: Vector3 = Vector3.FORWARD


func setup(p_target: RaceCar, initial_mode: int = 0) -> void:
	target = p_target
	camera_mode = clampi(initial_mode, 0, 2)
	fov = 66.0
	_current_fov = 66.0
	near = 0.15
	far = 1400.0
	if target:
		_smoothed_forward = -target.global_transform.basis.z
		_snap_immediate()
		if not target.impact_occurred.is_connected(_on_impact):
			target.impact_occurred.connect(_on_impact)


func cycle_mode() -> int:
	camera_mode = (camera_mode + 1) % 3
	GameState.settings["camera_mode"] = camera_mode
	return camera_mode


func _on_impact(intensity: float) -> void:
	_shake_amount = maxf(_shake_amount, intensity * 0.42)


func _snap_immediate() -> void:
	if target == null:
		return
	var fwd := (-target.global_transform.basis.z)
	fwd.y *= 0.25
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	_smoothed_forward = fwd
	_shake_amount = 0.0
	global_position = target.global_position - fwd * 6.4 + Vector3.UP * 2.55
	look_at(target.global_position + fwd * 8.0 + Vector3.UP * 1.1, Vector3.UP)


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	_shake_amount = maxf(0.0, _shake_amount - delta * 1.9)

	if finish_orbit:
		_orbit_angle += delta * 0.55
		var offset := Vector3(sin(_orbit_angle) * 7.2, 2.8, cos(_orbit_angle) * 7.2)
		global_position = global_position.lerp(target.global_position + offset, clampf(delta * 4.0, 0.0, 1.0))
		look_at(target.global_position + Vector3.UP * 0.85, Vector3.UP)
		fov = lerpf(fov, 60.0, delta * 3.0)
		return

	var looking_back := Input.is_action_pressed("look_back")
	var car_fwd := (-target.global_transform.basis.z)
	car_fwd.y *= 0.25
	car_fwd = car_fwd.normalized()

	# Blend travel velocity into camera heading so drifting showcases the dramatic sideways silhouette!
	var vel_horiz := Vector3(target.linear_velocity.x, 0.0, target.linear_velocity.z)
	var desired_dir := car_fwd
	if target.arcade_drift_active:
		var drift_travel := Vector3(target._drift_travel_dir.x, 0.0, target._drift_travel_dir.z)
		if drift_travel.length_squared() > 0.001:
			desired_dir = drift_travel.normalized().lerp(car_fwd, 0.16).normalized()
	elif vel_horiz.length() > 8.0 and target.local_velocity.z < -1.0:
		desired_dir = car_fwd.lerp(vel_horiz.normalized(), 0.38).normalized()

	var heading_lerp := 8.5 if target.arcade_drift_active else 6.5
	_smoothed_forward = _smoothed_forward.slerp(desired_dir, clampf(delta * heading_lerp, 0.0, 1.0)).normalized()

	var speed_ratio := clampf(target.get_speed_kmh() / 260.0, 0.0, 1.0)
	var nitro_boost_fov := 0.0
	if target.nitro_active or target.boost_pad_timer > 0.0:
		nitro_boost_fov = maxf(nitro_boost_fov, 9.5)
	if target.drift_exit_boost_timer > 0.0:
		nitro_boost_fov = maxf(nitro_boost_fov, 7.0 + float(target.drift_exit_boost_tier) * 2.8)
	var drift_fov_add := 3.5 if target.arcade_drift_active else 0.0

	if camera_mode == 2 and not looking_back:
		# Hood / Bumper Cam — ultra crisp sense of speed
		var hood_pos := target.global_transform * Vector3(0.0, 1.26, -0.52)
		global_position = hood_pos
		var look_pt := target.global_transform * Vector3(0.0, 1.05, -24.0)
		look_at(look_pt, target.global_transform.basis.y.lerp(Vector3.UP, 0.65).normalized())
		_current_fov = lerpf(_current_fov, 72.0 + speed_ratio * 13.0 + nitro_boost_fov, delta * 7.0)
	else:
		var dist := 6.2 if camera_mode == 0 else 8.4
		var height := 2.45 if camera_mode == 0 else 3.25
		var dir := -_smoothed_forward if looking_back else _smoothed_forward
		var right := dir.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		else:
			right = right.normalized()

		# Swing camera dynamically toward the OUTSIDE of the corner during rail-drift!
		# Left drift (drift_dir = +1) -> outside is +right; Right drift (drift_dir = -1) -> outside is -right
		var target_lat := 0.0
		if target.arcade_drift_active and not looking_back:
			var slip_norm := clampf(target.drift_angle_deg / 38.0, 0.35, 1.20)
			target_lat = target.drift_dir * (1.10 if camera_mode == 0 else 1.45) * slip_norm

		var target_dist := dist + speed_ratio * 0.65 + (0.65 if nitro_boost_fov > 0.0 else 0.0) + (0.45 if target.arcade_drift_active else 0.0)
		var cur_rel := global_position - target.global_position
		var cur_lat := cur_rel.dot(right)
		var cur_y := cur_rel.y
		var cur_back := -cur_rel.dot(dir)

		var smooth_lat := lerpf(cur_lat, target_lat, clampf(delta * (7.2 if target.arcade_drift_active else 10.5), 0.0, 1.0))
		var smooth_y := lerpf(cur_y, height, clampf(delta * 10.5, 0.0, 1.0))
		var smooth_back := lerpf(cur_back, target_dist, clampf(delta * 16.0, 0.0, 1.0))
		var min_back := dist * 0.92
		var max_back := dist + speed_ratio * 0.65 + (1.05 if nitro_boost_fov > 0.0 else 0.70)
		smooth_back = clampf(smooth_back, min_back, max_back)

		global_position = target.global_position - dir * smooth_back + right * smooth_lat + Vector3.UP * smooth_y
		var look_bias := -right * (target.drift_dir * 0.85) if (target.arcade_drift_active and not looking_back) else Vector3.ZERO
		var look_ahead := target.global_position + dir * 10.5 + look_bias + Vector3.UP * 1.05
		look_at(look_ahead, Vector3.UP)
		var base_fov := 64.0 if camera_mode == 0 else 68.0
		_current_fov = lerpf(_current_fov, base_fov + speed_ratio * 14.0 + nitro_boost_fov + drift_fov_add, delta * 6.0)

	# Apply collision impact micro-shake
	if _shake_amount > 0.005:
		global_position += Vector3(
			randf_range(-_shake_amount, _shake_amount),
			randf_range(-_shake_amount, _shake_amount) * 0.7,
			randf_range(-_shake_amount, _shake_amount)
		)

	fov = clampf(_current_fov, 56.0, 96.0)

class_name AIDriver
extends Node

## Pure-Pursuit + Curvature-Lookahead AI Driver operating the real GEVP RaceCar physics.
## Includes overtaking lane switching, difficulty scaling, subtle rubber-banding, and stuck recovery.

var car: RaceCar
var spline: TrackSpline
var all_cars: Array[RaceCar] = []
var player_car: RaceCar
var boost_distances: PackedFloat32Array = PackedFloat32Array()

var skill_level: float = 0.88
var base_lane_offset: float = 0.0
var active_lane_offset: float = 0.0
var aggression: float = 0.8
var _stuck_timer: float = 0.0
var _reverse_timer: float = 0.0
var _lane_recalc_timer: float = 0.0
var _ai_using_nitro: bool = false


func setup(
	p_car: RaceCar,
	p_spline: TrackSpline,
	p_all_cars: Array[RaceCar],
	p_player: RaceCar,
	rival_info: Dictionary,
	difficulty: int,
	p_boost_distances: PackedFloat32Array = PackedFloat32Array()
) -> void:
	car = p_car
	if car != null:
		car.enable_arcade_drift = false
	spline = p_spline
	all_cars = p_all_cars
	player_car = p_player
	boost_distances = p_boost_distances
	var base_skill := 0.76
	if difficulty == 1:
		base_skill = 0.88
	elif difficulty >= 2:
		base_skill = 0.99
	skill_level = clampf(base_skill + float(rival_info.get("skill_offset", 0.0)), 0.68, 1.08)
	base_lane_offset = float(rival_info.get("preferred_lane", 0.0))
	active_lane_offset = base_lane_offset
	aggression = float(rival_info.get("aggression", 0.8))
	_ai_using_nitro = false


func _physics_process(delta: float) -> void:
	if car == null or spline == null:
		return
	if car.controls_locked:
		car.throttle_input = 0.55
		car.brake_input = 0.0
		car.steering_input = 0.0
		car.handbrake_input = 0.0
		_ai_using_nitro = false
		car.nitro_input = false
		return
	if car.finished:
		# Coast smoothly after finishing
		car.throttle_input = 0.25 if car.speed < 18.0 else 0.0
		car.brake_input = 0.4 if car.speed > 26.0 else 0.0
		_ai_using_nitro = false
		car.nitro_input = false
		_steer_along_spline(delta)
		return

	# Check stuck / pinned condition
	if _reverse_timer > 0.0:
		_reverse_timer -= delta
		car.throttle_input = 0.0
		car.brake_input = 1.0
		car.steering_input = -signf(active_lane_offset) if absf(active_lane_offset) > 0.5 else 0.8
		car.handbrake_input = 0.0
		_ai_using_nitro = false
		car.nitro_input = false
		return

	if car.speed < 2.2:
		_stuck_timer += delta
		if _stuck_timer > 4.2:
			# Cleanly respawn AI car on centerline facing forward
			var dist := spline.cum_lengths[car.spline_index]
			car.reset_to_transform(spline.get_transform_at_distance(dist, 0.0, 0.14))
			_stuck_timer = 0.0
			return
		elif _stuck_timer > 1.8:
			_reverse_timer = 0.95
			return
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)

	# If accidentally in reverse gear, return cleanly to 1st gear
	if car.current_gear == -1:
		car.shift(2)

	# Periodically adjust overtaking lane to pass slower vehicles ahead
	_lane_recalc_timer -= delta
	if _lane_recalc_timer <= 0.0:
		_lane_recalc_timer = 0.22
		_update_overtaking_lane()

	var steer_angle := _steer_along_spline(delta)

	# Curvature lookahead speed regulation from current position through full braking horizon
	var brake_horizon := clampf(24.0 + car.speed * 1.45, 36.0, 115.0)
	var cur_curv := absf(spline.curvatures[car.spline_index])
	var ahead_curv := spline.get_max_curvature_ahead(car.spline_index, 5.5, brake_horizon)
	var max_curv := maxf(cur_curv, ahead_curv)

	var rb_mult := 1.0
	if player_car != null and not player_car.finished:
		var prog_diff := car.total_race_progress - player_car.total_race_progress
		if prog_diff > 0.08:
			rb_mult = 0.93
		elif prog_diff < -0.07:
			rb_mult = 1.07

	var road_grip := float(car.coefficient_of_friction.get("Road", 3.0))
	var grip_scale := clampf(road_grip / 3.05, 0.72, 1.00)
	var max_lat_accel := 20.5 * minf(skill_level, 1.04) * grip_scale
	var target_speed := 72.0 * skill_level * rb_mult
	if max_curv > 0.0025:
		target_speed = minf(target_speed, sqrt(max_lat_accel / max_curv))
	target_speed = clampf(target_speed, 18.0, 74.0)

	var speed_err := target_speed - car.speed
	if speed_err > 1.2:
		car.throttle_input = clampf(0.58 + speed_err * 0.09, 0.48, 1.0)
		car.brake_input = 0.0
	elif speed_err < -1.5:
		car.throttle_input = 0.0
		car.brake_input = clampf((-speed_err - 0.8) * 0.14, 0.18, 1.0)
	elif speed_err < 0.0:
		car.throttle_input = 0.0
		car.brake_input = 0.0
	else:
		car.throttle_input = 0.42
		car.brake_input = 0.0

	# Pro driver throttle feathering when sliding so RWD rivals (e.g. KENJI) hold traction out of hairpins
	if car.drift_angle_deg > 7.0:
		var slip_mod := clampf(1.0 - (car.drift_angle_deg - 7.0) / 13.0, 0.15, 1.0)
		car.throttle_input *= slip_mod

	car.handbrake_input = 0.0
	# Use Nitro smartly on straight sections with hysteresis (engage > 58%, disengage < 18% or corner)
	var straight_ahead := max_curv < 0.0048 and absf(steer_angle) < 0.14
	if not _ai_using_nitro:
		if straight_ahead and car.nitro > 58.0 and car.speed > 26.0 and speed_err > 2.0:
			_ai_using_nitro = true
	else:
		if car.nitro < 18.0 or not straight_ahead or speed_err < -1.0:
			_ai_using_nitro = false
	car.nitro_input = _ai_using_nitro


func _steer_along_spline(delta: float) -> float:
	var half_w := spline.road_width * 0.5 - 2.3
	var prog := spline.get_progress(car.global_position, car.spline_index)
	car.spline_index = int(prog["index"])
	var lateral := float(prog["lateral"])

	var desired_lane := clampf(active_lane_offset, -half_w, half_w)

	# Hug the inside apex through corners (+curv = left turn -> inside is -X) to stay well inside tarmac
	var n := spline.sample_count()
	var apex_idx := (car.spline_index + 5) % n
	var signed_curv := spline.curvatures[apex_idx]
	if absf(signed_curv) > 0.0055:
		var apex_bias := clampf(-signed_curv * 240.0, -2.6, 2.6)
		desired_lane = clampf(lerpf(desired_lane, apex_bias, 0.72), -half_w, half_w)

	# Pull firmly back toward tarmac centerline if nearing road edge
	if absf(lateral) > half_w:
		desired_lane = -signf(lateral) * 1.8

	var curv_near := spline.get_max_curvature_ahead(car.spline_index, 3.0, 24.0)
	var curv_tighten := clampf(1.0 - curv_near * 14.0, 0.78, 1.0)
	var lookahead := clampf((9.2 + car.speed * 0.25) * curv_tighten, 9.2, 20.5)
	var target_dist := fposmod(float(prog["distance_along"]) + lookahead, spline.total_length)
	var target_xf := spline.get_transform_at_distance(target_dist, desired_lane, 0.0)
	var local_target := car.to_local(target_xf.origin)

	# Forward is -Z, Left is -X -> positive angle means steer LEFT (+1.0 in GEVP)
	var angle := atan2(-local_target.x, maxf(1.5, -local_target.z))
	var steer_cmd := clampf(angle * 2.15, -1.0, 1.0)
	car.steering_input = lerpf(car.steering_input, steer_cmd, clampf(delta * 14.0, 0.0, 1.0))
	return angle


func _update_overtaking_lane() -> void:
	var half_w := spline.road_width * 0.5 - 2.6
	var target_lane := clampf(base_lane_offset, -half_w, half_w)
	var rival_blocking := false
	var near_curv := spline.get_max_curvature_ahead(car.spline_index, 0.0, 20.0)
	var cur_lat := float(spline.get_progress(car.global_position, car.spline_index)["lateral"])
	if near_curv < 0.013 and absf(cur_lat) < half_w:
		for other in all_cars:
			if other == car or not is_instance_valid(other):
				continue
			var rel := car.to_local(other.global_position)
			# Check cars directly ahead (rel.z < 0 and within 22m)
			if rel.z < -2.0 and rel.z > -22.0 and absf(rel.x) < 2.8:
				# Pick the side with more room inside the safe tarmac corridor
				var shift_dir := -1.0 if rel.x >= 0.0 else 1.0
				if shift_dir > 0.0 and cur_lat + 2.6 > half_w:
					shift_dir = -1.0
				elif shift_dir < 0.0 and cur_lat - 2.6 < -half_w:
					shift_dir = 1.0
				target_lane = clampf(cur_lat + shift_dir * 2.6, -half_w, half_w)
				rival_blocking = true
				break

	# Gently bias toward centerline (0.0) when approaching a boost pad within 45m on a straight
	if not rival_blocking and boost_distances.size() > 0 and spline.total_length > 1.0:
		var my_dist := spline.cum_lengths[car.spline_index]
		var on_straight := absf(spline.curvatures[car.spline_index]) < 0.011
		if on_straight:
			for bd in boost_distances:
				var ahead := fposmod(bd - my_dist, spline.total_length)
				if ahead > 0.0 and ahead <= 45.0:
					target_lane = 0.0
					break

	active_lane_offset = lerpf(active_lane_offset, target_lane, 0.55)

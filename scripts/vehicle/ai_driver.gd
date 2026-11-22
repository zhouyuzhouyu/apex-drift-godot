class_name AIDriver
extends Node

## Pure-Pursuit + Curvature-Lookahead AI Driver operating the real GEVP RaceCar physics.
## Includes overtaking lane switching, difficulty scaling, subtle rubber-banding, and stuck recovery.

var car: RaceCar
var spline: TrackSpline
var all_cars: Array[RaceCar] = []
var player_car: RaceCar

var skill_level: float = 0.88
var base_lane_offset: float = 0.0
var active_lane_offset: float = 0.0
var aggression: float = 0.8
var _stuck_timer: float = 0.0
var _reverse_timer: float = 0.0
var _lane_recalc_timer: float = 0.0


func setup(p_car: RaceCar, p_spline: TrackSpline, p_all_cars: Array[RaceCar], p_player: RaceCar, rival_info: Dictionary, difficulty: int) -> void:
	car = p_car
	spline = p_spline
	all_cars = p_all_cars
	player_car = p_player
	var base_skill := 0.76
	if difficulty == 1:
		base_skill = 0.88
	elif difficulty >= 2:
		base_skill = 0.99
	skill_level = clampf(base_skill + float(rival_info.get("skill_offset", 0.0)), 0.68, 1.08)
	base_lane_offset = float(rival_info.get("preferred_lane", 0.0))
	active_lane_offset = base_lane_offset
	aggression = float(rival_info.get("aggression", 0.8))


func _physics_process(delta: float) -> void:
	if car == null or spline == null:
		return
	if car.controls_locked:
		car.throttle_input = 0.55
		car.brake_input = 0.0
		car.steering_input = 0.0
		car.handbrake_input = 0.0
		car.nitro_input = false
		return
	if car.finished:
		# Coast smoothly after finishing
		car.throttle_input = 0.25 if car.speed < 18.0 else 0.0
		car.brake_input = 0.4 if car.speed > 26.0 else 0.0
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

	# Curvature lookahead speed regulation
	var max_curv := spline.get_max_curvature_ahead(car.spline_index, 14.0, clampf(26.0 + car.speed * 1.15, 32.0, 88.0))
	var max_lat_accel := 25.0 * skill_level
	var target_speed := 72.0 * skill_level
	if max_curv > 0.0025:
		target_speed = minf(target_speed, sqrt(max_lat_accel / max_curv))
	target_speed = clampf(target_speed, 19.0, 74.0)

	# Gentle rubber-banding relative to player so races stay close & competitive
	if player_car != null and not player_car.finished:
		var prog_diff := car.total_race_progress - player_car.total_race_progress
		if prog_diff > 0.08:
			target_speed *= 0.93
		elif prog_diff < -0.07:
			target_speed *= 1.07

	var speed_err := target_speed - car.speed
	if speed_err > 1.5:
		car.throttle_input = clampf(0.55 + speed_err * 0.08, 0.45, 1.0)
		car.brake_input = 0.0
	elif speed_err < -3.0:
		car.throttle_input = 0.0
		car.brake_input = clampf((-speed_err - 2.0) * 0.085, 0.15, 0.95)
	else:
		car.throttle_input = 0.45
		car.brake_input = 0.0

	car.handbrake_input = 0.0
	# Use Nitro smartly on straight sections when skill allows
	var straight_ahead := max_curv < 0.0055 and absf(steer_angle) < 0.16
	car.nitro_input = straight_ahead and car.nitro > 45.0 and car.speed > 26.0 and speed_err > 2.5


func _steer_along_spline(delta: float) -> float:
	var half_w := spline.road_width * 0.5 - 1.8
	var prog := spline.get_progress(car.global_position, car.spline_index)
	car.spline_index = int(prog["index"])
	var lateral := float(prog["lateral"])

	var desired_lane := clampf(active_lane_offset, -half_w, half_w)
	# Pull firmly back onto tarmac if pushed onto shoulder
	if absf(lateral) > half_w:
		desired_lane = -signf(lateral) * 1.2

	var lookahead := clampf(10.5 + car.speed * 0.48, 10.5, 36.0)
	var target_dist := fposmod(float(prog["distance_along"]) + lookahead, spline.total_length)
	var target_xf := spline.get_transform_at_distance(target_dist, desired_lane, 0.0)
	var local_target := car.to_local(target_xf.origin)

	# Forward is -Z, Left is -X -> positive angle means steer LEFT (+1.0 in GEVP)
	var angle := atan2(-local_target.x, maxf(1.5, -local_target.z))
	var steer_cmd := clampf(angle * 2.1, -1.0, 1.0)
	car.steering_input = lerpf(car.steering_input, steer_cmd, clampf(delta * 12.0, 0.0, 1.0))
	return angle


func _update_overtaking_lane() -> void:
	var half_w := spline.road_width * 0.5 - 2.0
	var target_lane := base_lane_offset
	for other in all_cars:
		if other == car or not is_instance_valid(other):
			continue
		var rel := car.to_local(other.global_position)
		# Check cars directly ahead (rel.z < 0 and within 22m)
		if rel.z < -2.0 and rel.z > -22.0 and absf(rel.x) < 3.0:
			# Shift toward whichever side has more room
			var shift_dir := -1.0 if rel.x >= 0.0 else 1.0
			target_lane = clampf(active_lane_offset + shift_dir * 3.4, -half_w, half_w)
			break
	active_lane_offset = lerpf(active_lane_offset, target_lane, 0.45)

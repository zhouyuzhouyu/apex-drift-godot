class_name RaceCar
extends Vehicle

## Complete playable & AI RaceCar built on top of GEVP Vehicle.
## Adds Nitro Boost, Drift Detection/Scoring, Tire Smoke, Skidmarks, Aerodynamic Downforce,
## Headlights/Brake Lights, Collision Impacts, Launch Control, and Clean Spline Respawn.

signal impact_occurred(intensity: float)
signal boost_pad_hit
signal gear_changed(new_gear: int)
signal drift_boost_triggered(tier: int)

var car_id: String = "apex_gtr"
var car_style: String = "gt"
var car_idx: int = 0
var livery_idx: int = 0
var driver_name: String = "PLAYER"
var is_player: bool = false
var is_night_track: bool = false

# Race control & state
var controls_locked: bool = true
var nitro_input: bool = false
var nitro: float = 65.0
var nitro_active: bool = false
var nitro_force: float = 11500.0
var nitro_charge_mult: float = 1.0
var downforce_coeff: float = 2.4
var max_speed_kmh: float = 258.0
var boost_pad_timer: float = 0.0
var launch_boost_timer: float = 0.0

var _base_stability_yaw_strength: float = 6.5
var _base_tcs_max_slip: float = 10.0

# Ridge Racer / Asphalt Arcade Rail-Drift System
var enable_arcade_drift: bool = true
var arcade_drift_active: bool = false
var drift_dir: float = 0.0 # +1.0 = Left Drift, -1.0 = Right Drift
var drift_duration: float = 0.0
var drift_charge_progress: float = 0.0 # 0.0 .. 3.0 across 3 boost tiers
var drift_boost_tier: int = 0 # 0=none, 1=Cyan Mini, 2=Gold Super, 3=Violet Ultra
var drift_exit_boost_timer: float = 0.0
var drift_exit_boost_tier: int = 0
var drift_turn_rate: float = 1.04
var drift_neutral_deg: float = 29.0
var drift_max_deg: float = 39.0
var drift_speed_retention: float = 0.94
var drift_charge_rate: float = 1.05

var _drift_travel_dir: Vector3 = Vector3.FORWARD
var _drift_entry_speed: float = 0.0
var _drift_speed: float = 0.0
var _drift_slip_rad: float = 0.0
var _drift_exit_timer: float = 0.0
var _drift_air_timer: float = 0.0
var _drift_arm_timer: float = 0.0
var _drift_straighten_timer: float = 0.0
var _drift_wall_resync_timer: float = 0.0
var _drift_steer_smooth: float = 0.0
var _prev_handbrake_down: bool = false
var _prev_brake_down: bool = false

# Drift state & scoring
var is_drifting: bool = false
var drift_angle_deg: float = 0.0
var current_drift_score: float = 0.0
var total_drift_score: int = 0
var drift_bank_timer: float = 0.0
var wheel_slip_intensity: float = 0.0

# Race progress tracking (updated by RaceManager)
var current_lap: int = 1
var next_checkpoint: int = 0
var spline_index: int = 0
var spline_progress: float = 0.0
var total_race_progress: float = 0.0
var finished: bool = false
var finish_time: float = 0.0
var current_lap_time: float = 0.0
var best_lap_time: float = 0.0
var race_rank: int = 1
var track_spline: TrackSpline = null
var barrier_corridor_half_width: float = 0.0

# Visual handles
var _visual_root: Node3D
var _brake_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _nitro_flames: Array[MeshInstance3D] = []
var _smoke_left: CPUParticles3D
var _smoke_right: CPUParticles3D
var _spark_particles: CPUParticles3D
var _headlight_spot: SpotLight3D
var _skid_mesh_inst: MeshInstance3D
var _skid_segments: Array[Dictionary] = []
var _last_skid_pos: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _last_skid_valid: Array[bool] = [false, false]
var _skid_rebuild_accum: float = 0.0
var _prev_gear: int = 0
var _impact_cooldown: float = 0.0


func _init() -> void:
	defer_initialization = true


func configure(p_car_idx: int, p_livery_idx: int, p_driver_name: String, p_is_player: bool, p_is_night: bool) -> void:
	car_idx = p_car_idx
	livery_idx = p_livery_idx
	driver_name = p_driver_name
	is_player = p_is_player
	is_night_track = p_is_night

	var spec := CarCatalog.get_car(car_idx)
	var livery := CarCatalog.get_livery(livery_idx)
	var p: Dictionary = spec["physics"]
	car_id = spec["id"]
	car_style = str(spec["style"])
	var is_slide_style := (car_style == "drift" or car_style == "rally")

	# Configure GEVP physics parameters from CarCatalog
	vehicle_mass = float(p["vehicle_mass"])
	max_torque = float(p["max_torque"])
	max_rpm = float(p["max_rpm"])
	idle_rpm = float(p["idle_rpm"])
	gear_ratios.clear()
	for gr in p["gear_ratios"]:
		gear_ratios.append(float(gr))
	final_drive = float(p["final_drive"])
	reverse_ratio = 3.2
	shift_time = 0.09
	automatic_transmission = true if (not is_player) else bool(GameState.settings.get("auto_transmission", true))

	front_torque_split = float(p["front_torque_split"])
	variable_torque_split = bool(p["variable_torque_split"])
	front_variable_split = float(p["front_variable_split"])
	front_weight_distribution = float(p["front_weight_distribution"])
	center_of_gravity_height_offset = float(p["center_of_gravity_height_offset"])
	inertia_multiplier = 1.15

	steering_speed = float(p["steering_speed"])
	countersteer_speed = float(p["countersteer_speed"])
	steering_speed_decay = float(p["steering_speed_decay"])
	max_steering_angle = float(p["max_steering_angle"])
	steering_slip_assist = 0.38 if is_slide_style else 0.28
	countersteer_assist = float(p["countersteer_assist"])
	steering_exponent = 1.35

	var esp_on := true if (not is_player) else bool(GameState.settings.get("stability_assist", true))
	enable_stability = true
	stability_yaw_engage_angle = 0.14 if is_slide_style else 0.10
	_base_stability_yaw_strength = float(p["stability_yaw_strength"]) * (1.0 if esp_on else 0.45)
	stability_yaw_strength = _base_stability_yaw_strength
	stability_yaw_ground_multiplier = float(p["stability_yaw_ground_multiplier"]) * (1.0 if esp_on else 0.45)
	stability_upright_spring = 4.5
	stability_upright_damping = 1800.0

	front_spring_length = float(p["spring_length_front"])
	rear_spring_length = float(p["spring_length_rear"])
	front_resting_ratio = 0.55
	rear_resting_ratio = 0.55
	front_damping_ratio = float(p["damping_ratio"])
	rear_damping_ratio = float(p["damping_ratio"])
	front_arb_ratio = 0.45
	rear_arb_ratio = 0.45

	front_tire_radius = 0.34
	rear_tire_radius = 0.35
	front_tire_width = 255.0
	rear_tire_width = 305.0 if car_style == "drift" else 275.0
	contact_patch = 0.22
	braking_grip_multiplier = 2.0
	_base_tcs_max_slip = 10.0
	traction_control_max_slip = _base_tcs_max_slip

	var road_cof := float(p["road_cof"])
	var dirt_cof := float(p["dirt_cof"])
	var grass_cof := float(p["grass_cof"])
	var kerb_cof := float(p["kerb_cof"])
	var lat_assist := float(p["lateral_grip_assist"])
	var long_ratio := float(p["longitudinal_grip_ratio"])

	tire_stiffnesses = {"Road": 12.0, "Kerb": 9.0, "Dirt": 4.0, "Grass": 3.5}
	coefficient_of_friction = {"Road": road_cof, "Kerb": kerb_cof, "Dirt": dirt_cof, "Grass": grass_cof}
	rolling_resistance = {"Road": 0.9, "Kerb": 1.2, "Dirt": 2.1, "Grass": 2.8}
	lateral_grip_assist = {"Road": lat_assist, "Kerb": lat_assist * 0.7, "Dirt": 0.02, "Grass": 0.0}
	longitudinal_grip_ratio = {"Road": long_ratio, "Kerb": long_ratio, "Dirt": 0.58, "Grass": 0.52}

	coefficient_of_drag = float(p["coefficient_of_drag"])
	frontal_area = 2.05
	downforce_coeff = float(p["downforce_coeff"])
	max_speed_kmh = float(p.get("max_speed_kmh", 258.0))
	nitro_force = float(p["nitro_force"])
	nitro_charge_mult = float(p["nitro_charge_mult"])
	drift_turn_rate = float(p.get("drift_turn_rate", 1.04))
	drift_neutral_deg = float(p.get("drift_neutral_deg", 29.0))
	drift_max_deg = float(p.get("drift_max_deg", 39.0))
	drift_speed_retention = float(p.get("drift_speed_retention", 0.94))
	drift_charge_rate = float(p.get("drift_charge_rate", 1.05))
	enable_arcade_drift = is_player

	# Physics layers: Vehicle on Layer 3 (4), collides with Road(1) + Barriers(2) + Vehicles(4)
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true

	var pmat := PhysicsMaterial.new()
	pmat.friction = 0.08
	pmat.bounce = 0.12
	physics_material_override = pmat

	# Ensure wheel raycasts ONLY hit RoadSurface (Layer 1)
	for w in [front_left_wheel, front_right_wheel, rear_left_wheel, rear_right_wheel]:
		if w:
			w.collision_mask = 1
			w.exclude_parent = true

	# Build sculpted 3D chassis & wheels
	_visual_root = get_node_or_null("VisualRoot")
	if _visual_root == null:
		_visual_root = Node3D.new()
		_visual_root.name = "VisualRoot"
		add_child(_visual_root)

	var built := CarMeshBuilder.build_car_visuals(_visual_root, str(spec["style"]), livery, false)
	_brake_mat = built["brake_mat"]
	_flame_mat = built.get("flame_mat", null)
	_nitro_flames.clear()
	for f in built["nitro_flames"]:
		_nitro_flames.append(f)

	var rim_col: Color = livery["rim"]
	if front_left_wheel and front_left_wheel.wheel_node:
		CarMeshBuilder.build_wheel_visual(front_left_wheel.wheel_node, front_tire_radius, 0.28, rim_col)
	if front_right_wheel and front_right_wheel.wheel_node:
		CarMeshBuilder.build_wheel_visual(front_right_wheel.wheel_node, front_tire_radius, 0.28, rim_col)
	if rear_left_wheel and rear_left_wheel.wheel_node:
		CarMeshBuilder.build_wheel_visual(rear_left_wheel.wheel_node, rear_tire_radius, 0.32, rim_col)
	if rear_right_wheel and rear_right_wheel.wheel_node:
		CarMeshBuilder.build_wheel_visual(rear_right_wheel.wheel_node, rear_tire_radius, 0.32, rim_col)

	_setup_fx()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	initialize()
	max_handbrake_force *= 1.65


func _setup_fx() -> void:
	# Rear tire drift smoke particles (CPUParticles3D works everywhere including GL Compatibility)
	if _smoke_left == null:
		_smoke_left = _create_smoke_emitter(Vector3(-0.82, 0.08, 1.30))
		add_child(_smoke_left)
	if _smoke_right == null:
		_smoke_right = _create_smoke_emitter(Vector3(0.82, 0.08, 1.30))
		add_child(_smoke_right)
	if _spark_particles == null:
		_spark_particles = _create_spark_emitter()
		add_child(_spark_particles)

	# Player headlights for night circuit
	if is_player and is_night_track and _headlight_spot == null:
		_headlight_spot = SpotLight3D.new()
		_headlight_spot.name = "HeadlightBeam"
		_headlight_spot.position = Vector3(0.0, 0.72, -1.95)
		_headlight_spot.light_color = Color(0.95, 0.98, 1.0)
		_headlight_spot.light_energy = 5.5
		_headlight_spot.spot_range = 68.0
		_headlight_spot.spot_angle = 40.0
		_headlight_spot.shadow_enabled = false
		add_child(_headlight_spot)

	# World-space skidmark mesh attached to parent scene once in tree
	if is_player and _skid_mesh_inst == null:
		_skid_mesh_inst = MeshInstance3D.new()
		_skid_mesh_inst.name = "PlayerSkidmarks"
		_skid_mesh_inst.top_level = true
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.04, 0.04, 0.05, 0.62)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.roughness = 0.95
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_skid_mesh_inst.material_override = smat
		_skid_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_skid_mesh_inst)


func _create_smoke_emitter(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = pos
	p.emitting = false
	p.amount = 22
	p.lifetime = 0.65
	p.local_coords = false
	p.direction = Vector3(0.0, 0.6, 1.0)
	p.spread = 28.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0.0, 1.4, 0.0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.95

	var mesh := SphereMesh.new()
	mesh.radius = 0.36
	mesh.height = 0.72
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.90, 0.94, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.mesh = mesh
	return p


func _create_spark_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = Vector3(0.0, 0.55, 0.0)
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 18
	p.lifetime = 0.32
	p.local_coords = false
	p.direction = Vector3(0.0, 1.0, 0.5)
	p.spread = 80.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 14.0
	p.gravity = Vector3(0.0, -14.0, 0.0)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.24)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.68, 0.12)
	mat.emission_energy_multiplier = 4.0
	mesh.material = mat
	p.mesh = mesh
	return p


func get_speed_kmh() -> float:
	return speed * 3.6


func trigger_launch_control() -> bool:
	# Reward revving in sweet spot (50%-95% RPM) when race lights go green!
	var rpm_ratio := motor_rpm / maxf(max_rpm, 1.0)
	if rpm_ratio >= 0.45 and throttle_input > 0.3:
		launch_boost_timer = 0.95
		nitro = minf(100.0, nitro + 15.0)
		return true
	return false


func trigger_boost_pad() -> void:
	if boost_pad_timer > 0.8:
		return
	boost_pad_timer = 1.5
	nitro = minf(100.0, nitro + 22.0)
	boost_pad_hit.emit()


func reset_to_transform(xf: Transform3D) -> void:
	reset_vehicle_physics(xf)
	arcade_drift_active = false
	arcade_drift_override = false
	drift_dir = 0.0
	drift_duration = 0.0
	drift_charge_progress = 0.0
	drift_boost_tier = 0
	drift_exit_boost_timer = 0.0
	drift_exit_boost_tier = 0
	_drift_travel_dir = -xf.basis.z
	_drift_entry_speed = 0.0
	_drift_speed = 0.0
	_drift_slip_rad = 0.0
	_drift_exit_timer = 0.0
	_drift_air_timer = 0.0
	_drift_arm_timer = 0.0
	_drift_straighten_timer = 0.0
	_drift_wall_resync_timer = 0.0
	_drift_steer_smooth = 0.0
	_prev_handbrake_down = false
	_prev_brake_down = false
	is_drifting = false
	drift_angle_deg = 0.0
	current_drift_score = 0.0
	nitro_active = false
	boost_pad_timer = 0.0
	launch_boost_timer = 0.0
	traction_control_max_slip = _base_tcs_max_slip
	stability_yaw_strength = _base_stability_yaw_strength
	_last_skid_valid = [false, false]


func _get_road_up() -> Vector3:
	var n := Vector3.ZERO
	var hits := 0
	for w in wheel_array:
		if w != null and w.is_colliding():
			n += w.last_collision_normal
			hits += 1
	if hits == 0 or n.length_squared() < 0.001:
		return Vector3.UP
	var avg := n.normalized()
	if avg.y < 0.55:
		return Vector3.UP
	return avg.lerp(Vector3.UP, 0.18).normalized()


func _enter_arcade_drift(dir: float) -> void:
	var road_up := _get_road_up()
	var horiz := linear_velocity.slide(road_up)
	var spd_now := horiz.length()
	var travel := horiz.normalized() if spd_now > 3.0 else (-global_transform.basis.z).slide(road_up).normalized()
	if travel.length_squared() < 0.001:
		travel = -global_transform.basis.z

	arcade_drift_active = true
	arcade_drift_override = true
	drift_dir = signf(dir)
	if is_zero_approx(drift_dir):
		drift_dir = 1.0
	drift_duration = 0.0
	drift_charge_progress = 0.0
	drift_boost_tier = 0
	_drift_entry_speed = maxf(spd_now, 14.0)
	_drift_speed = _drift_entry_speed
	_drift_travel_dir = travel
	_drift_slip_rad = clampf(deg_to_rad(16.0), deg_to_rad(10.0), deg_to_rad(drift_neutral_deg))
	_drift_exit_timer = 0.0
	_drift_air_timer = 0.0
	_drift_arm_timer = 0.0
	_drift_straighten_timer = 0.0
	_drift_wall_resync_timer = 0.0
	_drift_steer_smooth = 0.25
	brake_amount = 0.0
	is_drifting = true
	drift_bank_timer = 0.90


func _fire_drift_exit_boost(tier: int, boost_dir: Vector3) -> void:
	if tier < 1:
		return
	var clamped_tier := clampi(tier, 1, 3)
	drift_exit_boost_tier = clamped_tier
	var dur := 0.68
	var speed_kick := 5.2
	var nitro_bonus := 8.0
	var cap_bonus := 22.0
	if clamped_tier == 2:
		dur = 1.08
		speed_kick = 8.6
		nitro_bonus = 16.0
		cap_bonus = 34.0
	elif clamped_tier >= 3:
		dur = 1.52
		speed_kick = 12.2
		nitro_bonus = 26.0
		cap_bonus = 46.0

	drift_exit_boost_timer = maxf(drift_exit_boost_timer, dur)
	nitro = minf(100.0, nitro + nitro_bonus)

	var max_v := (max_speed_kmh + cap_bonus) / 3.6
	var road_up := _get_road_up()
	var d := boost_dir.slide(road_up)
	if d.length_squared() > 0.001:
		d = d.normalized()
		var vel_up := linear_velocity.dot(road_up)
		var new_spd := minf(_drift_speed + speed_kick, max_v)
		_drift_speed = new_spd
		linear_velocity = d * new_spd + road_up * vel_up

	drift_boost_triggered.emit(clamped_tier)


func _exit_arcade_drift(allow_boost: bool) -> void:
	if not arcade_drift_active:
		return
	var earned_tier := drift_boost_tier
	var exit_dir := _drift_travel_dir
	var road_up := _get_road_up()

	arcade_drift_active = false
	arcade_drift_override = false
	_drift_straighten_timer = 0.28
	steering_amount = clampf(steering_input * 0.4, -0.5, 0.5)

	# Keep velocity smoothly aligned with exit heading while preserving vertical suspension motion
	var vel_up := linear_velocity.dot(road_up)
	var clean_dir := exit_dir.slide(road_up)
	if clean_dir.length_squared() > 0.001:
		clean_dir = clean_dir.normalized()
		linear_velocity = clean_dir * _drift_speed + road_up * vel_up

	if allow_boost and earned_tier >= 1:
		_fire_drift_exit_boost(earned_tier, exit_dir)

	drift_dir = 0.0
	drift_duration = 0.0
	drift_charge_progress = 0.0
	drift_boost_tier = 0
	_drift_exit_timer = 0.0
	_drift_air_timer = 0.0
	is_drifting = false
	drift_bank_timer = 0.90


func _process_arcade_drift(delta: float, hb_just_pressed: bool) -> void:
	var road_up := _get_road_up()
	var grounded := get_wheel_contact_count() >= 2

	if grounded:
		_drift_air_timer = 0.0
	else:
		_drift_air_timer += delta
		if _drift_air_timer > 0.35:
			_exit_arcade_drift(false)
			return

	# Continuously sync with guardrail / rival contact so cars glide smoothly along walls without climbing or sticking!
	var touching_barrier := false
	for b in get_colliding_bodies():
		if not (b.is_in_group("Road") or b.is_in_group("Kerb") or b.is_in_group("Grass") or b.is_in_group("Dirt")):
			touching_barrier = true
			break

	var actual_horiz := linear_velocity.slide(road_up)
	var actual_spd := actual_horiz.length()
	if touching_barrier or _drift_wall_resync_timer > 0.0:
		_drift_wall_resync_timer = maxf(0.0, _drift_wall_resync_timer - delta)
		if actual_spd > 4.0:
			var sync_rate := 16.0 if touching_barrier else 10.0
			_drift_travel_dir = _drift_travel_dir.lerp(actual_horiz.normalized(), clampf(delta * sync_rate, 0.0, 1.0)).slide(road_up).normalized()
			_drift_speed = lerpf(_drift_speed, minf(_drift_speed, maxf(actual_spd, _drift_speed * 0.86)), clampf(delta * 10.0, 0.0, 1.0))
	elif actual_spd < _drift_speed * 0.78 and actual_spd > 3.0:
		_drift_travel_dir = _drift_travel_dir.lerp(actual_horiz.normalized(), 0.45).slide(road_up).normalized()
		_drift_speed = lerpf(_drift_speed, actual_spd, 0.35)

	var steer_in := steering_input * drift_dir # +1 inside tighten, 0 neutral arc, -1 outward widen/exit

	# S-Curve Instant Chain Switch: tap Space while steering opposite direction!
	if hb_just_pressed and steer_in < -0.35 and drift_duration > 0.20:
		if drift_boost_tier >= 1:
			_fire_drift_exit_boost(drift_boost_tier, _drift_travel_dir)
		drift_dir = -drift_dir
		drift_duration = 0.0
		drift_charge_progress = 0.0
		drift_boost_tier = 0
		_drift_exit_timer = 0.0
		_drift_entry_speed = maxf(_drift_speed, _drift_entry_speed * 0.96)
		_drift_slip_rad = deg_to_rad(14.0)
		steer_in = steering_input * drift_dir

	# Speed control: Ridge Racer / Asphalt near-zero speed loss + nitro drifting!
	var boost_extra_kmh := 0.0
	if nitro_active or boost_pad_timer > 0.0:
		boost_extra_kmh = maxf(boost_extra_kmh, 35.0)
	if drift_exit_boost_timer > 0.0:
		boost_extra_kmh = maxf(boost_extra_kmh, 22.0 + float(drift_exit_boost_tier - 1) * 12.0)

	var top_drift_v := (max_speed_kmh * drift_speed_retention + boost_extra_kmh) / 3.6
	var min_cruise_v := _drift_entry_speed * drift_speed_retention
	var brake_drag := brake_input > 0.40 and drift_duration > 0.14

	if brake_drag:
		_drift_speed = maxf(0.0, _drift_speed - 19.0 * brake_input * delta)
	elif nitro_active or boost_pad_timer > 0.0 or drift_exit_boost_timer > 0.0:
		_drift_speed = minf((max_speed_kmh + boost_extra_kmh) / 3.6, _drift_speed + 15.0 * delta)
	elif throttle_input > 0.20:
		var hold_target := clampf(_drift_entry_speed * (drift_speed_retention + 0.03), 30.0, top_drift_v)
		if _drift_speed < hold_target:
			var accel_rate := 3.8 * throttle_input * clampf(1.0 - (_drift_speed / maxf(top_drift_v, 1.0)) * 0.55, 0.25, 1.0)
			_drift_speed = minf(hold_target, _drift_speed + accel_rate * delta)
		else:
			# Ultra-gentle bleed down only to min_cruise_v (93%-97% of entry speed!)
			var floor_v := minf(min_cruise_v, top_drift_v)
			_drift_speed = lerpf(_drift_speed, floor_v, clampf(delta * 0.85, 0.0, 1.0))
	else:
		_drift_speed = maxf(0.0, _drift_speed - 4.8 * delta)

	# Exit conditions: too slow, sustained full counter-steer hold, or clean straight release
	if _drift_speed * 3.6 < 36.0:
		_exit_arcade_drift(false)
		return

	var want_counter_exit := (steer_in < -0.55 and handbrake_input < 0.20)
	var want_straight_exit := (absf(steering_input) < 0.15 and handbrake_input < 0.20 and drift_duration > 0.25)
	if want_counter_exit:
		_drift_exit_timer += delta * 2.2
		if _drift_exit_timer >= 0.52:
			_exit_arcade_drift(true)
			return
	elif want_straight_exit:
		_drift_exit_timer += delta
		if _drift_exit_timer >= 0.55:
			_exit_arcade_drift(true)
			return
	else:
		_drift_exit_timer = maxf(0.0, _drift_exit_timer - delta * 4.5)

	# Smooth binary keyboard steering into silky analog corner curvature control!
	_drift_steer_smooth = lerpf(_drift_steer_smooth, steer_in, clampf(delta * 9.5, 0.0, 1.0))

	# Curvature-calibrated corner carving (matched to real track radii R=27m..180m+):
	#   Outer (-0.5..-1.0) -> R ~ 900m (widen cleanly all the way straight!)
	#   Neutral (0.0)      -> R ~ 135-160m (carves sweeping curves hands-free!)
	#   Inside (+1.0)      -> R ~ 42-52m (hugs tight hairpins)
	#   Inside + Space     -> R ~ 26-32m (nails sharpest mountain hairpins & neon chicanes!)
	var kappa := lerpf(0.0062, 0.0195, _drift_steer_smooth) if _drift_steer_smooth >= 0.0 else lerpf(0.0062, 0.0009, clampf(-_drift_steer_smooth / 0.52, 0.0, 1.0))
	if handbrake_input > 0.25:
		kappa += 0.0110
	if brake_drag:
		kappa += 0.0090
	var yaw_turn_rate := clampf(_drift_speed * kappa * drift_turn_rate, 0.03, 1.85)
	_drift_travel_dir = _drift_travel_dir.rotated(road_up, drift_dir * yaw_turn_rate * delta).slide(road_up)
	if _drift_travel_dir.length_squared() < 0.001:
		_drift_travel_dir = (-global_transform.basis.z).slide(road_up)
	_drift_travel_dir = _drift_travel_dir.normalized()

	# Dramatic controllable body slip angle (stays wide & photogenic even when widening!)
	var target_deg := lerpf(drift_neutral_deg, drift_max_deg, _drift_steer_smooth) if _drift_steer_smooth >= 0.0 else lerpf(drift_neutral_deg, maxf(18.0, drift_neutral_deg * 0.65), -_drift_steer_smooth)
	if handbrake_input > 0.25:
		target_deg = minf(drift_max_deg + 3.0, target_deg + 3.0)
	_drift_slip_rad = lerpf(_drift_slip_rad, deg_to_rad(target_deg), clampf(delta * 9.5, 0.0, 1.0))

	# Set road-tangent velocity while keeping vertical suspension velocity clamped against kerb launches
	var vel_up := clampf(linear_velocity.dot(road_up), -8.0, 2.2)
	linear_velocity = _drift_travel_dir * _drift_speed + road_up * vel_up

	# PD yaw lock toward dramatic nose angle + active upright roll-lock (impossible to spin out or tip over!)
	var target_nose := _drift_travel_dir.rotated(road_up, drift_dir * _drift_slip_rad).slide(road_up).normalized()
	var cur_fwd := (-global_transform.basis.z).slide(road_up)
	if cur_fwd.length_squared() > 0.001:
		cur_fwd = cur_fwd.normalized()
		var yaw_err := atan2(cur_fwd.cross(target_nose).dot(road_up), clampf(cur_fwd.dot(target_nose), -1.0, 1.0))
		var ang_up := angular_velocity.dot(road_up)
		var ang_pitch_roll := angular_velocity - road_up * ang_up
		var desired_yaw_rate := clampf(yaw_err * 10.0, -5.4, 5.4) + drift_dir * yaw_turn_rate
		var new_ang_up := lerpf(ang_up, desired_yaw_rate, clampf(delta * 16.0, 0.0, 1.0))
		# Active upright stabilization keeps all 4 tires planted over kerbs and guardrail taps
		var upright_err := global_transform.basis.y.cross(road_up)
		var upright_pr := upright_err - road_up * upright_err.dot(road_up)
		var stabilized_pr := ang_pitch_roll * maxf(0.0, 1.0 - delta * 8.0) + upright_pr * 12.0
		angular_velocity = stabilized_pr + road_up * new_ang_up

	# Visual front wheel counter-steering into the slide (iconic Ridge Racer / Drift King silhouette!)
	var cs_ratio := clampf(0.76 - steer_in * 0.18, 0.54, 0.96)
	var wheel_yaw := clampf(-drift_dir * _drift_slip_rad * cs_ratio, -0.68, 0.68)
	for fw in [front_left_wheel, front_right_wheel]:
		if fw != null:
			fw.rotation.y = lerpf(fw.rotation.y, wheel_yaw, clampf(delta * 18.0, 0.0, 1.0))

	# Keep engine revving aggressively through the drift for exhilarating engine audio
	var min_drift_rpm := lerpf(idle_rpm * 1.4, max_rpm * 0.80, clampf(_drift_speed / 56.0, 0.25, 1.0))
	motor_rpm = maxf(motor_rpm, min_drift_rpm)

	# 3-Tier Exit Mini-Turbo charging + Drift Score + Rapid Nitro Recharge
	drift_duration += delta
	drift_angle_deg = rad_to_deg(_drift_slip_rad)
	is_drifting = true
	drift_bank_timer = 0.90
	wheel_slip_intensity = clampf(0.75 + (_drift_slip_rad / 0.8) * 0.65, 0.75, 1.45)

	var angle_bonus := 0.88 + 0.30 * clampf(drift_angle_deg / 35.0, 0.0, 1.3)
	var tier_speed := 1.85 if drift_charge_progress < 1.0 else (1.30 if drift_charge_progress < 2.0 else 1.05)
	drift_charge_progress = minf(3.0, drift_charge_progress + delta * tier_speed * drift_charge_rate * angle_bonus)
	drift_boost_tier = int(floorf(drift_charge_progress))

	var score_rate := (_drift_speed * 3.6 * 0.95 + drift_angle_deg * 10.5) * nitro_charge_mult * drift_charge_rate * delta
	current_drift_score += score_rate
	nitro = minf(100.0, nitro + 24.0 * nitro_charge_mult * delta)


func _physics_process(delta: float) -> void:
	if not is_ready:
		return

	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)

	# Hold vehicle cleanly on starting grid during 3-2-1 countdown while letting engine rev!
	if controls_locked:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		arcade_drift_active = false
		arcade_drift_override = false
		for w in wheel_array:
			w.force_raycast_update()
			if w.is_colliding():
				w.spring_current_length = clampf(w.get_collision_point().distance_to(w.global_position) - w.tire_radius, 0.0, w.spring_length)
		var target_rpm := lerpf(idle_rpm, max_rpm * 0.84, clampf(throttle_input, 0.0, 1.0))
		motor_rpm = lerpf(motor_rpm, target_rpm, delta * 6.5)
		current_gear = 0
		is_drifting = false
		nitro_active = false
		_update_visual_fx(delta)
		return

	var hb_down := handbrake_input > 0.25
	var hb_just_pressed := hb_down and not _prev_handbrake_down
	var brake_down := brake_input > 0.35
	var brake_just_pressed := brake_down and not _prev_brake_down
	_prev_handbrake_down = hb_down
	_prev_brake_down = brake_down

	var pre_grounded := get_wheel_contact_count() >= 2
	var pre_speed_kmh := linear_velocity.length() * 3.6

	# Check Ridge Racer / Asphalt Arcade Rail-Drift Entry BEFORE GEVP tire forces run!
	if enable_arcade_drift and not arcade_drift_active:
		if hb_just_pressed:
			_drift_arm_timer = 0.28
		elif hb_down:
			_drift_arm_timer = maxf(_drift_arm_timer, 0.10)
		else:
			_drift_arm_timer = maxf(0.0, _drift_arm_timer - delta)

		if pre_grounded and current_gear >= 0:
			var trigger_dir := 0.0
			if _drift_arm_timer > 0.0 and pre_speed_kmh >= 46.0:
				if absf(steering_input) > 0.15:
					trigger_dir = signf(steering_input)
				elif hb_just_pressed and absf(angular_velocity.y) > 0.30:
					trigger_dir = signf(angular_velocity.y)
			elif brake_just_pressed and pre_speed_kmh >= 76.0 and absf(steering_input) > 0.35:
				# Asphalt / Burnout Brake-to-Drift!
				trigger_dir = signf(steering_input)

			if not is_zero_approx(trigger_dir):
				_enter_arcade_drift(trigger_dir)

	arcade_drift_override = arcade_drift_active

	if not arcade_drift_active:
		# Standard GEVP grip & AI drift assist
		var drift_relax := handbrake_input > 0.2 or (is_drifting and is_player)
		if drift_relax:
			traction_control_max_slip = -1.0
			if drift_angle_deg < 32.0:
				stability_yaw_strength = _base_stability_yaw_strength * 0.25
			else:
				var catch_t := clampf((drift_angle_deg - 32.0) / 14.0, 0.0, 1.0)
				stability_yaw_strength = lerpf(_base_stability_yaw_strength * 0.25, _base_stability_yaw_strength * 1.5, catch_t)
		else:
			traction_control_max_slip = _base_tcs_max_slip
			stability_yaw_strength = _base_stability_yaw_strength

		for rw in [rear_left_wheel, rear_right_wheel]:
			if rw != null and rw.surface_type != "":
				var base_cof: float = float(rw.coefficient_of_friction.get(rw.surface_type, 2.5))
				if handbrake_input > 0.2 and speed > 8.0 and drift_angle_deg < 28.0:
					rw.current_cof = base_cof * (0.56 if car_style == "drift" else 0.74)
				elif is_player and is_drifting and car_style == "drift" and throttle_input > 0.30 and absf(steering_input) > 0.20 and drift_angle_deg < 34.0:
					rw.current_cof = base_cof * 0.74
				else:
					rw.current_cof = base_cof

	# Run core GEVP raycast vehicle simulation (suspension always active; tires bypassed during arcade drift)
	super._physics_process(delta)

	# Emit gear change notification for audio shift pop
	if current_gear != _prev_gear:
		if _prev_gear > 0 and current_gear > 0:
			gear_changed.emit(current_gear)
		_prev_gear = current_gear

	var grounded := get_wheel_contact_count() >= 2
	var forward_dir := -global_transform.basis.z
	var forward_speed := -local_velocity.z

	# 1. Aerodynamic Downforce (keeps race cars glued to asphalt at high speeds)
	if grounded and speed > 8.0:
		var df := downforce_coeff * speed * speed
		apply_central_force(-global_transform.basis.y * df)

	# 2. Progressive anti-rollover stabilization (only activates past 33 deg tilt; damps pitch/roll only, never steering yaw!)
	if global_transform.basis.y.y < 0.84:
		var upright_axis := global_transform.basis.y.cross(Vector3.UP)
		var severity := clampf((0.84 - global_transform.basis.y.y) / 0.42, 0.0, 1.8)
		var pr_ang := Vector3(angular_velocity.x, 0.0, angular_velocity.z)
		apply_torque(upright_axis * vehicle_mass * (22.0 + 38.0 * severity) - pr_ang * vehicle_mass * 2.2)

	# 3. Nitro Boost, Boost Pad, Launch Control & Drift Exit Mini-Turbo Thrust
	var want_nitro := nitro_input and nitro > 2.0 and (arcade_drift_active or forward_speed > 2.0) and current_gear >= 0
	if want_nitro:
		nitro_active = true
		nitro = maxf(0.0, nitro - 27.0 * delta)
		if grounded and not arcade_drift_active:
			apply_central_force(forward_dir * nitro_force)
	else:
		nitro_active = false
		nitro = minf(100.0, nitro + 2.8 * delta)

	if boost_pad_timer > 0.0:
		boost_pad_timer = maxf(0.0, boost_pad_timer - delta)
		if grounded and brake_input < 0.35 and not arcade_drift_active:
			apply_central_force(forward_dir * (nitro_force * 1.15))

	if launch_boost_timer > 0.0:
		launch_boost_timer = maxf(0.0, launch_boost_timer - delta)
		if grounded and not arcade_drift_active:
			apply_central_force(forward_dir * (nitro_force * 0.85))

	if drift_exit_boost_timer > 0.0:
		drift_exit_boost_timer = maxf(0.0, drift_exit_boost_timer - delta)
		if grounded and brake_input < 0.40 and not arcade_drift_active:
			var tier_mult := 0.82 + float(drift_exit_boost_tier) * 0.28
			apply_central_force(forward_dir * (nitro_force * tier_mult))
		if drift_exit_boost_timer <= 0.0:
			drift_exit_boost_tier = 0

	# 4. Execute Arcade Rail-Drift OR Standard GEVP Drift Handling
	if arcade_drift_active:
		_process_arcade_drift(delta, hb_just_pressed)
	else:
		# Smooth laser-straightening right after exiting an arcade drift (zero whip-back!)
		if _drift_straighten_timer > 0.0:
			_drift_straighten_timer = maxf(0.0, _drift_straighten_timer - delta)
			var road_up := _get_road_up()
			var horiz := linear_velocity.slide(road_up)
			if grounded and horiz.length() > 8.0:
				var vel_dir := horiz.normalized()
				var cur_fwd := (-global_transform.basis.z).slide(road_up).normalized()
				var yaw_err := atan2(cur_fwd.cross(vel_dir).dot(road_up), clampf(cur_fwd.dot(vel_dir), -1.0, 1.0))
				var ang_up := angular_velocity.dot(road_up)
				var ang_pr := angular_velocity - road_up * ang_up
				var desired_up := clampf(yaw_err * 9.0, -4.2, 4.2)
				angular_velocity = ang_pr + road_up * lerpf(ang_up, desired_up, clampf(delta * 14.0, 0.0, 1.0))

		# Progressive drift angle limiter for AI / non-arcade slides
		var catch_deg := 36.0 if car_style == "drift" else (26.0 if car_style == "rally" else (21.0 if car_style == "formula" else 22.0))
		if grounded and speed > 6.0 and drift_angle_deg > catch_deg:
			var slip_sign := signf(local_velocity.x)
			var excess := clampf((drift_angle_deg - catch_deg) / 14.0, 0.0, 1.8)
			var restore_gain := 2.0 if car_style == "drift" else (4.6 if car_style == "rally" else 6.8)
			var restore_yaw := -slip_sign * vehicle_mass * restore_gain * excess
			var damp_yaw := -angular_velocity.y * vehicle_mass * 2.8 * excess
			apply_torque(global_transform.basis.y * (restore_yaw + damp_yaw))

		var max_slip := 0.0
		for w in [rear_left_wheel, rear_right_wheel]:
			if w and w.is_colliding():
				max_slip = maxf(max_slip, absf(w.slip_vector.x) + absf(w.slip_vector.y) * 0.45)
		wheel_slip_intensity = clampf(max_slip * 0.65, 0.0, 1.5)

		drift_angle_deg = rad_to_deg(atan2(absf(local_velocity.x), maxf(2.0, forward_speed)))
		var speed_kmh := speed * 3.6
		if grounded and speed_kmh > 40.0 and (drift_angle_deg > 10.5 or (handbrake_input > 0.4 and drift_angle_deg > 5.5)):
			is_drifting = true
			drift_bank_timer = 0.75
			var rate := (speed_kmh * 0.75 + drift_angle_deg * 8.0) * nitro_charge_mult * delta
			current_drift_score += rate
			nitro = minf(100.0, nitro + 21.0 * nitro_charge_mult * delta)
		else:
			is_drifting = false
			if current_drift_score > 0.0:
				drift_bank_timer -= delta
				if drift_bank_timer <= 0.0:
					total_drift_score += int(round(current_drift_score))
					current_drift_score = 0.0

	# In-physics guardrail corridor wall-glide containment (prevents high-speed wall tunneling!)
	_enforce_track_corridor()

	# Per-car top speed cap (+35 km/h on Nitro/Pad, up to +46 km/h on LV.3 Drift Exit Boost!)
	var cap_bonus := 0.0
	if nitro_active or boost_pad_timer > 0.0:
		cap_bonus = maxf(cap_bonus, 35.0)
	if drift_exit_boost_timer > 0.0:
		cap_bonus = maxf(cap_bonus, 22.0 + float(drift_exit_boost_tier - 1) * 12.0)
	var max_v := (max_speed_kmh + cap_bonus) / 3.6
	if linear_velocity.length() > max_v:
		linear_velocity = linear_velocity.normalized() * max_v

	_update_visual_fx(delta)


func set_track_bounds(p_spline: TrackSpline, p_barrier_offset: float) -> void:
	track_spline = p_spline
	barrier_corridor_half_width = maxf(0.0, p_barrier_offset - 1.05)


func _enforce_track_corridor() -> void:
	if track_spline == null or barrier_corridor_half_width <= 2.0:
		return
	var prog := track_spline.get_progress(global_position, spline_index)
	var road_pt: Vector3 = prog["closest_point"]
	# Ignore if running on an elevated test skidpad far above the track
	if absf(global_position.y - road_pt.y) > 8.0:
		return
	spline_index = int(prog["index"])
	var lat: float = float(prog["lateral"])
	var max_lat: float = barrier_corridor_half_width
	if absf(lat) < max_lat:
		return

	var side := signf(lat)
	var track_right: Vector3 = prog["right"]
	var outward := track_right * side
	var out_vel := linear_velocity.dot(outward)
	if out_vel > 0.0:
		linear_velocity -= outward * (out_vel * 1.12)
		if linear_velocity.y > 1.8:
			linear_velocity.y = 1.8

	if arcade_drift_active:
		var td_out := _drift_travel_dir.dot(outward)
		if td_out > 0.0:
			var road_up := _get_road_up()
			var glided := (_drift_travel_dir - outward * (td_out + 0.06)).slide(road_up)
			if glided.length_squared() > 0.001:
				_drift_travel_dir = glided.normalized()
		_drift_speed = minf(_drift_speed, maxf(linear_velocity.length(), _drift_speed * 0.94))

	# Hard-clamp residual lateral penetration so car can never squeeze past the guardrail
	var excess := absf(lat) - (max_lat + 0.25)
	if excess > 0.0 and excess < 4.5:
		global_position -= outward * excess
		angular_velocity.x *= 0.45
		angular_velocity.z *= 0.45


func _update_visual_fx(delta: float) -> void:
	# Dynamic brake light glow
	if _brake_mat:
		var braking_now := brake_input > 0.15 or handbrake_input > 0.2 or arcade_drift_active
		_brake_mat.emission_energy_multiplier = 4.5 if braking_now else (1.3 if is_night_track else 0.75)

	# Flickering Tier-Colored Exhaust Flames (LV.1 Cyan / LV.2 Gold / LV.3 Violet!)
	var exit_boost_on := drift_exit_boost_timer > 0.0
	var drift_charge_flames := arcade_drift_active and drift_boost_tier >= 1
	var flames_on := nitro_active or boost_pad_timer > 0.0 or launch_boost_timer > 0.0 or exit_boost_on or drift_charge_flames

	if _flame_mat and flames_on:
		var visual_tier := drift_exit_boost_tier if exit_boost_on else (drift_boost_tier if drift_charge_flames else 1)
		if visual_tier >= 3:
			_flame_mat.albedo_color = Color(0.84, 0.28, 1.0, 0.96)
			_flame_mat.emission = Color(0.92, 0.22, 1.0)
			_flame_mat.emission_energy_multiplier = 7.5 if exit_boost_on else 5.2
		elif visual_tier == 2:
			_flame_mat.albedo_color = Color(1.0, 0.78, 0.16, 0.96)
			_flame_mat.emission = Color(1.0, 0.64, 0.08)
			_flame_mat.emission_energy_multiplier = 6.5 if exit_boost_on else 4.6
		else:
			_flame_mat.albedo_color = Color(0.15, 0.85, 1.0, 0.92)
			_flame_mat.emission = Color(0.05, 0.78, 1.0)
			_flame_mat.emission_energy_multiplier = 5.5 if not drift_charge_flames else 3.8

	for fl in _nitro_flames:
		fl.visible = flames_on
		if flames_on:
			var scale_base := 1.0
			if exit_boost_on:
				scale_base = 1.15 + float(drift_exit_boost_tier) * 0.24
			elif drift_charge_flames and not (nitro_active or boost_pad_timer > 0.0):
				scale_base = 0.52 + float(drift_boost_tier) * 0.14
			var jitter := randf_range(0.80, 1.32) * scale_base
			fl.scale = Vector3(minf(1.35, 0.9 + scale_base * 0.18), jitter, minf(1.35, 0.9 + scale_base * 0.18))

	# Rear Tire Drift Smoke
	var show_smoke := (not controls_locked) and (arcade_drift_active or is_drifting or wheel_slip_intensity > 0.55) and get_wheel_contact_count() >= 2
	if _smoke_left:
		_smoke_left.emitting = show_smoke
	if _smoke_right:
		_smoke_right.emitting = show_smoke

	# Player Asphalt Skidmarks Ribbon
	if is_player and _skid_mesh_inst != null:
		_update_skidmarks(show_smoke, delta)


func _update_skidmarks(active: bool, delta: float) -> void:
	var rear_wheels := [rear_left_wheel, rear_right_wheel]
	var added := false
	for i in range(2):
		var w: Wheel = rear_wheels[i]
		if active and w != null and w.is_colliding():
			var pt := w.last_collision_point + w.last_collision_normal * 0.045
			if _last_skid_valid[i]:
				var d := _last_skid_pos[i].distance_to(pt)
				if d > 0.45 and d < 4.5:
					var right_v := global_transform.basis.x * 0.15
					_skid_segments.append({
						"a": _last_skid_pos[i],
						"b": pt,
						"r": right_v
					})
					if _skid_segments.size() > 140:
						_skid_segments.pop_front()
					_last_skid_pos[i] = pt
					added = true
			else:
				_last_skid_pos[i] = pt
				_last_skid_valid[i] = true
		else:
			_last_skid_valid[i] = false

	_skid_rebuild_accum += delta
	if added and _skid_rebuild_accum >= 0.05:
		_skid_rebuild_accum = 0.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for seg in _skid_segments:
			var a: Vector3 = seg["a"]
			var b: Vector3 = seg["b"]
			var r: Vector3 = seg["r"]
			st.add_vertex(a - r); st.add_vertex(b - r); st.add_vertex(b + r)
			st.add_vertex(a - r); st.add_vertex(b + r); st.add_vertex(a + r)
		_skid_mesh_inst.mesh = st.commit()


func _on_body_entered(body: Node) -> void:
	if controls_locked:
		return
	if body.is_in_group("Road") or body.is_in_group("Kerb") or body.is_in_group("Grass") or body.is_in_group("Dirt"):
		return
	# Prevent high-speed guardrail impacts from launching or barrel-rolling the vehicle
	if body is StaticBody3D and (linear_velocity.y > 2.2 or global_transform.basis.y.y < 0.88):
		linear_velocity.y = minf(linear_velocity.y, 1.5)
		angular_velocity.x *= 0.35
		angular_velocity.z *= 0.35
	if _impact_cooldown > 0.0:
		return
	var intensity := clampf(speed / 45.0, 0.15, 1.0)
	if arcade_drift_active:
		_drift_wall_resync_timer = 0.16
		if intensity > 0.85 and linear_velocity.length() * 3.6 < 52.0:
			_exit_arcade_drift(false)
	if intensity > 0.22:
		_impact_cooldown = 0.28
		if _spark_particles:
			_spark_particles.restart()
			_spark_particles.emitting = true
		# Cancel part of unbanked drift only on heavy high-speed wall slam (allow light drift wall taps!)
		if intensity > 0.72:
			current_drift_score *= 0.35
		impact_occurred.emit(intensity)

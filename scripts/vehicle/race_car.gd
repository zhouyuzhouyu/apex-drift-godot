class_name RaceCar
extends Vehicle

## Complete playable & AI RaceCar built on top of GEVP Vehicle.
## Adds Nitro Boost, Drift Detection/Scoring, Tire Smoke, Skidmarks, Aerodynamic Downforce,
## Headlights/Brake Lights, Collision Impacts, Launch Control, and Clean Spline Respawn.

signal impact_occurred(intensity: float)
signal boost_pad_hit
signal gear_changed(new_gear: int)

var car_id: String = "apex_gtr"
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
var boost_pad_timer: float = 0.0
var launch_boost_timer: float = 0.0

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

# Visual handles
var _visual_root: Node3D
var _brake_mat: StandardMaterial3D
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
	steering_slip_assist = 0.18
	countersteer_assist = float(p["countersteer_assist"])
	steering_exponent = 1.35

	var esp_on := true if (not is_player) else bool(GameState.settings.get("stability_assist", true))
	enable_stability = true
	stability_yaw_strength = float(p["stability_yaw_strength"]) * (1.0 if esp_on else 0.45)
	stability_yaw_ground_multiplier = float(p["stability_yaw_ground_multiplier"]) * (1.0 if esp_on else 0.45)
	stability_upright_spring = 1.6
	stability_upright_damping = 1200.0

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
	rear_tire_width = 275.0
	contact_patch = 0.22
	braking_grip_multiplier = 2.0
	traction_control_max_slip = 10.0

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
	nitro_force = float(p["nitro_force"])
	nitro_charge_mult = float(p["nitro_charge_mult"])

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
	is_drifting = false
	current_drift_score = 0.0
	nitro_active = false
	boost_pad_timer = 0.0
	launch_boost_timer = 0.0
	_last_skid_valid = [false, false]


func _physics_process(delta: float) -> void:
	if not is_ready:
		return

	_impact_cooldown = maxf(0.0, _impact_cooldown - delta)

	# Hold vehicle cleanly on starting grid during 3-2-1 countdown while letting engine rev!
	if controls_locked:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
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

	# Run core GEVP raycast vehicle simulation
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

	# 2. Anti-flip gentle upright torque if car ever rolls past 65 degrees
	if global_transform.basis.y.y < 0.42:
		var upright_axis := global_transform.basis.y.cross(Vector3.UP)
		apply_torque(upright_axis * vehicle_mass * 12.0)

	# 3. Nitro Boost, Boost Pad & Launch Control Thrust
	var want_nitro := nitro_input and nitro > 2.0 and forward_speed > 2.0 and current_gear >= 0
	if want_nitro:
		nitro_active = true
		nitro = maxf(0.0, nitro - 27.0 * delta)
		if grounded:
			apply_central_force(forward_dir * nitro_force)
	else:
		nitro_active = false
		# Slow passive regeneration so nitro never feels permanently empty
		nitro = minf(100.0, nitro + 2.8 * delta)

	if boost_pad_timer > 0.0:
		boost_pad_timer = maxf(0.0, boost_pad_timer - delta)
		if grounded:
			apply_central_force(forward_dir * (nitro_force * 1.15))

	if launch_boost_timer > 0.0:
		launch_boost_timer = maxf(0.0, launch_boost_timer - delta)
		if grounded:
			apply_central_force(forward_dir * (nitro_force * 0.85))

	# Cap extreme velocity cleanly so physics stays rock-solid
	var max_v := 86.0 if (nitro_active or boost_pad_timer > 0.0) else 75.0
	if linear_velocity.length() > max_v:
		linear_velocity = linear_velocity.normalized() * max_v

	# 4. Drift Detection, Scoring & Nitro Recharge
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
		var rate := (speed_kmh * 0.75 + drift_angle_deg * 8.0) * delta
		current_drift_score += rate
		nitro = minf(100.0, nitro + 21.0 * nitro_charge_mult * delta)
	else:
		is_drifting = false
		if current_drift_score > 0.0:
			drift_bank_timer -= delta
			if drift_bank_timer <= 0.0:
				total_drift_score += int(round(current_drift_score))
				current_drift_score = 0.0

	_update_visual_fx(delta)


func _update_visual_fx(delta: float) -> void:
	# Dynamic brake light glow
	if _brake_mat:
		var braking_now := brake_input > 0.15 or handbrake_input > 0.2
		_brake_mat.emission_energy_multiplier = 4.5 if braking_now else (1.3 if is_night_track else 0.75)

	# Flickering Nitro Exhaust Flames
	var flames_on := nitro_active or boost_pad_timer > 0.0 or launch_boost_timer > 0.0
	for fl in _nitro_flames:
		fl.visible = flames_on
		if flames_on:
			var jitter := randf_range(0.75, 1.35)
			fl.scale = Vector3(1.0, jitter, 1.0)

	# Rear Tire Drift Smoke
	var show_smoke := (not controls_locked) and (is_drifting or wheel_slip_intensity > 0.55) and get_wheel_contact_count() >= 2
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
	if controls_locked or _impact_cooldown > 0.0:
		return
	if body.is_in_group("Road") or body.is_in_group("Kerb") or body.is_in_group("Grass") or body.is_in_group("Dirt"):
		return
	var intensity := clampf(speed / 45.0, 0.15, 1.0)
	if intensity > 0.22:
		_impact_cooldown = 0.28
		if _spark_particles:
			_spark_particles.restart()
			_spark_particles.emitting = true
		# Cancel unbanked drift on heavy wall slam
		if intensity > 0.55:
			current_drift_score *= 0.25
		impact_occurred.emit(intensity)

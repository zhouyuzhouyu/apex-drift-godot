extends Node

## Records a real-time 24fps (--fixed-fps 24) Arcade Rail-Drift Showcase video + key screenshots
## using a 60Hz _physics_process closed-loop human-style pilot on:
##   1. Sakura Mountain Pass (KAZE DRIFT-S): Space Rail-Drift -> LV.1 Cyan -> LV.2 Gold -> LV.3 Violet -> Ultra Exit Boost!
##   2. Coastal Sunway (APEX GT-R): Brake-to-Drift (Tap S + A) Left Sweeping Rail-Drift -> Super Exit Boost!

const FRAME_DIR := "/tmp/apex_drift_video_frames"
const SHOT_DIR := "/tmp/apex_drift_shots"

var _frame_idx: int = 0
var _active_rm: RaceManager = null
var _pilot_mode: String = "" # "sakura_right" or "coastal_left"
var _pilot_elapsed: float = 0.0
var _drift_triggered: bool = false
var _exit_started: bool = false

var _max_ang: float = 0.0
var _min_drift_kmh: float = 999.0
var _peak_boost_kmh: float = 0.0
var _max_lat: float = 0.0
var _boost_seen: bool = false

var _saved_lv2: bool = false
var _saved_lv3: bool = false
var _saved_boost: bool = false
var _saved_coastal: bool = false


func _ready() -> void:
	call_deferred("_record")


func _physics_process(delta: float) -> void:
	if _active_rm == null or not is_instance_valid(_active_rm) or _pilot_mode == "":
		return
	var pc := _active_rm.player_car
	if pc == null or pc.controls_locked:
		return

	_pilot_elapsed += delta
	var prog := _active_rm.spline.get_progress(pc.global_position, pc.spline_index)
	var lat := float(prog["lateral"])
	_max_lat = maxf(_max_lat, absf(lat))

	var look_d := fposmod(float(prog["distance_along"]) + 20.0, _active_rm.spline.total_length)
	var look_xf := _active_rm.spline.get_transform_at_distance(look_d, 0.0, 0.0)
	var vel_dir := pc.linear_velocity.slide(Vector3.UP)
	vel_dir = vel_dir.normalized() if vel_dir.length() > 2.0 else (-pc.global_transform.basis.z)
	var to_target := (look_xf.origin - pc.global_position).slide(Vector3.UP).normalized()
	var vel_err := atan2(vel_dir.cross(to_target).y, clampf(vel_dir.dot(to_target), -1.0, 1.0))

	pc.throttle_input = 1.0
	pc.brake_input = 0.0
	pc.handbrake_input = 0.0
	pc.nitro_input = false

	if _pilot_mode == "sakura_right":
		if _pilot_elapsed < 0.35:
			var loc := pc.to_local(look_xf.origin)
			pc.steering_input = clampf(atan2(-loc.x, maxf(2.0, -loc.z)) * 2.0, -1.0, 1.0)
		elif not _drift_triggered:
			# Tap Space + Right steer (-1.0) -> instant right rail-drift!
			pc.steering_input = -1.0
			pc.handbrake_input = 1.0
			if pc.arcade_drift_active:
				_drift_triggered = true
		elif pc.arcade_drift_active and not _exit_started:
			# Smooth centerline modulation during right rail-drift (never crosses +0.55 exit threshold)
			var steer_cmd := clampf(vel_err * 4.5 + lat * 0.12, -1.0, 0.50)
			pc.steering_input = steer_cmd
			if _pilot_elapsed >= 2.60 and pc.drift_boost_tier >= 3:
				_exit_started = true
		elif _exit_started and pc.arcade_drift_active:
			# Crisp counter-steer flick (+0.90) -> laser-straighten + LV.3 Violet Ultra Boost!
			pc.steering_input = 0.90
		else:
			var loc := pc.to_local(look_xf.origin)
			pc.steering_input = clampf(atan2(-loc.x, maxf(2.0, -loc.z)) * 2.0, -1.0, 1.0)

	elif _pilot_mode == "coastal_left":
		if _pilot_elapsed < 0.30:
			var loc := pc.to_local(look_xf.origin)
			pc.steering_input = clampf(atan2(-loc.x, maxf(2.0, -loc.z)) * 2.0, -1.0, 1.0)
		elif not _drift_triggered:
			# Asphalt Brake-to-Drift Left (Tap S + A)!
			pc.steering_input = 1.0
			pc.brake_input = 0.85
			if pc.arcade_drift_active:
				_drift_triggered = true
		elif pc.arcade_drift_active and not _exit_started:
			# Smooth centerline modulation during left rail-drift (never crosses -0.55 exit threshold)
			var steer_cmd := clampf(vel_err * 4.5 + lat * 0.12, -0.50, 1.0)
			pc.steering_input = steer_cmd
			if _pilot_elapsed >= 2.25 and pc.drift_boost_tier >= 2:
				_exit_started = true
		elif _exit_started and pc.arcade_drift_active:
			# Crisp counter-steer flick (-0.90) -> Exit Mini-Turbo!
			pc.steering_input = -0.90
		else:
			var loc := pc.to_local(look_xf.origin)
			pc.steering_input = clampf(atan2(-loc.x, maxf(2.0, -loc.z)) * 2.0, -1.0, 1.0)

	if pc.arcade_drift_active:
		_max_ang = maxf(_max_ang, pc.drift_angle_deg)
		_min_drift_kmh = minf(_min_drift_kmh, pc.get_speed_kmh())
	if pc.drift_exit_boost_timer > 0.0:
		_boost_seen = true
		_peak_boost_kmh = maxf(_peak_boost_kmh, pc.get_speed_kmh())


func _reset_stats() -> void:
	_pilot_elapsed = 0.0
	_drift_triggered = false
	_exit_started = false
	_max_ang = 0.0
	_min_drift_kmh = 999.0
	_peak_boost_kmh = 0.0
	_max_lat = 0.0
	_boost_seen = false


func _record() -> void:
	GameState.enable_test_mode()
	DirAccess.make_dir_recursive_absolute(FRAME_DIR)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	print("=== RECORDING REAL-TIME 24FPS ARCADE RAIL-DRIFT SHOWCASE ===")

	# Segment 1: Sakura Mountain Pass — KAZE DRIFT-S Right Rail-Drift -> LV.3 Violet Ultra Boost (115 frames = 4.8s @ 24fps)
	GameState.settings["language"] = "zh"
	GameState.settings["camera_mode"] = 0
	GameState.mode = "free_roam"
	GameState.selected_track_idx = 1 # Sakura Mountain Pass
	GameState.selected_car_idx = 1   # KAZE DRIFT-S
	GameState.selected_livery_idx = 3 # Sakura Pearl
	var rm1: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm1)
	rm1.countdown_timer = 5.0
	await _step_frames(3)
	rm1.player_controller.set_physics_process(false)

	var pc1 := rm1.player_car
	pc1.enable_arcade_drift = true
	var xf1 := rm1.spline.get_transform_at_distance(205.0, -1.5, 0.08)
	pc1.reset_to_transform(xf1)
	pc1.controls_locked = false
	pc1.linear_velocity = -xf1.basis.z * 49.0 # 176.4 km/h
	pc1.current_gear = 4
	rm1.go_lights_timer = 0.0
	rm1._update_start_lights(0, false, false)
	rm1.hud._banner_timer = 0.0
	rm1.hud._banner_label.visible = false
	rm1.chase_camera._snap_immediate()

	_reset_stats()
	_active_rm = rm1
	_pilot_mode = "sakura_right"

	for f in range(79):
		await _save_video_frame()
		if not _saved_lv2 and pc1.arcade_drift_active and pc1.drift_boost_tier == 2 and pc1.drift_charge_progress >= 2.35:
			_saved_lv2 = true
			await _save_shot("drift_sakura_lv2_gold.png")
		if not _saved_lv3 and pc1.arcade_drift_active and pc1.drift_boost_tier >= 3 and _pilot_elapsed >= 2.35:
			_saved_lv3 = true
			await _save_shot("drift_sakura_lv3_violet.png")
		if not _saved_boost and pc1.drift_exit_boost_timer > 0.0 and not pc1.arcade_drift_active and pc1.drift_exit_boost_timer < 1.38:
			_saved_boost = true
			await _save_shot("drift_sakura_exit_boost.png")

	print("Sakura Rail-Drift Stats: max_ang=%.1fdeg min_drift_kmh=%.1f boost_seen=%s peak_boost_kmh=%.1f max_lat=%.1fm score=%.0f" % [
		_max_ang, _min_drift_kmh, str(_boost_seen), _peak_boost_kmh, _max_lat, pc1.current_drift_score + float(pc1.total_drift_score)
	])
	_pilot_mode = ""
	_active_rm = null
	rm1.queue_free()
	await _step_frames(3)

	# Segment 2: Coastal Sunway — APEX GT-R Brake-to-Drift Left Rail-Drift -> Exit Boost (96 frames = 4.0s @ 24fps)
	GameState.selected_track_idx = 0 # Coastal Sunway
	GameState.selected_car_idx = 0   # APEX GT-R
	GameState.selected_livery_idx = 0 # Racing Red
	var rm2: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm2)
	rm2.countdown_timer = 5.0
	await _step_frames(3)
	rm2.player_controller.set_physics_process(false)

	var pc2 := rm2.player_car
	pc2.enable_arcade_drift = true
	var xf2 := rm2.spline.get_transform_at_distance(190.0, 1.5, 0.08)
	pc2.reset_to_transform(xf2)
	pc2.controls_locked = false
	pc2.linear_velocity = -xf2.basis.z * 50.0 # 180.0 km/h
	pc2.current_gear = 4
	rm2.go_lights_timer = 0.0
	rm2._update_start_lights(0, false, false)
	rm2.hud._banner_timer = 0.0
	rm2.hud._banner_label.visible = false
	rm2.chase_camera._snap_immediate()

	_reset_stats()
	_active_rm = rm2
	_pilot_mode = "coastal_left"

	for f in range(96):
		await _save_video_frame()
		if not _saved_coastal and pc2.arcade_drift_active and pc2.drift_boost_tier >= 2 and pc2.drift_charge_progress >= 2.20:
			_saved_coastal = true
			await _save_shot("drift_coastal_left_b2d.png")

	print("Coastal Brake-to-Drift Stats: max_ang=%.1fdeg min_drift_kmh=%.1f boost_seen=%s peak_boost_kmh=%.1f max_lat=%.1fm score=%.0f" % [
		_max_ang, _min_drift_kmh, str(_boost_seen), _peak_boost_kmh, _max_lat, pc2.current_drift_score + float(pc2.total_drift_score)
	])
	_pilot_mode = ""
	_active_rm = null
	rm2.queue_free()
	await _step_frames(3)
	print("=== RECORDED %d REAL-TIME 24FPS DRIFT FRAMES ===" % _frame_idx)
	get_tree().quit(0)


func _save_video_frame() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/frame_%04d.png" % [FRAME_DIR, _frame_idx])
		_frame_idx += 1


func _save_shot(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := SHOT_DIR + "/" + fname
		img.save_png(path)
		print("Drift shot saved: " + path)


func _step_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

class_name RaceManager
extends Node3D

## Complete Race Director orchestrating track construction, 6-car grid spawning,
## F1 5-light countdown, checkpoints, anti-cheat laps, Ghost recording/replay,
## live standings, wrong-way detection, pause menu, and results podium.

const RACE_CAR_SCENE := preload("res://scenes/vehicle/race_car.tscn")

var track_data: Dictionary = {}
var spline: TrackSpline
var start_light_mats: Array[StandardMaterial3D] = []
var is_night: bool = false

var cars: Array[RaceCar] = []
var player_car: RaceCar
var ghost_car: GhostCar
var player_controller: PlayerController
var chase_camera: ChaseCamera
var hud: RaceHUD
var pause_menu: PauseMenu
var results_screen: ResultsScreen

var race_state: String = "countdown" # countdown, racing, finished
var countdown_timer: float = 0.0
var countdown_step: int = -1
var go_lights_timer: float = 0.0
var race_elapsed: float = 0.0
var total_laps: int = 3
var mode: String = "quick_race"

var _car_has_crossed_start: Dictionary = {} # RaceCar -> bool
var _car_prev_progress: Dictionary = {}     # RaceCar -> float
var _ghost_lap_frames: Array = []
var _ghost_sample_accum: float = 0.0
var _new_record_this_race: bool = false
var _best_medal_this_race: String = "none"
var _finish_delay_timer: float = -1.0


func _ready() -> void:
	get_tree().paused = false
	mode = GameState.mode
	track_data = TrackCatalog.get_track(GameState.selected_track_idx)
	total_laps = 3 if mode == "grand_prix" else (1 if mode == "time_trial" else GameState.lap_count)
	if mode == "time_trial":
		total_laps = 3 # 3 hotlaps per Time Trial session (or endless hotlap? 3 crisp laps with live ghost!)

	# 1. Build 3D Track World
	var built := TrackBuilder.build_track(self, track_data)
	spline = built["spline"]
	start_light_mats = built["start_lights"]
	is_night = bool(built["is_night"])

	# Connect Boost Pad triggers
	for area in built["boost_areas"]:
		var a: Area3D = area
		a.body_entered.connect(_on_boost_pad_entered)

	# 2. Spawn Vehicles
	_spawn_grid()

	# 3. Camera Rig
	chase_camera = ChaseCamera.new()
	chase_camera.name = "ChaseCamera"
	add_child(chase_camera)
	chase_camera.setup(player_car, int(GameState.settings.get("camera_mode", 0)))
	chase_camera.current = true

	# 4. Player Controller
	player_controller = PlayerController.new()
	player_controller.name = "PlayerController"
	add_child(player_controller)
	player_controller.setup(player_car)
	player_controller.respawn_requested.connect(_on_player_respawn)
	player_controller.camera_switch_requested.connect(_on_camera_switch)

	# 5. HUD, Pause Menu & Results Screen
	hud = RaceHUD.new()
	hud.name = "RaceHUD"
	add_child(hud)
	hud.setup(player_car, cars, spline, track_data, total_laps, mode)

	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.resume_requested.connect(_toggle_pause)
	pause_menu.restart_requested.connect(_restart_race)
	pause_menu.camera_switch_requested.connect(_on_camera_switch)
	pause_menu.quit_requested.connect(_quit_to_menu)

	results_screen = ResultsScreen.new()
	results_screen.name = "ResultsScreen"
	add_child(results_screen)
	results_screen.next_round_requested.connect(_next_grand_prix_round)
	results_screen.rematch_requested.connect(_restart_race)
	results_screen.main_menu_requested.connect(_quit_to_menu)

	# 6. Start Driving Audio & Countdown
	AudioManager.start_driving_audio()
	if mode == "free_roam":
		countdown_timer = 2.0 # Short quick launch
		countdown_step = 3
	else:
		countdown_timer = 0.0
		countdown_step = 0
	_update_start_lights(0, false, true)


func _exit_tree() -> void:
	AudioManager.stop_driving_audio()


func _spawn_grid() -> void:
	var has_ai := (mode == "quick_race" or mode == "grand_prix")
	var player_slot := 3 if has_ai else 0

	# Spawn Player Car
	player_car = _instantiate_car(
		GameState.selected_car_idx,
		GameState.selected_livery_idx,
		"PLAYER",
		true,
		player_slot
	)
	cars.append(player_car)

	# Spawn 5 Competitive AI Rivals in Quick Race / Grand Prix
	if has_ai:
		var rivals := CarCatalog.get_ai_rivals()
		var ai_slots := [0, 1, 2, 4, 5]
		for i in range(mini(rivals.size(), ai_slots.size())):
			var rv: Dictionary = rivals[i]
			var liv := int(rv["livery_idx"])
			if liv == GameState.selected_livery_idx:
				liv = (liv + 1) % CarCatalog.get_liveries().size()
			var ai_car := _instantiate_car(
				int(rv["car_idx"]),
				liv,
				str(rv["name"]),
				false,
				ai_slots[i]
			)
			cars.append(ai_car)

		# Attach AIDriver to each rival once all_cars list is complete
		var r_idx := 0
		for c in cars:
			if c.is_player:
				continue
			var drv := AIDriver.new()
			drv.name = "AI_" + c.driver_name
			c.add_child(drv)
			drv.setup(c, spline, cars, player_car, rivals[r_idx], GameState.difficulty)
			r_idx += 1

	# Spawn Time Trial Ghost Car if saved best lap exists
	if mode == "time_trial":
		var rec := GameState.get_track_record(str(track_data["id"]))
		var ghost_frames: Array = rec.get("ghost", [])
		if ghost_frames.size() >= 2:
			ghost_car = GhostCar.new()
			ghost_car.name = "GhostCar"
			add_child(ghost_car)
			ghost_car.setup(GameState.selected_car_idx, ghost_frames)


func _instantiate_car(car_idx: int, livery_idx: int, drv_name: String, is_p: bool, grid_slot: int) -> RaceCar:
	var car: RaceCar = RACE_CAR_SCENE.instantiate()
	car.name = "Car_" + drv_name
	add_child(car)
	car.configure(car_idx, livery_idx, drv_name, is_p, is_night)
	var xf := spline.get_grid_transform(grid_slot)
	car.reset_to_transform(xf)
	car.controls_locked = true
	var prog := spline.get_progress(car.global_position)
	car.spline_index = int(prog["index"])
	car.spline_progress = float(prog["progress"])
	car.total_race_progress = car.spline_progress - 1.0 # Behind start line initially
	_car_has_crossed_start[car] = false
	_car_prev_progress[car] = car.spline_progress
	return car


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and race_state != "finished":
		_toggle_pause()


func _toggle_pause() -> void:
	var new_paused := not get_tree().paused
	get_tree().paused = new_paused
	pause_menu.visible = new_paused


func _physics_process(delta: float) -> void:
	if race_state == "countdown":
		_process_countdown(delta)
	elif race_state == "racing":
		race_elapsed += delta
		if go_lights_timer > 0.0:
			go_lights_timer -= delta
			if go_lights_timer <= 0.0:
				_update_start_lights(0, false, false)
		_update_race_progress(delta)
		_record_ghost_frame(delta)
	elif race_state == "finished":
		race_elapsed += delta
		_update_race_progress(delta)
		if _finish_delay_timer > 0.0:
			_finish_delay_timer -= delta
			if _finish_delay_timer <= 0.0:
				_show_final_results()

	hud.update_hud(delta, race_elapsed)


func _process_countdown(delta: float) -> void:
	countdown_timer += delta
	var step_interval := 0.55
	var desired_step := int(countdown_timer / step_interval)

	if desired_step > countdown_step and desired_step <= 5:
		countdown_step = desired_step
		_update_start_lights(countdown_step, false, true)
		AudioManager.play_sfx("countdown_beep", 1.0, 0.85)
	elif countdown_timer >= step_interval * 5.8:
		# LIGHTS OUT AND AWAY WE GO!
		race_state = "racing"
		go_lights_timer = 1.6
		_update_start_lights(5, true, true)
		AudioManager.play_sfx("countdown_go", 1.0, 1.0)
		var perfect_launch := player_car.trigger_launch_control()
		for c in cars:
			c.controls_locked = false
		if perfect_launch:
			hud.show_banner(GameState.t("hud_perfect_start"), UITheme.ACCENT_GOLD, 1.8)
		else:
			hud.show_banner(GameState.t("hud_go"), Color(0.15, 1.0, 0.45), 1.4)
		if ghost_car != null:
			ghost_car.start_lap()
		_ghost_lap_frames.clear()


func _update_start_lights(lit_count: int, is_green: bool, show_hud: bool) -> void:
	hud.set_countdown_lights(lit_count, is_green, show_hud)
	for i in range(start_light_mats.size()):
		var mat := start_light_mats[i]
		if is_green:
			mat.albedo_color = Color(0.15, 0.96, 0.36)
			mat.emission = Color(0.12, 1.0, 0.35)
			mat.emission_energy_multiplier = 4.0
		elif i < lit_count:
			mat.albedo_color = Color(1.0, 0.14, 0.14)
			mat.emission = Color(1.0, 0.12, 0.12)
			mat.emission_energy_multiplier = 3.8
		else:
			mat.albedo_color = Color(0.18, 0.05, 0.05)
			mat.emission = Color(0.05, 0.01, 0.01)
			mat.emission_energy_multiplier = 0.2


func _update_race_progress(delta: float) -> void:
	for car in cars:
		if not is_instance_valid(car):
			continue
		if not car.finished:
			car.current_lap_time += delta

		var prog := spline.get_progress(car.global_position, car.spline_index)
		var p_val := float(prog["progress"])
		var prev_p := float(_car_prev_progress.get(car, p_val))
		car.spline_index = int(prog["index"])
		car.spline_progress = p_val

		# Detect initial crossing of Start/Finish line after leaving grid behind line
		if not bool(_car_has_crossed_start.get(car, false)):
			if prev_p > 0.75 and p_val < 0.25:
				_car_has_crossed_start[car] = true
				car.next_checkpoint = 0
				car.total_race_progress = p_val
			else:
				car.total_race_progress = p_val - 1.0 if p_val > 0.5 else p_val
		else:
			# Sequential checkpoints 0..6 at 0.125 .. 0.875
			if car.next_checkpoint < 7:
				var cp_frac := float(car.next_checkpoint + 1) * 0.125
				if p_val >= cp_frac and p_val < cp_frac + 0.22:
					car.next_checkpoint += 1

			# Lap wrap check: crossed start/finish forward after clearing >= 6 checkpoints
			if prev_p > 0.80 and p_val < 0.20 and car.next_checkpoint >= 6:
				_on_car_lap_completed(car)

			car.total_race_progress = float(car.current_lap - 1) + p_val

		_car_prev_progress[car] = p_val

		# Wrong-way indicator for player
		if car == player_car:
			var fwd := -car.global_transform.basis.z
			var track_fwd: Vector3 = prog["forward"]
			var dot_dir := fwd.dot(track_fwd)
			hud.set_wrong_way(dot_dir < -0.35 and car.speed > 3.5 and not car.finished)

	# Rank all vehicles by finish order, then descending total_race_progress
	var sorted := cars.duplicate()
	sorted.sort_custom(func(a: RaceCar, b: RaceCar) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.total_race_progress > b.total_race_progress
	)
	for idx in range(sorted.size()):
		sorted[idx].race_rank = idx + 1


func _on_car_lap_completed(car: RaceCar) -> void:
	if car.finished:
		return
	var lap_t := car.current_lap_time
	if lap_t > 2.0 and (car.best_lap_time <= 0.0 or lap_t < car.best_lap_time):
		car.best_lap_time = lap_t

	if car.is_player:
		var rec_res := GameState.save_lap_record(str(track_data["id"]), lap_t, _ghost_lap_frames.duplicate(true))
		if bool(rec_res["is_new_best"]):
			_new_record_this_race = true
			hud.show_banner(GameState.t("hud_new_best") + "  " + GameState.format_time(lap_t), UITheme.ACCENT_CYAN, 2.2)
		var earned_m := str(rec_res["medal"])
		if _medal_rank(earned_m) > _medal_rank(_best_medal_this_race):
			_best_medal_this_race = earned_m
		_ghost_lap_frames.clear()
		if ghost_car != null:
			# Refresh ghost if we just beat our record!
			if bool(rec_res["is_new_best"]):
				var fresh_rec := GameState.get_track_record(str(track_data["id"]))
				ghost_car.frames = fresh_rec.get("ghost", [])
			ghost_car.start_lap()

	car.current_lap_time = 0.0
	car.next_checkpoint = 0

	if mode != "free_roam" and car.current_lap >= total_laps:
		car.finished = true
		car.finish_time = race_elapsed
		if car.is_player:
			_on_player_finished()
	else:
		car.current_lap += 1
		if car.is_player:
			if mode != "free_roam" and car.current_lap == total_laps:
				AudioManager.play_sfx("final_lap", 1.0, 1.0)
				hud.show_banner(GameState.t("hud_final_lap"), UITheme.ACCENT_RED, 2.3)
			else:
				AudioManager.play_sfx("lap_chime", 1.0, 0.85)
				if mode != "free_roam":
					hud.show_banner(GameState.t("hud_lap_banner") % [car.current_lap, total_laps], Color.WHITE, 1.6)


func _on_player_finished() -> void:
	if race_state == "finished":
		return
	race_state = "finished"
	player_car.total_drift_score += int(round(player_car.current_drift_score))
	player_car.current_drift_score = 0.0
	player_controller.active = false
	chase_camera.finish_orbit = true
	AudioManager.play_sfx("race_finish", 1.0, 1.0)
	hud.show_banner("#%d  %s" % [player_car.race_rank, GameState.t("res_race_complete")], UITheme.ACCENT_GOLD, 2.5)
	_finish_delay_timer = 1.6


func _show_final_results() -> void:
	# Estimate finish times for AI cars still on track
	var sorted := cars.duplicate()
	sorted.sort_custom(func(a: RaceCar, b: RaceCar) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return a.total_race_progress > b.total_race_progress
	)

	var result_rows: Array[Dictionary] = []
	var prev_time: float = 0.0
	for idx in range(sorted.size()):
		var car: RaceCar = sorted[idx]
		var est_time: float = car.finish_time
		if not car.finished:
			var rem_laps := maxf(0.02, float(total_laps) - car.total_race_progress)
			var rem_dist := rem_laps * spline.total_length
			est_time = race_elapsed + rem_dist / 36.0
		if idx > 0 and est_time <= prev_time + 0.05:
			est_time = prev_time + randf_range(0.18, 0.55)
		prev_time = est_time
		result_rows.append({
			"driver_name": car.driver_name,
			"is_player": car.is_player,
			"car_idx": car.car_idx,
			"finish_time": est_time,
			"best_lap": car.best_lap_time,
			"round_points": 0,
			"total_points": 0
		})

	GameState.record_race_finished(player_car.race_rank, player_car.total_drift_score)

	var is_gp := (mode == "grand_prix")
	var has_next_gp := false
	if is_gp:
		GameState.record_grand_prix_results(result_rows)
		has_next_gp = GameState.gp_round < TrackCatalog.get_tracks().size() - 1

	results_screen.show_results({
		"results": result_rows,
		"track": track_data,
		"is_gp": is_gp,
		"gp_round": GameState.gp_round,
		"has_next_gp": has_next_gp,
		"is_new_record": _new_record_this_race,
		"medal": _best_medal_this_race,
		"drift_score": player_car.total_drift_score
	})


func _record_ghost_frame(delta: float) -> void:
	if player_car == null or player_car.finished:
		return
	_ghost_sample_accum += delta
	if _ghost_sample_accum < 0.10:
		return
	_ghost_sample_accum = 0.0
	if _ghost_lap_frames.size() >= 1800: # cap at 3 minutes per lap
		return
	var p := player_car.global_position
	var r := player_car.rotation
	_ghost_lap_frames.append([
		snappedf(player_car.current_lap_time, 0.01),
		snappedf(p.x, 0.02), snappedf(p.y, 0.02), snappedf(p.z, 0.02),
		snappedf(r.x, 0.005), snappedf(r.y, 0.005), snappedf(r.z, 0.005)
	])


func _on_boost_pad_entered(body: Node) -> void:
	if body is RaceCar:
		(body as RaceCar).trigger_boost_pad()


func _on_player_respawn() -> void:
	if player_car == null or race_state != "racing":
		return
	var dist := spline.cum_lengths[player_car.spline_index]
	var xf := spline.get_transform_at_distance(dist, 0.0, 0.14)
	player_car.reset_to_transform(xf)
	AudioManager.play_sfx("ui_click")


func _on_camera_switch() -> void:
	if chase_camera == null:
		return
	var new_mode := chase_camera.cycle_mode()
	hud.set_camera_name(new_mode)
	AudioManager.play_sfx("ui_click")


func _next_grand_prix_round() -> void:
	get_tree().paused = false
	if GameState.advance_grand_prix_round():
		get_tree().change_scene_to_file("res://scenes/race_scene.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _restart_race() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/race_scene.tscn")


func _quit_to_menu() -> void:
	get_tree().paused = false
	GameState.gp_active = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _medal_rank(m: String) -> int:
	match m:
		"gold": return 3
		"silver": return 2
		"bronze": return 1
		_: return 0

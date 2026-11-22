extends Node

## Automated Verification & Visual Screenshot Suite for Apex Drift.
## Run headless:
##   godot --headless --path . --script res://tests/verify_game.gd
## Or with real OpenGL3 rendering under Xvfb to capture PNG screenshots:
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://tests/verify_runner.tscn

const SCREENSHOT_DIR := "/tmp/apex_drift_shots"


func _ready() -> void:
	# Defer so autoloads and viewport are fully initialized
	call_deferred("_run_all")


func _run_all() -> void:
	var capture_visuals := DisplayServer.get_name() != "headless"
	print("=== APEX DRIFT VERIFICATION START (display=%s) ===" % DisplayServer.get_name())
	if capture_visuals:
		DirAccess.make_dir_recursive_absolute(SCREENSHOT_DIR)

	var failures: Array[String] = []

	# 1. Validate all 3 Track Splines mathematically
	var tracks := TrackCatalog.get_tracks()
	for i in range(tracks.size()):
		var tr: Dictionary = tracks[i]
		var sp := TrackSpline.new()
		sp.build_from_control_points(tr["control_points"], float(tr["road_width"]), float(tr["bank_strength"]), 3.0)
		var v := sp.validate_geometry()
		print("Track[%d] %s: len=%.1fm samples=%d max_grade=%.3f min_sep=%.1fm valid=%s" % [
			i, tr["id"], v["total_length"], v["sample_count"], v["max_grade"], v["min_non_adjacent_sep"], str(v["is_valid"])
		])
		if not bool(v["is_valid"]):
			failures.append("Track geometry invalid: %s" % tr["id"])

	# 2. Test Main Menu scene + Live 3D Showroom
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 0
	GameState.selected_car_idx = 0
	GameState.selected_livery_idx = 0
	var menu_scene: PackedScene = load("res://scenes/main_menu.tscn")
	var menu := menu_scene.instantiate()
	get_tree().root.add_child(menu)
	await _wait_frames(15)
	if capture_visuals:
		await _save_shot("01_main_menu_zh.png")
		# Also switch car to Formula + Cyber Cyan livery on Neon Midnight!
		GameState.selected_track_idx = 2
		GameState.selected_car_idx = 2
		GameState.selected_livery_idx = 1
		menu._rebuild_showroom_car()
		menu._refresh_all()
		await _wait_frames(8)
		await _save_shot("02_main_menu_formula.png")
		# Reset defaults cleanly
		GameState.selected_track_idx = 0
		GameState.selected_car_idx = 0
		GameState.selected_livery_idx = 0
	menu.queue_free()
	await _wait_frames(3)

	# 3. Simulate real GEVP physics & AI racing on ALL 3 circuits!
	for track_idx in range(tracks.size()):
		GameState.mode = "quick_race"
		GameState.selected_track_idx = track_idx
		GameState.selected_car_idx = track_idx % CarCatalog.get_cars().size()
		GameState.selected_livery_idx = track_idx
		GameState.difficulty = 1
		GameState.lap_count = 3

		var race_scene: PackedScene = load("res://scenes/race_scene.tscn")
		var rm: RaceManager = race_scene.instantiate()
		get_tree().root.add_child(rm)
		await _wait_physics(15)

		# Verify all 6 cars spawned & grounded on GEVP raycast wheels
		if rm.cars.size() != 6:
			failures.append("Track %d expected 6 cars, got %d" % [track_idx, rm.cars.size()])
		for c in rm.cars:
			var contacts := c.get_wheel_contact_count()
			if contacts < 4:
				failures.append("Track %d car %s only %d/4 wheels grounded at start" % [track_idx, c.driver_name, contacts])

		# Fast-forward countdown right to racing start!
		rm.countdown_timer = 3.15
		await _wait_physics(6)
		if rm.race_state != "racing":
			failures.append("Track %d did not transition to racing state" % track_idx)

		# Attach temporary autopilot to player car so we drive cleanly through turns & test Nitro!
		rm.player_controller.active = false
		rm.player_controller.set_physics_process(false)
		var test_ai := AIDriver.new()
		rm.player_car.add_child(test_ai)
		test_ai.setup(rm.player_car, rm.spline, rm.cars, null, {"skill_offset": 0.08, "preferred_lane": 0.0}, 2)

		var start_prog := rm.player_car.total_race_progress
		var max_player_kmh := 0.0
		var steps := 300 if track_idx == 0 else 240 # ~5.0s / ~4.0s simulated physics
		for s in range(steps):
			await get_tree().physics_frame
			if s >= 95 and s <= 165:
				rm.player_car.nitro_input = true # fire nitro for visual & thrust test!
			max_player_kmh = maxf(max_player_kmh, rm.player_car.get_speed_kmh())
			if capture_visuals and s == 145:
				await _save_shot("03_race_track%d_%s.png" % [track_idx, tracks[track_idx]["id"]])

		# Verify healthy physics & forward track progress
		var moved_dist := (rm.player_car.total_race_progress - start_prog) * rm.spline.total_length
		var ai_avg_kmh := 0.0
		for c in rm.cars:
			if not c.global_position.is_finite():
				failures.append("NaN/Inf position on %s track %d" % [c.driver_name, track_idx])
			if not c.is_player:
				ai_avg_kmh += c.get_speed_kmh()
		ai_avg_kmh /= 5.0

		print("Track[%d] Sim Result: player_max=%.1f km/h moved=%.1fm ai_avg=%.1f km/h rank=%d/6 cp=%d" % [
			track_idx, max_player_kmh, moved_dist, ai_avg_kmh, rm.player_car.race_rank, rm.player_car.next_checkpoint
		])
		if max_player_kmh < 120.0:
			failures.append("Track %d player car too slow: %.1f km/h" % [track_idx, max_player_kmh])
		if ai_avg_kmh < 80.0:
			failures.append("Track %d AI cars too slow: %.1f km/h" % [track_idx, ai_avg_kmh])
		if moved_dist < 60.0:
			failures.append("Track %d player barely advanced: %.1fm" % [track_idx, moved_dist])

		# On Track 0 also verify Results Screen rendering & Grand Prix recording!
		if track_idx == 0:
			rm.player_car.best_lap_time = 35.42
			rm.player_car.total_drift_score = 1850
			rm._new_record_this_race = true
			rm._best_medal_this_race = "gold"
			rm._show_final_results()
			await _wait_frames(8)
			if capture_visuals:
				await _save_shot("04_results_screen.png")

		rm.queue_free()
		await _wait_frames(4)

	# 4. Verify Save/Load, Ghost persistence & Time Trial Ghost playback
	GameState.records.erase("coastal_sunway")
	var sample_ghost: Array = []
	for k in range(15):
		sample_ghost.append([float(k) * 0.1, 0.0, 0.1, 80.0 - float(k) * 4.5, 0.0, 0.0, 0.0])
	var save_res := GameState.save_lap_record("coastal_sunway", 38.5, sample_ghost)
	print("Save record test: ", save_res)
	GameState.load_save()
	var loaded_best := float(GameState.get_track_record("coastal_sunway").get("best_lap", 0.0))
	if loaded_best <= 0.0:
		failures.append("Persistent save/load failed for best_lap")

	# Verify Time Trial mode instantiates GhostCar cleanly
	GameState.mode = "time_trial"
	GameState.selected_track_idx = 0
	var tt_scene: PackedScene = load("res://scenes/race_scene.tscn")
	var tt_rm: RaceManager = tt_scene.instantiate()
	get_tree().root.add_child(tt_rm)
	await _wait_physics(10)
	if tt_rm.ghost_car == null:
		failures.append("Time Trial did not spawn GhostCar with saved record")
	else:
		tt_rm.ghost_car.start_lap()
		await _wait_frames(5)
		print("Time Trial GhostCar verified at pos=", tt_rm.ghost_car.global_position)
	tt_rm.queue_free()
	await _wait_frames(4)

	# Restore clean default quick_race state in save
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 0
	GameState.selected_car_idx = 0
	GameState.selected_livery_idx = 0
	GameState.save_data()

	if failures.is_empty():
		print("=== ALL VERIFICATION CHECKS PASSED! ===")
		get_tree().quit(0)
	else:
		print("=== VERIFICATION FAILED (%d issues) ===" % failures.size())
		for f in failures:
			push_error("FAIL: " + f)
		get_tree().quit(1)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _wait_physics(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func _save_shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var path := SCREENSHOT_DIR + "/" + filename
		img.save_png(path)
		print("Saved screenshot: " + path)

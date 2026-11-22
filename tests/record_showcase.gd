extends Node

## Records a complete 24fps 16:9 gameplay showcase video (~11s, 264 frames) covering:
## 1. Main Menu 3D Showroom cycling all 4 cars & liveries
## 2. Coastal Sunway — F1 Countdown Lights -> Green Light GO! -> 6-car launch + Nitro
## 3. Sakura Mountain Pass — Sunset mountain curves, active Drift + Hood Cam
## 4. Neon Midnight Circuit — Nighttime cyber street race under glowing neon arches
## 5. Grand Prix Championship Podium Victory Screen

const FRAME_DIR := "/tmp/apex_video_frames"

var _frame_idx: int = 0


func _ready() -> void:
	call_deferred("_record")


func _record() -> void:
	GameState.enable_test_mode()
	DirAccess.make_dir_recursive_absolute(FRAME_DIR)
	Engine.max_physics_steps_per_frame = 8
	print("=== RECORDING COMPLETE 5-SEGMENT SHOWCASE ===")

	# Segment 1: Main Menu 3D Showroom cycling all 4 cars (48 frames = 2.0s @ 24fps)
	GameState.settings["language"] = "zh"
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 0
	GameState.selected_car_idx = 0
	GameState.selected_livery_idx = 0
	var menu: MainMenu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	await _step_frames(3)
	for f in range(48):
		if f == 14:
			GameState.selected_car_idx = 1; GameState.selected_livery_idx = 3; GameState.selected_track_idx = 1
			menu._rebuild_showroom_car(); menu._refresh_all()
		elif f == 28:
			GameState.selected_car_idx = 2; GameState.selected_livery_idx = 1; GameState.selected_track_idx = 2
			menu._rebuild_showroom_car(); menu._refresh_all()
		elif f == 40:
			GameState.selected_car_idx = 3; GameState.selected_livery_idx = 2; GameState.selected_track_idx = 0
			menu._rebuild_showroom_car(); menu._refresh_all()
		menu._turntable.rotate_y(0.065)
		await _capture_frame(2)
	menu.queue_free()
	await _step_frames(2)

	# Segment 2: Coastal Sunway — F1 Countdown 4->5->GO! + 6-Car Launch & Nitro (66 frames = 2.75s)
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 0
	GameState.selected_car_idx = 0
	GameState.selected_livery_idx = 0
	GameState.difficulty = 2
	GameState.lap_count = 3
	var rm0: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm0)
	rm0.countdown_timer = 2.45 # Lights 4 -> 5 -> GO! right at ~0.7s
	rm0.player_controller.set_physics_process(false)
	var ai0 := AIDriver.new()
	rm0.player_car.add_child(ai0)
	ai0.setup(rm0.player_car, rm0.spline, rm0.cars, null, {"skill_offset": 0.08, "preferred_lane": 0.0}, 2, rm0.boost_distances)
	for f in range(66):
		if f >= 34 and f <= 62:
			rm0.player_car.nitro_input = true
		await _capture_frame(2)
	rm0.queue_free()
	await _step_frames(2)

	# Segment 3: Sakura Mountain Pass — Mountain Curves + Drift + Hood Cam (58 frames = 2.42s)
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 1
	GameState.selected_car_idx = 1 # KAZE DRIFT-S
	GameState.selected_livery_idx = 3 # Sakura Pearl
	var rm1: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm1)
	rm1.countdown_timer = 5.0
	rm1.player_controller.set_physics_process(false)
	var ai1 := AIDriver.new()
	rm1.player_car.add_child(ai1)
	ai1.setup(rm1.player_car, rm1.spline, rm1.cars, null, {"skill_offset": 0.10, "preferred_lane": 0.0}, 2, rm1.boost_distances)
	await _fast_skip_physics(210)
	for f in range(58):
		if f == 34:
			rm1._on_camera_switch() # Far
			rm1._on_camera_switch() # Hood Cam!
		if f >= 12 and f <= 30:
			rm1.player_car.nitro_input = true
		await _capture_frame(2)
	rm1.queue_free()
	await _step_frames(2)

	# Segment 4 + 5: Neon Midnight Circuit + GP Championship Podium (60 + 32 = 92 frames = 3.83s)
	GameState.start_grand_prix()
	GameState.gp_round = 2
	GameState.gp_standings = {"PLAYER": 18, "ELENA": 18, "KENJI": 14, "MARCO": 10, "SORA": 6, "VIKTOR": 4}
	GameState.selected_track_idx = 2
	GameState.selected_car_idx = 2 # VORTEX F-ZERO
	GameState.selected_livery_idx = 1 # Cyber Cyan
	var rm2: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm2)
	rm2.countdown_timer = 5.0
	rm2.player_controller.set_physics_process(false)
	var ai2 := AIDriver.new()
	rm2.player_car.add_child(ai2)
	ai2.setup(rm2.player_car, rm2.spline, rm2.cars, null, {"skill_offset": 0.12, "preferred_lane": 0.0}, 2, rm2.boost_distances)
	await _fast_skip_physics(200)
	for f in range(60):
		if f >= 12 and f <= 48:
			rm2.player_car.nitro_input = true
		await _capture_frame(2)

	# Grand Prix Final Podium Victory Screen!
	rm2.player_car.best_lap_time = 40.82
	rm2.player_car.total_drift_score = 2480
	rm2._new_record_this_race = true
	rm2._best_medal_this_race = "gold"
	rm2.player_car.finished = true
	rm2.player_car.finish_time = 123.45
	rm2.chase_camera.finish_orbit = true
	rm2._show_final_results()
	for _f in range(32):
		await _capture_frame(2)

	rm2.queue_free()
	await _step_frames(2)
	print("=== RECORDED %d FRAMES SUCCESSFULLY ===" % _frame_idx)
	get_tree().quit(0)


func _fast_skip_physics(steps: int) -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	for _i in range(steps):
		await get_tree().physics_frame
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0


func _capture_frame(phys_steps: int) -> void:
	for _i in range(phys_steps):
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/frame_%04d.png" % [FRAME_DIR, _frame_idx])
		_frame_idx += 1


func _step_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

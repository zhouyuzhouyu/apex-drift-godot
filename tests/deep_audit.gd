extends Node

## Deep Full-Lap & Feature Audit Suite for Apex Drift.
## Tests:
## 1. All 4 cars straight-line acceleration (0-100, top speed) and drift/nitro charging
## 2. FULL 2-LAP headless simulation on ALL 3 tracks (verifying all checkpoints, lap1 & flying lap2,
##    real lap times vs medal targets, AI performance, boost pad hits >= 1, flipped == 0)
## 3. Reverse-behind-start-line anti-exploit check, Wrong-way & Respawn, Pause/Unpause via pause_game,
##    Mid-race HUD language switch, Grand Prix 3-round podium sorting, Time Trial Ghost Car sync
## 4. Expanded visual screenshot capture (when run under Xvfb OpenGL3)

const AUDIT_SHOT_DIR := "/tmp/apex_audit_shots"


func _ready() -> void:
	call_deferred("_run_audit")


func _run_audit() -> void:
	GameState.enable_test_mode()
	var visual := DisplayServer.get_name() != "headless"
	print("=== DEEP AUDIT START (display=%s) ===" % DisplayServer.get_name())
	var failures: Array[String] = []
	if visual:
		DirAccess.make_dir_recursive_absolute(AUDIT_SHOT_DIR)
		await _run_visual_audit()
	else:
		failures = await _run_headless_full_lap_audit()

	await _wait_frames(3)
	if failures.is_empty():
		print("=== DEEP AUDIT END (0 FAILURES) ===")
		get_tree().quit(0)
	else:
		print("=== DEEP AUDIT FAILED (%d issues) ===" % failures.size())
		for f in failures:
			push_error("AUDIT FAIL: " + f)
		get_tree().quit(1)


func _run_headless_full_lap_audit() -> Array[String]:
	var failures: Array[String] = []
	# 4x wall-clock speedup while keeping IDENTICAL fixed 60 Hz physics delta (1/60s)!
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = 8

	var tracks := TrackCatalog.get_tracks()

	# 0. Verify Engine Main & BGM audio streams are configured to loop cleanly!
	print("\n--- [0] AUDIO LOOP INTEGRITY CHECK ---")
	var eng_stream: AudioStream = AudioManager.sfx_streams.get("engine_main", null)
	var bgm_stream: AudioStream = AudioManager.sfx_streams.get("bgm_loop", null)
	var eng_loop_ok := (eng_stream is AudioStreamWAV) and ((eng_stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED)
	var bgm_loop_ok := (bgm_stream is AudioStreamWAV) and ((bgm_stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED)
	print("   engine_main loop_mode=%d (ok=%s) | bgm_loop loop_mode=%d (ok=%s)" % [
		(eng_stream as AudioStreamWAV).loop_mode if eng_stream is AudioStreamWAV else -1,
		str(eng_loop_ok),
		(bgm_stream as AudioStreamWAV).loop_mode if bgm_stream is AudioStreamWAV else -1,
		str(bgm_loop_ok)
	])
	if not eng_loop_ok:
		failures.append("AudioManager engine_main is NOT set to loop!")
	if not bgm_loop_ok:
		failures.append("AudioManager bgm_loop is NOT set to loop!")

	# A. Test all 4 cars' real acceleration, distinct top speeds, & Arcade Rail-Drift benchmark
	print("\n--- [A] ALL 4 CARS PERFORMANCE & ARCADE RAIL-DRIFT BENCHMARK ---")
	var car_metrics: Array[Dictionary] = []
	for car_idx in range(CarCatalog.get_cars().size()):
		var spec := CarCatalog.get_car(car_idx)
		GameState.mode = "free_roam"
		GameState.selected_track_idx = 0
		GameState.selected_car_idx = car_idx
		GameState.selected_livery_idx = car_idx
		var rm: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
		get_tree().root.add_child(rm)
		await _wait_phys(4)
		rm.countdown_timer = 5.0
		await _wait_phys(3)
		rm.player_controller.set_physics_process(false)
		var pc := rm.player_car
		var t_100 := -1.0
		var max_kmh := 0.0
		for step in range(240): # 4.0s straight on real Coastal Sunway tarmac
			pc.throttle_input = 1.0
			pc.brake_input = 0.0
			pc.steering_input = 0.0
			pc.handbrake_input = 0.0
			pc.nitro_input = false
			await get_tree().physics_frame
			var spd := pc.get_speed_kmh()
			max_kmh = maxf(max_kmh, spd)
			if t_100 < 0.0 and spd >= 100.0:
				t_100 = float(step) / 60.0

		# Move car onto a clean wide Road skidpad (y = 60) for barrier-free Rail-Drift precision test
		var pad := StaticBody3D.new()
		pad.name = "DriftSkidpad"
		pad.collision_layer = 1
		pad.collision_mask = 0
		pad.add_to_group("Road")
		var pad_col := CollisionShape3D.new()
		var pad_box := BoxShape3D.new()
		pad_box.size = Vector3(600.0, 1.0, 600.0)
		pad_col.shape = pad_box
		pad_col.position = Vector3(0.0, 59.5, 0.0)
		pad.add_child(pad_col)
		rm.add_child(pad)
		await _wait_phys(2)

		var pad_xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 60.08, 0.0))
		pc.reset_to_transform(pad_xf)
		pc.controls_locked = false
		pc.enable_arcade_drift = true
		pc.linear_velocity = Vector3(0.0, 0.0, -48.0) # 172.8 km/h entry speed
		pc.current_gear = 4
		await _wait_phys(5)

		var entry_kmh := pc.get_speed_kmh()
		var boost_fired := [0]
		pc.drift_boost_triggered.connect(func(tier: int): boost_fired[0] = maxi(boost_fired[0], tier))

		var entered_rail := false
		var max_drift_angle := 0.0
		var min_drift_kmh := 999.0
		var peak_tier := 0
		var min_wheel_cs := 0.0
		var nitro_start := pc.nitro
		var nitro_after_drift := pc.nitro

		# Phase 1: 1.75s Space + Left rail-drift
		for step in range(105):
			pc.throttle_input = 1.0
			pc.brake_input = 0.0
			pc.steering_input = 1.0
			pc.handbrake_input = 1.0 if step < 12 else 0.0
			pc.nitro_input = false
			await get_tree().physics_frame
			if pc.arcade_drift_active:
				entered_rail = true
				max_drift_angle = maxf(max_drift_angle, pc.drift_angle_deg)
				min_drift_kmh = minf(min_drift_kmh, pc.get_speed_kmh())
				peak_tier = maxi(peak_tier, pc.drift_boost_tier)
				nitro_after_drift = maxf(nitro_after_drift, pc.nitro)
				if pc.front_left_wheel != null:
					min_wheel_cs = minf(min_wheel_cs, pc.front_left_wheel.rotation.y)

		var pre_exit_kmh := pc.get_speed_kmh()
		var post_exit_max_kmh := pre_exit_kmh
		var exited_cleanly := false

		# Phase 2: 0.70s Release straight -> Clean Exit + Exit Mini-Turbo!
		for step in range(42):
			pc.throttle_input = 1.0
			pc.brake_input = 0.0
			pc.steering_input = 0.0
			pc.handbrake_input = 0.0
			pc.nitro_input = false
			await get_tree().physics_frame
			if not pc.arcade_drift_active:
				exited_cleanly = true
			post_exit_max_kmh = maxf(post_exit_max_kmh, pc.get_speed_kmh())

		var retention_pct := (min_drift_kmh / maxf(entry_kmh, 1.0)) * 100.0 if min_drift_kmh < 900.0 else 0.0
		var total_dscore := pc.current_drift_score + float(pc.total_drift_score)
		car_metrics.append({
			"id": spec["id"],
			"t_100": t_100,
			"max_kmh": max_kmh,
			"drifted": entered_rail,
			"drift_score": total_dscore,
			"max_angle": max_drift_angle
		})
		print("Car[%d] %s: 0-100=%.2fs max=%.1fkmh | rail=%s entry=%.0f->min=%.0f(%.0f%%) ang=%.1fdeg cs_wheel=%.2frad tier=%d->boost=LV%d exit_spd=%.0f->%.0f score=%.0f nitro %.0f->%.0f" % [
			car_idx, spec["id"], t_100, max_kmh, str(entered_rail), entry_kmh, min_drift_kmh, retention_pct, max_drift_angle, min_wheel_cs, peak_tier, boost_fired[0], pre_exit_kmh, post_exit_max_kmh, total_dscore, nitro_start, nitro_after_drift
		])
		if not entered_rail:
			failures.append("Car %s failed to enter arcade rail-drift" % spec["id"])
		if retention_pct < 85.0:
			failures.append("Car %s rail-drift speed retention too low: %.1f%% (expected >= 85%%)" % [spec["id"], retention_pct])
		if max_drift_angle < 22.0 or max_drift_angle > 54.0:
			failures.append("Car %s rail-drift angle out of arcade range: %.1fdeg" % [spec["id"], max_drift_angle])
		if min_wheel_cs > -0.15:
			failures.append("Car %s front wheels failed to visually counter-steer (rot.y=%.2f)" % [spec["id"], min_wheel_cs])
		if not exited_cleanly or boost_fired[0] < 2:
			failures.append("Car %s failed clean exit mini-turbo (exited=%s boost_tier=%d)" % [spec["id"], str(exited_cleanly), boost_fired[0]])
		if post_exit_max_kmh <= pre_exit_kmh + 6.0:
			failures.append("Car %s exit mini-turbo did not boost speed (%.1f -> %.1f)" % [spec["id"], pre_exit_kmh, post_exit_max_kmh])

		# Extra mechanics check on Car 0: Brake-to-Drift (S tap + D) & S-Curve Chain Switch (Left -> Right)
		if car_idx == 0:
			pc.reset_to_transform(pad_xf)
			pc.controls_locked = false
			pc.enable_arcade_drift = true
			pc.linear_velocity = Vector3(0.0, 0.0, -40.0) # 144 km/h
			pc.current_gear = 3
			await _wait_phys(4)
			# Trigger Brake-to-Drift right (steer=-1.0 + brake tap)
			pc.throttle_input = 1.0
			pc.steering_input = -1.0
			pc.brake_input = 0.85
			pc.handbrake_input = 0.0
			await _wait_phys(2)
			pc.brake_input = 0.0
			await _wait_phys(18)
			var b2d_ok := pc.arcade_drift_active and pc.drift_dir < -0.5
			# Now S-Curve Chain Switch to LEFT (steer=+1.0 + Space tap!)
			pc.steering_input = 1.0
			pc.handbrake_input = 1.0
			await _wait_phys(2)
			pc.handbrake_input = 0.0
			await _wait_phys(10)
			var scurve_ok := pc.arcade_drift_active and pc.drift_dir > 0.5
			print("   Arcade Drift Extras: Brake-to-Drift=%s | S-Curve Chain-Switch=%s" % [str(b2d_ok), str(scurve_ok)])
			if not b2d_ok:
				failures.append("Brake-to-Drift (S tap + steer) failed to engage right rail-drift")
			if not scurve_ok:
				failures.append("S-Curve Chain Switch (Space + opposite steer) failed to flip drift_dir")

		rm.queue_free()
		await _wait_phys(3)

	# Assert kaze_drift earns > 400 drift score and beats all other cars!
	var kaze_score := float(car_metrics[1]["drift_score"])
	if kaze_score <= 400.0:
		failures.append("kaze_drift drift_score too low: %.1f (expected > 400)" % kaze_score)
	for i in range(car_metrics.size()):
		if i != 1 and float(car_metrics[i]["drift_score"]) >= kaze_score:
			failures.append("kaze_drift (%.0f) did not beat %s (%.0f) in drift score" % [kaze_score, car_metrics[i]["id"], car_metrics[i]["drift_score"]])
	# Assert 0-100 ordering: vortex_f0 <= titan_rally <= kaze_drift <= apex_gtr
	var t_apex := float(car_metrics[0]["t_100"])
	var t_kaze := float(car_metrics[1]["t_100"])
	var t_vortex := float(car_metrics[2]["t_100"])
	var t_titan := float(car_metrics[3]["t_100"])
	if not (t_vortex < t_titan and t_titan < t_kaze and t_kaze <= t_apex + 0.05):
		failures.append("0-100 ordering mismatch: vortex=%.2f titan=%.2f kaze=%.2f apex=%.2f" % [t_vortex, t_titan, t_kaze, t_apex])

	# B. FULL 2-LAP 6-car race simulation on ALL 3 tracks!
	print("\n--- [B] FULL 2-LAP 6-CAR RACE SIMULATION (ALL 3 TRACKS) ---")
	for t_idx in range(tracks.size()):
		var tr: Dictionary = tracks[t_idx]
		GameState.mode = "quick_race"
		GameState.selected_track_idx = t_idx
		GameState.selected_car_idx = 0
		GameState.selected_livery_idx = 0
		GameState.difficulty = 2 # Master AI to measure fast full-lap times!
		GameState.lap_count = 2

		var rm: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
		get_tree().root.add_child(rm)
		await _wait_phys(6)
		rm.countdown_timer = 5.0
		await _wait_phys(3)

		rm.player_controller.set_physics_process(false)
		var auto_p := AIDriver.new()
		rm.player_car.add_child(auto_p)
		auto_p.setup(rm.player_car, rm.spline, rm.cars, null, {"skill_offset": 0.05, "preferred_lane": 0.0}, 2, rm.boost_distances)

		var boost_counts := [0, 0] # [player_hits, total_all_car_hits] (Array for lambda ref capture)
		rm.player_car.boost_pad_hit.connect(func(): boost_counts[0] += 1)
		for cc in rm.cars:
			cc.boost_pad_hit.connect(func(): boost_counts[1] += 1)

		var max_steps := 7800 # up to 130s simulated physics (2 full laps)
		var lap1_time := -1.0
		var lap2_time := -1.0
		var lap1_end_elapsed := 0.0
		var max_kmh := 0.0
		var min_wheels_seen := 4
		var flipped_count := 0
		var max_lat_err := 0.0

		for s in range(max_steps):
			await get_tree().physics_frame
			var spd := rm.player_car.get_speed_kmh()
			max_kmh = maxf(max_kmh, spd)
			min_wheels_seen = mini(min_wheels_seen, rm.player_car.get_wheel_contact_count())
			if rm.player_car.global_transform.basis.y.y < 0.35:
				flipped_count += 1
			var pinfo := rm.spline.get_progress(rm.player_car.global_position, rm.player_car.spline_index)
			max_lat_err = maxf(max_lat_err, absf(float(pinfo["lateral"])))
			if rm.player_car.current_lap >= 2 and lap1_time < 0.0:
				lap1_time = rm.player_car.best_lap_time
				lap1_end_elapsed = rm.race_elapsed
			if rm.player_car.finished:
				lap2_time = rm.player_car.finish_time - lap1_end_elapsed
				break

		var boost_hits: int = boost_counts[0]
		var all_boost_hits: int = boost_counts[1]
		var ai_completed_lap1 := 0
		var ai_finished := 0
		var ai_laps_str := ""
		for c in rm.cars:
			if not c.is_player:
				if c.current_lap >= 2 or c.finished:
					ai_completed_lap1 += 1
				if c.finished:
					ai_finished += 1
				ai_laps_str += "%s(L%d,cp%d,best=%.1fs) " % [c.driver_name, c.current_lap, c.next_checkpoint, c.best_lap_time]

		var mt: Dictionary = tr["medal_times"]
		print("Track[%d] %s: lap1=%.2fs lap2(fly)=%.2fs best=%.2fs (medals G=%.1f/S=%.1f/B=%.1f) max=%.1fkmh boost_hits=%d(all=%d) max_lat=%.1fm flipped=%d ai_L1=%d/5 ai_fin=%d/5" % [
			t_idx, tr["id"], lap1_time, lap2_time, rm.player_car.best_lap_time, mt["gold"], mt["silver"], mt["bronze"], max_kmh, boost_hits, all_boost_hits, max_lat_err, flipped_count, ai_completed_lap1, ai_finished
		])
		print("   AI status: " + ai_laps_str)

		if lap1_time <= 0.0 or lap2_time <= 0.0:
			failures.append("Track[%d] %s did not complete 2 full laps (lap1=%.2f, lap2=%.2f)" % [t_idx, tr["id"], lap1_time, lap2_time])
		if boost_hits < 1:
			failures.append("Track[%d] %s had 0 boost pad hits" % [t_idx, tr["id"]])
		if flipped_count > 0:
			failures.append("Track[%d] %s flipped %d frames" % [t_idx, tr["id"], flipped_count])
		if max_lat_err > 7.6:
			failures.append("Track[%d] %s max_lat=%.2fm exceeded 7.6m limit" % [t_idx, tr["id"], max_lat_err])
		if lap2_time > float(mt["bronze"]) or lap2_time > float(mt["silver"]) + 1.5:
			failures.append("Track[%d] %s flying lap2=%.2fs out of medal calibration range (G=%.1f/S=%.1f/B=%.1f)" % [
				t_idx, tr["id"], lap2_time, mt["gold"], mt["silver"], mt["bronze"]
			])

		# Also verify Quick Race ghost timestamp normalization on Track 0
		if t_idx == 0:
			var qr_rec := GameState.get_track_record(str(tr["id"]))
			var qr_ghost: Array = qr_rec.get("ghost", [])
			var qr_t0 := float(qr_ghost[0][0]) if qr_ghost.size() > 0 else 99.0
			print("   Quick Race ghost frames=%d first_t=%.2f" % [qr_ghost.size(), qr_t0])
			if qr_ghost.size() < 10 or qr_t0 > 0.15:
				failures.append("Quick Race ghost timestamp not normalized (frames=%d t0=%.2f)" % [qr_ghost.size(), qr_t0])

		# Run feature assertions on Track 0 before freeing
		if t_idx == 0:
			auto_p.queue_free()
			await _wait_phys(2)
			# Reset race_state to racing for interactive assertions
			rm.race_state = "racing"
			rm.player_car.finished = false

			# (1) Wrong-Way Detection & Respawn
			var prev_xf := rm.player_car.global_transform
			var reversed_xf := prev_xf.rotated_local(Vector3.UP, PI)
			rm.player_car.reset_to_transform(reversed_xf)
			rm.player_car.linear_velocity = -reversed_xf.basis.z * 15.0
			await _wait_phys(3)
			var ww_detected: bool = rm.hud._wrong_way
			rm._on_player_respawn()
			await _wait_phys(3)
			var after_respawn_dot := (-rm.player_car.global_transform.basis.z).dot(rm.spline.tangents[rm.player_car.spline_index])
			print("   Wrong-Way detected=%s | After Respawn forward_dot=%.3f" % [str(ww_detected), after_respawn_dot])
			if not ww_detected or after_respawn_dot < 0.9:
				failures.append("Wrong-way (%s) or respawn dot (%.3f) failed" % [str(ww_detected), after_respawn_dot])

			# (2) Reverse-behind-start-line anti-exploit check
			rm.player_car.current_lap = 1
			rm.player_car.next_checkpoint = 0
			rm._car_has_crossed_start[rm.player_car] = true
			for c in rm.cars:
				if not c.is_player:
					c.finished = false
					c.current_lap = 1
					c.next_checkpoint = 1
					rm._car_has_crossed_start[c] = true
					c.reset_to_transform(rm.spline.get_transform_at_distance(rm.spline.total_length * 0.16, 0.0, 0.10))
			var behind_xf := rm.spline.get_transform_at_distance(rm.spline.total_length - 12.0, 0.0, 0.10)
			rm.player_car.reset_to_transform(behind_xf)
			rm._car_prev_progress[rm.player_car] = 0.01
			await _wait_phys(3)
			print("   Reverse-behind-start check: progress=%.3f rank=%d/6" % [rm.player_car.total_race_progress, rm.player_car.race_rank])
			if rm.player_car.total_race_progress >= 0.0 or rm.player_car.race_rank == 1:
				failures.append("Reverse-behind-start rank exploit triggered: prog=%.3f rank=%d" % [rm.player_car.total_race_progress, rm.player_car.race_rank])

			# (3) Pause & Unpause via pause_game action + Mid-race HUD language switch
			var ev_pause := InputEventAction.new()
			ev_pause.action = "pause_game"
			ev_pause.pressed = true
			get_viewport().push_input(ev_pause)
			await _wait_frames(2)
			var paused_ok := get_tree().paused and rm.pause_menu.visible
			var prev_pos_sub := rm.hud._pos_sub.text
			GameState.toggle_language()
			await _wait_frames(1)
			var lang_updated := rm.hud._pos_sub.text != prev_pos_sub
			GameState.toggle_language()
			var ev_unpause := InputEventAction.new()
			ev_unpause.action = "pause_game"
			ev_unpause.pressed = true
			get_viewport().push_input(ev_unpause)
			await _wait_frames(2)
			var unpaused_ok := (not get_tree().paused) and (not rm.pause_menu.visible)
			print("   Pause/Unpause via pause_game: paused=%s unpaused=%s mid_race_hud_lang=%s" % [str(paused_ok), str(unpaused_ok), str(lang_updated)])
			if not paused_ok or not unpaused_ok:
				failures.append("Pause/Unpause via pause_game failed (paused=%s unpaused=%s)" % [str(paused_ok), str(unpaused_ok)])
			if not lang_updated:
				failures.append("Mid-race HUD language switch did not update RaceHUD")

		rm.queue_free()
		await _wait_phys(4)

	# B2. Clean Time-Trial flying lap benchmark with VORTEX F-ZERO across all 3 tracks (verifies Gold reachability!)
	print("\n--- [B2] VORTEX F-ZERO FLYING-LAP BENCHMARK (ALL 3 TRACKS) ---")
	for t_idx in range(tracks.size()):
		var tr: Dictionary = tracks[t_idx]
		GameState.mode = "time_trial"
		GameState.selected_track_idx = t_idx
		GameState.selected_car_idx = 2 # vortex_f0
		GameState.selected_livery_idx = 1
		var rm_v: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
		get_tree().root.add_child(rm_v)
		await _wait_phys(4)
		rm_v.countdown_timer = 5.0
		await _wait_phys(3)
		rm_v.player_controller.set_physics_process(false)
		var ai_v := AIDriver.new()
		rm_v.player_car.add_child(ai_v)
		ai_v.setup(rm_v.player_car, rm_v.spline, rm_v.cars, null, {"skill_offset": 0.08, "preferred_lane": 0.0}, 2, rm_v.boost_distances)
		var v_lap1 := -1.0
		var v_lap2 := -1.0
		var v_lap1_end := 0.0
		var v_max_lat := 0.0
		var v_max_kmh := 0.0
		for _s in range(6600):
			await get_tree().physics_frame
			v_max_kmh = maxf(v_max_kmh, rm_v.player_car.get_speed_kmh())
			var pinfo := rm_v.spline.get_progress(rm_v.player_car.global_position, rm_v.player_car.spline_index)
			v_max_lat = maxf(v_max_lat, absf(float(pinfo["lateral"])))
			if rm_v.player_car.current_lap >= 2 and v_lap1 < 0.0:
				v_lap1 = rm_v.player_car.best_lap_time
				v_lap1_end = rm_v.race_elapsed
			if rm_v.player_car.current_lap >= 3:
				v_lap2 = rm_v.race_elapsed - v_lap1_end
				break
		var mt: Dictionary = tr["medal_times"]
		print("VortexF0 Track[%d] %s: lap1=%.2fs lap2(fly)=%.2fs best=%.2fs (G=%.1f/S=%.1f/B=%.1f) max=%.1fkmh max_lat=%.1fm" % [
			t_idx, tr["id"], v_lap1, v_lap2, rm_v.player_car.best_lap_time, mt["gold"], mt["silver"], mt["bronze"], v_max_kmh, v_max_lat
		])
		if v_max_lat > 7.6:
			failures.append("VortexF0 Track[%d] max_lat=%.2fm exceeded 7.6m" % [t_idx, v_max_lat])
		if v_lap2 <= 0.0 or v_lap2 > float(mt["gold"]) + 1.5:
			failures.append("VortexF0 Track[%d] flying lap2=%.2fs too far from Gold=%.1f" % [t_idx, v_lap2, mt["gold"]])
		rm_v.queue_free()
		await _wait_phys(3)

	# C. Grand Prix 3-round podium sorting test
	print("\n--- [C] GRAND PRIX 3-ROUND PODIUM SORTING TEST ---")
	GameState.start_grand_prix()
	# Round 1 & 2: PLAYER 1st (10+10=20), ELENA 2nd (8+8=16)
	for r in range(2):
		var round_rows: Array[Dictionary] = [
			{"driver_name": "PLAYER", "is_player": true, "car_idx": 0, "finish_time": 110.0, "best_lap": 35.0},
			{"driver_name": "ELENA", "is_player": false, "car_idx": 2, "finish_time": 112.0, "best_lap": 36.0}
		]
		GameState.record_grand_prix_results(round_rows)
		GameState.advance_grand_prix_round()
	# Round 3: ELENA wins race (16+10=26), PLAYER 2nd in race (20+8=28 -> OVERALL CHAMPION!)
	var r3_rows: Array[Dictionary] = [
		{"driver_name": "ELENA", "is_player": false, "car_idx": 2, "finish_time": 108.0, "best_lap": 34.0},
		{"driver_name": "PLAYER", "is_player": true, "car_idx": 0, "finish_time": 109.5, "best_lap": 34.5}
	]
	GameState.record_grand_prix_results(r3_rows)
	var rs := ResultsScreen.new()
	get_tree().root.add_child(rs)
	rs.show_results({
		"results": r3_rows,
		"track": tracks[2],
		"is_gp": true,
		"gp_round": 2,
		"has_next_gp": false,
		"is_new_record": false,
		"medal": "gold",
		"drift_score": 450
	})
	await _wait_frames(2)
	# Row 0 is header, Row 1 is #1 Champion -> child 1 inside HBox is driver label
	var first_row_panel := rs._table_box.get_child(1)
	var first_driver_txt: String = first_row_panel.get_child(0).get_child(1).text
	var second_driver_txt: String = rs._table_box.get_child(2).get_child(0).get_child(1).text
	print("   GP Final Podium #1='%s' (28 pts) | #2='%s' (26 pts)" % [first_driver_txt, second_driver_txt])
	if first_driver_txt != GameState.t("res_you"):
		failures.append("GP podium did not sort by total_points: #1 was '%s'" % first_driver_txt)
	rs.queue_free()
	await _wait_frames(2)

	# Tie-break consistency check: tied total_points (26 vs 26), ELENA faster in final round -> must NOT award gp_title to PLAYER!
	var titles_before := int(GameState.career.get("gp_titles", 0))
	GameState.start_grand_prix()
	GameState.gp_round = 2
	GameState.gp_standings = {"PLAYER": 18, "ELENA": 16}
	var tie_r3: Array[Dictionary] = [
		{"driver_name": "ELENA", "is_player": false, "car_idx": 2, "finish_time": 107.0, "best_lap": 34.0},
		{"driver_name": "PLAYER", "is_player": true, "car_idx": 0, "finish_time": 109.0, "best_lap": 34.8}
	]
	GameState.record_grand_prix_results(tie_r3)
	var titles_after_loss := int(GameState.career.get("gp_titles", 0))
	print("   GP tie-break check (26 vs 26, ELENA faster R3): gp_titles %d->%d" % [titles_before, titles_after_loss])
	if titles_after_loss != titles_before:
		failures.append("GP tie-break awarded title to PLAYER despite losing R3 finish_time tie-break")

	# D. Time Trial Ghost Car Synchronization Test
	print("\n--- [D] TIME TRIAL GHOST CAR SYNC TEST ---")
	var sp0 := TrackSpline.new()
	sp0.build_from_control_points(tracks[0]["control_points"], float(tracks[0]["road_width"]), float(tracks[0]["bank_strength"]), 3.0)
	var ghost_samples: Array = []
	for k in range(20):
		var gxf := sp0.get_transform_at_distance(float(k) * 4.0, 0.0, 0.1)
		var gr := gxf.basis.get_euler()
		ghost_samples.append([float(k) * 0.1, gxf.origin.x, gxf.origin.y, gxf.origin.z, gr.x, gr.y, gr.z])
	GameState.save_lap_record("coastal_sunway", 38.0, ghost_samples)
	GameState.mode = "time_trial"
	GameState.selected_track_idx = 0
	var tt_rm: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(tt_rm)
	await _wait_phys(4)
	tt_rm.countdown_timer = 5.0
	await _wait_phys(3)
	tt_rm.player_controller.set_physics_process(false)
	var ghost_held_before_line := (tt_rm.ghost_car != null) and (not tt_rm.ghost_car.is_playing)
	# Drive player forward across start line (dist = 0.0)
	var crossed := false
	for _s in range(180):
		tt_rm.player_car.throttle_input = 1.0
		tt_rm.player_car.steering_input = 0.0
		await get_tree().physics_frame
		if bool(tt_rm._car_has_crossed_start.get(tt_rm.player_car, false)):
			crossed = true
			break
	var ghost_playing_after_line := (tt_rm.ghost_car != null) and tt_rm.ghost_car.is_playing
	var lap_time_reset_ok := tt_rm.player_car.current_lap_time < 0.25
	await _wait_phys(10)
	var first_ghost_t := float(tt_rm._ghost_lap_frames[0][0]) if tt_rm._ghost_lap_frames.size() > 0 else 99.0
	print("   Ghost held before line=%s | crossed=%s | playing after=%s | lap_t_reset=%s | first_rec_t=%.2f" % [
		str(ghost_held_before_line), str(crossed), str(ghost_playing_after_line), str(lap_time_reset_ok), first_ghost_t
	])
	if not (ghost_held_before_line and crossed and ghost_playing_after_line and lap_time_reset_ok and first_ghost_t <= 0.15):
		failures.append("Time Trial Ghost sync failed (held=%s crossed=%s playing=%s reset=%s t0=%.2f)" % [
			str(ghost_held_before_line), str(crossed), str(ghost_playing_after_line), str(lap_time_reset_ok), first_ghost_t
		])
	tt_rm.queue_free()
	await _wait_phys(4)

	# Restore normal physics rate
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	return failures


func _run_visual_audit() -> void:
	# Capture all 4 cars in showroom, English & Chinese UI, Settings modal,
	# F1 Countdown lights, Sakura Mid-Corner, Hood Cam, Pause Menu, Neon Midnight, and GP Podium!
	GameState.settings["language"] = "zh"
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 0
	var menu: MainMenu = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child(menu)

	for ci in range(4):
		GameState.selected_car_idx = ci
		GameState.selected_livery_idx = ci
		menu._rebuild_showroom_car()
		menu._refresh_all()
		await _wait_frames(6)
		await _save_shot("car_%d_%s.png" % [ci, CarCatalog.get_car(ci)["id"]])

	# Settings modal & English mode
	menu._settings_modal.visible = true
	await _wait_frames(4)
	await _save_shot("modal_settings_zh.png")
	menu._settings_modal.visible = false

	GameState.toggle_language()
	await _wait_frames(4)
	await _save_shot("main_menu_en.png")
	GameState.toggle_language() # back to zh
	menu.queue_free()
	await _wait_frames(4)

	# Sakura Mountain Pass: Countdown lights, Mid-Corner Drift/Action, Hood Cam, Pause Menu
	GameState.mode = "quick_race"
	GameState.selected_track_idx = 1 # Sakura Mountain Pass
	GameState.selected_car_idx = 1   # KAZE DRIFT-S
	GameState.selected_livery_idx = 3 # Sakura Pearl
	var rm: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm)
	rm.countdown_timer = 1.8 # 3 red lights illuminated!
	await _wait_phys(8)
	await _save_shot("race_countdown_lights.png")

	rm.countdown_timer = 5.0
	rm.player_controller.set_physics_process(false)
	var ai := AIDriver.new()
	rm.player_car.add_child(ai)
	ai.setup(rm.player_car, rm.spline, rm.cars, null, {"skill_offset": 0.08, "preferred_lane": 0.0}, 2, rm.boost_distances)
	for s in range(280):
		await get_tree().physics_frame
		if s == 200:
			rm.player_car.nitro_input = true
		if s == 220:
			await _save_shot("race_sakura_midturn.png")
		if s == 250:
			rm._on_camera_switch() # Far
			rm._on_camera_switch() # Hood Cam!
			await _wait_frames(4)
			await _save_shot("race_hood_cam.png")

	# Pause menu
	rm._toggle_pause()
	await _wait_frames(4)
	await _save_shot("race_pause_menu.png")
	rm._toggle_pause()
	rm.queue_free()
	await _wait_frames(4)

	# Neon Midnight Circuit + Grand Prix Final Podium!
	GameState.settings["camera_mode"] = 0
	GameState.start_grand_prix()
	GameState.selected_track_idx = 2 # Neon Midnight Circuit
	GameState.gp_round = 2
	GameState.selected_car_idx = 2   # VORTEX F-ZERO
	GameState.selected_livery_idx = 1 # Cyber Cyan
	GameState.gp_standings = {"PLAYER": 20, "ELENA": 16, "KENJI": 12, "MARCO": 8, "SORA": 4, "VIKTOR": 2}
	var rm_neon: RaceManager = load("res://scenes/race_scene.tscn").instantiate()
	get_tree().root.add_child(rm_neon)
	rm_neon.countdown_timer = 5.0
	await _wait_phys(4)
	rm_neon.player_controller.set_physics_process(false)
	var ai_neon := AIDriver.new()
	rm_neon.player_car.add_child(ai_neon)
	ai_neon.setup(rm_neon.player_car, rm_neon.spline, rm_neon.cars, null, {"skill_offset": 0.08, "preferred_lane": 0.0}, 2, rm_neon.boost_distances)
	for s in range(230):
		await get_tree().physics_frame
		if s == 165:
			rm_neon.player_car.nitro_input = true
		if s == 195:
			await _save_shot("race_neon_midnight.png")

	# Show Grand Prix Final Championship Podium sorted by cumulative total_points!
	var mock_gp_rows: Array[Dictionary] = [
		{"driver_name": "ELENA", "is_player": false, "car_idx": 2, "finish_time": 118.2, "best_lap": 38.4},
		{"driver_name": "PLAYER", "is_player": true, "car_idx": 2, "finish_time": 118.9, "best_lap": 38.7},
		{"driver_name": "KENJI", "is_player": false, "car_idx": 1, "finish_time": 121.4, "best_lap": 39.8},
		{"driver_name": "MARCO", "is_player": false, "car_idx": 0, "finish_time": 123.1, "best_lap": 40.3},
		{"driver_name": "SORA", "is_player": false, "car_idx": 3, "finish_time": 124.8, "best_lap": 40.9},
		{"driver_name": "VIKTOR", "is_player": false, "car_idx": 0, "finish_time": 126.5, "best_lap": 41.5}
	]
	GameState.record_grand_prix_results(mock_gp_rows)
	rm_neon.results_screen.show_results({
		"results": mock_gp_rows,
		"track": TrackCatalog.get_track(2),
		"is_gp": true,
		"gp_round": 2,
		"has_next_gp": false,
		"is_new_record": true,
		"medal": "gold",
		"drift_score": 1420
	})
	await _wait_frames(5)
	await _save_shot("results_gp_podium.png")
	rm_neon.queue_free()
	await _wait_frames(4)


func _wait_phys(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _save_shot(fname: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		var path := AUDIT_SHOT_DIR + "/" + fname
		img.save_png(path)
		print("Audit shot: " + path)

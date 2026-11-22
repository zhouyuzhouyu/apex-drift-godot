class_name MainMenu
extends Node3D

## Main Menu + Live 3D Rotating Showroom Turntable!
## Lets the player pick Game Mode, Circuit (with live vector minimap & saved medals),
## Car & Livery (with instant 3D showroom preview & stat bars), Difficulty, Laps, Settings, and Controls.

var _turntable: Node3D
var _car_mount: Node3D
var _turntable_ring_mat: StandardMaterial3D
var _camera: Camera3D

var _ui_layer: CanvasLayer
var _title_lbl: Label
var _subtitle_lbl: Label
var _career_lbl: Label
var _mode_desc_lbl: Label
var _mode_buttons: Dictionary = {}
var _track_buttons: Array[Button] = []
var _track_minimap: Control
var _track_info_lbl: Label
var _track_record_lbl: Label
var _diff_buttons: Array[Button] = []
var _lap_buttons: Array[Button] = []
var _options_row: Control
var _car_buttons: Array[Button] = []
var _livery_buttons: Array[Button] = []
var _car_title_lbl: Label
var _car_class_lbl: Label
var _car_desc_lbl: Label
var _stat_bars: Dictionary = {}
var _stat_labels: Dictionary = {}
var _start_btn: Button
var _lang_btn: Button
var _settings_btn: Button
var _controls_btn: Button
var _lbl_mode_hdr: Label
var _lbl_track_hdr: Label
var _lbl_car_hdr: Label
var _lbl_livery_hdr: Label
var _lbl_diff: Label
var _lbl_laps: Label

var _settings_modal: Control
var _controls_modal: Control
var _preview_spline_pts: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	get_tree().paused = false
	AudioManager.stop_driving_audio()
	AudioManager.apply_volumes()
	_build_3d_showroom()
	_build_ui()
	_rebuild_showroom_car()
	_refresh_all()
	GameState.language_changed.connect(func(_l): _refresh_all())


func _process(delta: float) -> void:
	if _turntable:
		_turntable.rotate_y(delta * 0.42)


func _build_3d_showroom() -> void:
	# Sleek Dark Motorsport Garage Showroom Environment
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var smat := ProceduralSkyMaterial.new()
	smat.sky_top_color = Color(0.04, 0.06, 0.14)
	smat.sky_horizon_color = Color(0.11, 0.14, 0.26)
	smat.ground_bottom_color = Color(0.03, 0.04, 0.08)
	smat.ground_horizon_color = Color(0.09, 0.11, 0.20)
	sky.sky_material = smat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.56, 0.78)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)

	# Key & Rim Lights
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.96, 0.92)
	key_light.light_energy = 1.65
	key_light.shadow_enabled = true
	key_light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	add_child(key_light)

	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color(0.10, 0.85, 1.0)
	rim_light.light_energy = 2.8
	rim_light.omni_range = 16.0
	rim_light.position = Vector3(-4.2, 3.2, -3.5)
	add_child(rim_light)

	var warm_rim := OmniLight3D.new()
	warm_rim.light_color = Color(1.0, 0.25, 0.42)
	warm_rim.light_energy = 2.4
	warm_rim.omni_range = 16.0
	warm_rim.position = Vector3(4.5, 2.5, 3.2)
	add_child(warm_rim)

	# Glossy Showroom Floor
	var floor_mesh := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(60.0, 60.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.07, 0.08, 0.13)
	fmat.roughness = 0.25
	fmat.metallic = 0.35
	floor_mesh.mesh = fp
	floor_mesh.material_override = fmat
	floor_mesh.position = Vector3(0.0, -0.02, 0.0)
	add_child(floor_mesh)

	# Rotating Pedestal Turntable positioned cleanly in upper-right showcase window
	_turntable = Node3D.new()
	_turntable.position = Vector3(1.05, 0.28, 0.0)
	add_child(_turntable)

	var disc := MeshInstance3D.new()
	var dc := CylinderMesh.new()
	dc.top_radius = 3.12
	dc.bottom_radius = 3.28
	dc.height = 0.22
	dc.radial_segments = 48
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.10, 0.12, 0.18)
	dmat.metallic = 0.55
	dmat.roughness = 0.22
	disc.mesh = dc
	disc.material_override = dmat
	disc.position = Vector3(0.0, 0.11, 0.0)
	_turntable.add_child(disc)

	# Sleek Glowing Outer Rim Ring tucked just below pedestal top surface
	var ring := MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 3.30
	rc.bottom_radius = 3.36
	rc.height = 0.09
	rc.radial_segments = 48
	_turntable_ring_mat = StandardMaterial3D.new()
	_turntable_ring_mat.albedo_color = UITheme.ACCENT_CYAN
	_turntable_ring_mat.emission_enabled = true
	_turntable_ring_mat.emission = UITheme.ACCENT_CYAN
	_turntable_ring_mat.emission_energy_multiplier = 2.0
	ring.mesh = rc
	ring.material_override = _turntable_ring_mat
	ring.position = Vector3(0.0, 0.13, 0.0)
	_turntable.add_child(ring)

	_car_mount = Node3D.new()
	_car_mount.position = Vector3(0.0, 0.22, 0.0)
	_turntable.add_child(_car_mount)

	# Hero Showroom Camera framing the entire car cleanly above the garage panel
	_camera = Camera3D.new()
	_camera.fov = 40.0
	_camera.position = Vector3(-2.45, 2.45, 7.25)
	add_child(_camera)
	_camera.look_at(Vector3(-0.35, 0.45, 0.0), Vector3.UP)
	_camera.current = true


func _rebuild_showroom_car() -> void:
	for c in _car_mount.get_children():
		c.queue_free()

	var spec := CarCatalog.get_car(GameState.selected_car_idx)
	var livery := CarCatalog.get_livery(GameState.selected_livery_idx)
	CarMeshBuilder.build_car_visuals(_car_mount, str(spec["style"]), livery, false)

	var rim_col: Color = livery["rim"]
	var wheel_spots := [
		Vector3(-0.84, 0.34, -1.28),
		Vector3( 0.84, 0.34, -1.28),
		Vector3(-0.85, 0.35,  1.28),
		Vector3( 0.85, 0.35,  1.28)
	]
	for i in range(4):
		var wn := Node3D.new()
		wn.position = wheel_spots[i]
		_car_mount.add_child(wn)
		CarMeshBuilder.build_wheel_visual(wn, 0.34 if i < 2 else 0.35, 0.28 if i < 2 else 0.32, rim_col, false)

	if _turntable_ring_mat:
		_turntable_ring_mat.albedo_color = livery["primary"]
		_turntable_ring_mat.emission = livery["primary"]


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.build_theme()
	_ui_layer.add_child(root)

	# --- TOP HEADER BAR ---
	var header := PanelContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 20
	header.offset_right = -20
	header.offset_top = 14
	header.offset_bottom = 84
	header.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.BORDER_SUBTLE, 14, 1, 22, 10))
	root.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	header.add_child(hbox)

	var brand_col := VBoxContainer.new()
	brand_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(brand_col)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 26)
	_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	brand_col.add_child(_title_lbl)

	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 18)
	brand_col.add_child(sub_row)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.add_theme_font_size_override("font_size", 12)
	_subtitle_lbl.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	sub_row.add_child(_subtitle_lbl)

	_career_lbl = Label.new()
	_career_lbl.add_theme_font_size_override("font_size", 12)
	_career_lbl.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
	sub_row.add_child(_career_lbl)

	_controls_btn = Button.new()
	_controls_btn.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		_controls_modal.visible = true
	)
	hbox.add_child(_controls_btn)

	_settings_btn = Button.new()
	_settings_btn.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		_settings_modal.visible = true
	)
	hbox.add_child(_settings_btn)

	_lang_btn = Button.new()
	_lang_btn.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		GameState.toggle_language()
	)
	hbox.add_child(_lang_btn)

	# --- LEFT PANEL: Mode + Circuit + Options + Start CTA ---
	var left_panel := PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_left = 20
	left_panel.offset_right = 472
	left_panel.offset_top = 98
	left_panel.offset_bottom = -20
	left_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.BORDER_SUBTLE, 14, 1, 18, 14))
	root.add_child(left_panel)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left_panel.add_child(lv)

	# Mode Section
	_lbl_mode_hdr = _make_section_header(lv)
	var mode_grid := GridContainer.new()
	mode_grid.columns = 2
	mode_grid.add_theme_constant_override("h_separation", 8)
	mode_grid.add_theme_constant_override("v_separation", 8)
	lv.add_child(mode_grid)

	for m_id in ["grand_prix", "quick_race", "time_trial", "free_roam"]:
		var mb := Button.new()
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.mode = m_id
			_refresh_all()
		)
		mode_grid.add_child(mb)
		_mode_buttons[m_id] = mb

	_mode_desc_lbl = Label.new()
	_mode_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc_lbl.add_theme_font_size_override("font_size", 13)
	_mode_desc_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	lv.add_child(_mode_desc_lbl)

	lv.add_child(HSeparator.new())

	# Circuit Selector Section
	_lbl_track_hdr = _make_section_header(lv)
	var tr_row := HBoxContainer.new()
	tr_row.add_theme_constant_override("separation", 10)
	lv.add_child(tr_row)

	var tr_list := VBoxContainer.new()
	tr_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr_list.add_theme_constant_override("separation", 6)
	tr_row.add_child(tr_list)

	var tracks := TrackCatalog.get_tracks()
	for i in range(tracks.size()):
		var tb := Button.new()
		tb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var idx_copy := i
		tb.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.selected_track_idx = idx_copy
			GameState.save_data()
			_refresh_all()
		)
		tr_list.add_child(tb)
		_track_buttons.append(tb)

	# Circuit Minimap Preview Box
	var map_wrap := PanelContainer.new()
	map_wrap.custom_minimum_size = Vector2(138, 134)
	map_wrap.add_theme_stylebox_override("panel", UITheme.make_panel_box(Color(0.04, 0.06, 0.11, 0.92), UITheme.BORDER_SUBTLE, 10, 1, 6, 6))
	tr_row.add_child(map_wrap)

	_track_minimap = _MenuDrawControl.new()
	_track_minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_track_minimap.draw_cb = _draw_track_preview
	map_wrap.add_child(_track_minimap)

	_track_info_lbl = Label.new()
	_track_info_lbl.add_theme_font_size_override("font_size", 13)
	_track_info_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	lv.add_child(_track_info_lbl)

	_track_record_lbl = Label.new()
	_track_record_lbl.add_theme_font_size_override("font_size", 14)
	_track_record_lbl.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
	lv.add_child(_track_record_lbl)

	lv.add_child(HSeparator.new())

	# Difficulty & Laps Row
	var opt_box := VBoxContainer.new()
	opt_box.add_theme_constant_override("separation", 8)
	lv.add_child(opt_box)
	_options_row = opt_box

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 6)
	opt_box.add_child(diff_row)
	_lbl_diff = Label.new()
	_lbl_diff.custom_minimum_size = Vector2(88, 0)
	_lbl_diff.add_theme_font_size_override("font_size", 14)
	diff_row.add_child(_lbl_diff)
	for d in range(3):
		var db := Button.new()
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var d_copy := d
		db.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.difficulty = d_copy
			GameState.save_data()
			_refresh_all()
		)
		diff_row.add_child(db)
		_diff_buttons.append(db)

	var lap_row := HBoxContainer.new()
	lap_row.add_theme_constant_override("separation", 6)
	opt_box.add_child(lap_row)
	_lbl_laps = Label.new()
	_lbl_laps.custom_minimum_size = Vector2(88, 0)
	_lbl_laps.add_theme_font_size_override("font_size", 14)
	lap_row.add_child(_lbl_laps)
	for lap_opt: int in [2, 3, 5]:
		var lb := Button.new()
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l_copy: int = lap_opt
		lb.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.lap_count = l_copy
			GameState.save_data()
			_refresh_all()
		)
		lap_row.add_child(lb)
		_lap_buttons.append(lb)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)

	# Big Primary START RACE Button
	_start_btn = Button.new()
	_start_btn.custom_minimum_size = Vector2(0, 54)
	UITheme.style_primary_button(_start_btn, UITheme.ACCENT_RED)
	_start_btn.pressed.connect(_on_start_pressed)
	lv.add_child(_start_btn)

	# --- BOTTOM-RIGHT GARAGE SHOWROOM BAR (keeps 3D car fully visible above it!) ---
	var garage_panel := PanelContainer.new()
	garage_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	garage_panel.offset_left = -772
	garage_panel.offset_right = -20
	garage_panel.offset_top = -248
	garage_panel.offset_bottom = -20
	garage_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.BORDER_SUBTLE, 14, 1, 18, 14))
	root.add_child(garage_panel)

	var gh := HBoxContainer.new()
	gh.add_theme_constant_override("separation", 18)
	garage_panel.add_child(gh)

	# Left half of garage card: Car Picker + Livery Swatches
	var g_left := VBoxContainer.new()
	g_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_left.add_theme_constant_override("separation", 8)
	gh.add_child(g_left)

	_lbl_car_hdr = _make_section_header(g_left)
	var car_grid := GridContainer.new()
	car_grid.columns = 2
	car_grid.add_theme_constant_override("h_separation", 8)
	car_grid.add_theme_constant_override("v_separation", 6)
	g_left.add_child(car_grid)

	var cars := CarCatalog.get_cars()
	for i in range(cars.size()):
		var cb := Button.new()
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var c_copy := i
		cb.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.selected_car_idx = c_copy
			GameState.save_data()
			_rebuild_showroom_car()
			_refresh_all()
		)
		car_grid.add_child(cb)
		_car_buttons.append(cb)

	_lbl_livery_hdr = _make_section_header(g_left)
	var liv_row := HBoxContainer.new()
	liv_row.add_theme_constant_override("separation", 8)
	g_left.add_child(liv_row)

	var liveries := CarCatalog.get_liveries()
	for i in range(liveries.size()):
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(44, 28)
		var l_copy := i
		sb.pressed.connect(func():
			AudioManager.play_sfx("ui_click")
			GameState.selected_livery_idx = l_copy
			GameState.save_data()
			_rebuild_showroom_car()
			_refresh_all()
		)
		liv_row.add_child(sb)
		_livery_buttons.append(sb)

	# Right half of garage card: Selected Car Info & 4 Animated Stat Bars
	var g_right := VBoxContainer.new()
	g_right.custom_minimum_size = Vector2(315, 0)
	g_right.add_theme_constant_override("separation", 5)
	gh.add_child(g_right)

	_car_title_lbl = Label.new()
	_car_title_lbl.add_theme_font_size_override("font_size", 22)
	_car_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	g_right.add_child(_car_title_lbl)

	_car_class_lbl = Label.new()
	_car_class_lbl.add_theme_font_size_override("font_size", 12)
	_car_class_lbl.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	g_right.add_child(_car_class_lbl)

	_car_desc_lbl = Label.new()
	_car_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_car_desc_lbl.add_theme_font_size_override("font_size", 12)
	_car_desc_lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	g_right.add_child(_car_desc_lbl)

	for sk in ["speed", "accel", "handling", "drift"]:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 8)
		g_right.add_child(srow)
		var sl := Label.new()
		sl.custom_minimum_size = Vector2(74, 0)
		sl.add_theme_font_size_override("font_size", 12)
		srow.add_child(sl)
		_stat_labels[sk] = sl

		var pb := ProgressBar.new()
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.custom_minimum_size = Vector2(0, 14)
		pb.min_value = 0.0
		pb.max_value = 100.0
		pb.show_percentage = false
		srow.add_child(pb)
		_stat_bars[sk] = pb

	# Modals
	_settings_modal = _build_settings_modal(root)
	_controls_modal = _build_controls_modal(root)


func _make_section_header(parent: Control) -> Label:
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	parent.add_child(lbl)
	return lbl


func _build_settings_modal(parent: Control) -> Control:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.07, 0.78)
	dim.visible = false
	parent.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(460, 0)
	card.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.ACCENT_CYAN, 16, 2, 26, 22))
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.name = "SettingsBox"
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	_add_volume_row(vb, "set_master", "master_volume")
	_add_volume_row(vb, "set_sfx", "sfx_volume")
	_add_volume_row(vb, "set_music", "music_volume")
	_add_toggle_row(vb, "set_auto_trans", "auto_transmission")
	_add_toggle_row(vb, "set_stability", "stability_assist")
	_add_toggle_row(vb, "set_controls_hud", "show_controls")

	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	UITheme.style_primary_button(close_btn, UITheme.ACCENT_RED)
	close_btn.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		dim.visible = false
	)
	vb.add_child(close_btn)
	return dim


func _add_volume_row(parent: Control, i18n_key: String, setting_key: String) -> void:
	var hb := HBoxContainer.new()
	hb.name = "Row_" + setting_key
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.name = "Lbl"
	lbl.set_meta("i18n", i18n_key)
	lbl.custom_minimum_size = Vector2(180, 0)
	hb.add_child(lbl)
	var sl := HSlider.new()
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = float(GameState.settings.get(setting_key, 0.8))
	sl.value_changed.connect(func(v: float):
		GameState.settings[setting_key] = v
		GameState.save_data()
		GameState.settings_changed.emit()
	)
	hb.add_child(sl)


func _add_toggle_row(parent: Control, i18n_key: String, setting_key: String) -> void:
	var cb := CheckButton.new()
	cb.name = "Toggle_" + setting_key
	cb.set_meta("i18n", i18n_key)
	cb.button_pressed = bool(GameState.settings.get(setting_key, true))
	cb.toggled.connect(func(val: bool):
		AudioManager.play_sfx("ui_click")
		GameState.settings[setting_key] = val
		GameState.save_data()
		GameState.settings_changed.emit()
	)
	parent.add_child(cb)


func _build_controls_modal(parent: Control) -> Control:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.07, 0.78)
	dim.visible = false
	parent.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 0)
	card.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.ACCENT_GOLD, 16, 2, 28, 24))
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.name = "CtrlBox"
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
	vb.add_child(title)
	vb.add_child(HSeparator.new())

	var body := Label.new()
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 15)
	vb.add_child(body)

	var close_btn := Button.new()
	close_btn.name = "CloseBtn"
	UITheme.style_primary_button(close_btn, UITheme.ACCENT_RED)
	close_btn.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		dim.visible = false
	)
	vb.add_child(close_btn)
	return dim


func _refresh_all() -> void:
	_title_lbl.text = GameState.t("game_title")
	_subtitle_lbl.text = GameState.t("game_subtitle")
	_career_lbl.text = GameState.t("career_stats") % [
		int(GameState.career.get("races_finished", 0)),
		int(GameState.career.get("wins", 0)),
		int(GameState.career.get("gp_titles", 0))
	]
	_controls_btn.text = GameState.t("btn_controls")
	_settings_btn.text = GameState.t("btn_settings")
	_lang_btn.text = GameState.t("btn_lang")
	_lbl_mode_hdr.text = GameState.t("select_mode")
	_lbl_track_hdr.text = GameState.t("select_track")
	_lbl_car_hdr.text = GameState.t("select_car")
	_lbl_livery_hdr.text = GameState.t("select_livery")
	_lbl_diff.text = GameState.t("difficulty")
	_lbl_laps.text = GameState.t("laps")
	_start_btn.text = GameState.t("btn_start_race")

	# Modes
	for m_id in _mode_buttons:
		var b: Button = _mode_buttons[m_id]
		b.text = GameState.t("mode_" + m_id)
		UITheme.style_selected_chip(b, GameState.mode == m_id)
	_mode_desc_lbl.text = GameState.t("mode_" + GameState.mode + "_desc")

	# Tracks + Preview Minimap
	var tracks := TrackCatalog.get_tracks()
	for i in range(tracks.size()):
		var tr: Dictionary = tracks[i]
		var rec := GameState.get_track_record(str(tr["id"]))
		var medal := str(rec.get("medal", "none"))
		var medal_icon := "🥇 " if medal == "gold" else ("🥈 " if medal == "silver" else ("🥉 " if medal == "bronze" else ""))
		_track_buttons[i].text = medal_icon + GameState.get_localized_field(tr, "name")
		_track_buttons[i].disabled = (GameState.mode == "grand_prix")
		UITheme.style_selected_chip(_track_buttons[i], GameState.selected_track_idx == i)

	var sel_tr := TrackCatalog.get_track(GameState.selected_track_idx)
	_track_info_lbl.text = "%s  ·  %s" % [
		GameState.get_localized_field(sel_tr, "subtitle"),
		GameState.get_localized_field(sel_tr, "difficulty")
	]
	var sel_rec := GameState.get_track_record(str(sel_tr["id"]))
	var bl := float(sel_rec.get("best_lap", 0.0))
	var med_str := GameState.t("medal_" + str(sel_rec.get("medal", "none")))
	_track_record_lbl.text = "%s: %s   |   %s" % [GameState.t("best_lap"), GameState.format_time(bl), med_str]

	var sp := TrackSpline.new()
	sp.build_from_control_points(sel_tr["control_points"], float(sel_tr["road_width"]), float(sel_tr["bank_strength"]), 5.0)
	_preview_spline_pts = sp.get_minimap_points()
	_track_minimap.queue_redraw()

	# Difficulty & Laps
	for d in range(3):
		_diff_buttons[d].text = GameState.t("diff_%d" % d)
		UITheme.style_selected_chip(_diff_buttons[d], GameState.difficulty == d)
	var lap_vals := [2, 3, 5]
	for idx in range(lap_vals.size()):
		_lap_buttons[idx].text = "%d %s" % [lap_vals[idx], GameState.t("laps_unit")]
		UITheme.style_selected_chip(_lap_buttons[idx], GameState.lap_count == lap_vals[idx])
	_options_row.visible = (GameState.mode == "quick_race" or GameState.mode == "grand_prix")
	_lap_buttons[0].get_parent().visible = (GameState.mode == "quick_race")

	# Cars & Liveries
	var cars := CarCatalog.get_cars()
	for i in range(cars.size()):
		_car_buttons[i].text = GameState.get_localized_field(cars[i], "name")
		UITheme.style_selected_chip(_car_buttons[i], GameState.selected_car_idx == i)

	var liveries := CarCatalog.get_liveries()
	for i in range(liveries.size()):
		var col: Color = liveries[i]["primary"]
		var is_sel := (GameState.selected_livery_idx == i)
		_livery_buttons[i].add_theme_stylebox_override("normal", UITheme.make_panel_box(col, Color.WHITE if is_sel else Color(0, 0, 0, 0.4), 6, 3 if is_sel else 1, 2, 2))
		_livery_buttons[i].add_theme_stylebox_override("hover", UITheme.make_panel_box(col.lightened(0.15), Color.WHITE, 6, 2, 2, 2))

	var sel_car := CarCatalog.get_car(GameState.selected_car_idx)
	_car_title_lbl.text = GameState.get_localized_field(sel_car, "name")
	_car_class_lbl.text = GameState.get_localized_field(sel_car, "class")
	_car_desc_lbl.text = GameState.get_localized_field(sel_car, "desc")
	var stats: Dictionary = sel_car["stats"]
	for sk in ["speed", "accel", "handling", "drift"]:
		_stat_labels[sk].text = GameState.t("stat_" + sk)
		_stat_bars[sk].value = float(stats[sk])

	# Refresh modal texts
	var sbox := _settings_modal.find_child("SettingsBox", true, false)
	if sbox:
		sbox.get_node("Title").text = GameState.t("settings_title")
		sbox.get_node("CloseBtn").text = GameState.t("btn_close")
		for child in sbox.get_children():
			if child.has_meta("i18n"):
				child.text = GameState.t(str(child.get_meta("i18n")))
			elif child.has_node("Lbl"):
				var l := child.get_node("Lbl")
				l.text = GameState.t(str(l.get_meta("i18n")))

	var cbox := _controls_modal.find_child("CtrlBox", true, false)
	if cbox:
		cbox.get_node("Title").text = GameState.t("ctrl_title")
		cbox.get_node("Body").text = GameState.t("ctrl_body")
		cbox.get_node("CloseBtn").text = GameState.t("btn_close")


func _draw_track_preview(ctrl: Control) -> void:
	if _preview_spline_pts.size() < 3:
		return
	var sz := ctrl.size
	var pad := 12.0
	var inner := sz - Vector2(pad * 2.0, pad * 2.0)
	var pts := PackedVector2Array()
	pts.resize(_preview_spline_pts.size() + 1)
	for i in range(_preview_spline_pts.size()):
		pts[i] = Vector2(pad, pad) + _preview_spline_pts[i] * inner
	pts[_preview_spline_pts.size()] = pts[0]
	ctrl.draw_polyline(pts, Color(0.0, 0.88, 1.0, 0.28), 8.0, true)
	ctrl.draw_polyline(pts, UITheme.ACCENT_CYAN, 3.2, true)
	ctrl.draw_circle(pts[0], 4.5, UITheme.ACCENT_GOLD)


func _on_start_pressed() -> void:
	AudioManager.play_sfx("ui_confirm")
	if GameState.mode == "grand_prix":
		GameState.start_grand_prix()
	else:
		GameState.gp_active = false
	GameState.save_data()
	get_tree().change_scene_to_file("res://scenes/race_scene.tscn")


class _MenuDrawControl extends Control:
	var draw_cb: Callable
	func _draw() -> void:
		if draw_cb.is_valid():
			draw_cb.call(self)

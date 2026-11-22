class_name RaceHUD
extends CanvasLayer

## Complete Live Motorsport HUD with custom vector Tachometer/Speedometer,
## Live Circuit Minimap, F1 Starting Lights, Drift Combo, Wrong-Way Alert, and Banners.

var player_car: RaceCar
var all_cars: Array[RaceCar] = []
var spline: TrackSpline
var track_data: Dictionary = {}
var total_laps: int = 3
var mode: String = "quick_race"

var _root: Control
var _pos_value: Label
var _pos_sub: Label
var _lap_value: Label
var _track_label: Label
var _time_cur: Label
var _time_best: Label
var _time_delta: Label
var _banner_label: Label
var _banner_timer: float = 0.0
var _wrong_way_panel: PanelContainer
var _drift_panel: PanelContainer
var _drift_label: Label
var _drift_tier_label: Label
var _drift_bar_canvas: Control
var _controls_bar: Label
var _lights_panel: PanelContainer
var _lights_canvas: Control
var _lights_lit_count: int = 0
var _lights_is_green: bool = false
var _gauge_canvas: Control
var _minimap_canvas: Control
var _speedlines_canvas: Control

var _minimap_pts: PackedVector2Array = PackedVector2Array()
var _wrong_way: bool = false
var _elapsed_race_time: float = 0.0
var _camera_label_text: String = ""


func _ready() -> void:
	layer = 10
	_build_ui()
	GameState.language_changed.connect(_on_language_changed)


func _exit_tree() -> void:
	if GameState.language_changed.is_connected(_on_language_changed):
		GameState.language_changed.disconnect(_on_language_changed)
	for c in [_lights_canvas, _gauge_canvas, _minimap_canvas, _speedlines_canvas, _drift_bar_canvas]:
		if c != null and c is _HUDDrawOverlay:
			(c as _HUDDrawOverlay).draw_cb = Callable()


func _on_language_changed(_lang: String) -> void:
	_refresh_labels()
	if player_car != null:
		_refresh_dynamic_texts()
	if _gauge_canvas != null:
		_gauge_canvas.queue_redraw()


func setup(p_player: RaceCar, p_all_cars: Array[RaceCar], p_spline: TrackSpline, p_track: Dictionary, p_laps: int, p_mode: String) -> void:
	player_car = p_player
	all_cars = p_all_cars
	spline = p_spline
	track_data = p_track
	total_laps = p_laps
	mode = p_mode
	_minimap_pts = spline.get_minimap_points()
	_refresh_labels()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.build_theme()
	add_child(_root)

	# Fullscreen subtle nitro/high-speed edge vignette overlay
	_speedlines_canvas = _HUDDrawOverlay.new()
	_speedlines_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_speedlines_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speedlines_canvas.draw_cb = _draw_speed_effect
	_root.add_child(_speedlines_canvas)

	# --- TOP-LEFT: Position & Lap Card ---
	var tl_panel := PanelContainer.new()
	tl_panel.position = Vector2(22, 18)
	tl_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.BORDER_SUBTLE, 12, 1, 18, 12))
	_root.add_child(tl_panel)

	var tl_box := HBoxContainer.new()
	tl_box.add_theme_constant_override("separation", 22)
	tl_panel.add_child(tl_box)

	var pos_col := VBoxContainer.new()
	tl_box.add_child(pos_col)
	_pos_sub = Label.new()
	_pos_sub.add_theme_font_size_override("font_size", 12)
	_pos_sub.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	pos_col.add_child(_pos_sub)
	_pos_value = Label.new()
	_pos_value.add_theme_font_size_override("font_size", 34)
	_pos_value.add_theme_color_override("font_color", Color.WHITE)
	pos_col.add_child(_pos_value)

	var sep := VSeparator.new()
	tl_box.add_child(sep)

	var lap_col := VBoxContainer.new()
	tl_box.add_child(lap_col)
	_track_label = Label.new()
	_track_label.add_theme_font_size_override("font_size", 13)
	_track_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	lap_col.add_child(_track_label)
	_lap_value = Label.new()
	_lap_value.add_theme_font_size_override("font_size", 28)
	_lap_value.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
	lap_col.add_child(_lap_value)

	# --- TOP-RIGHT: Timing Card ---
	var tr_panel := PanelContainer.new()
	tr_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_panel.offset_left = -265
	tr_panel.offset_right = -22
	tr_panel.offset_top = 18
	tr_panel.offset_bottom = 122
	tr_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.BORDER_SUBTLE, 12, 1, 16, 10))
	_root.add_child(tr_panel)

	var tr_box := VBoxContainer.new()
	tr_box.add_theme_constant_override("separation", 4)
	tr_panel.add_child(tr_box)

	_time_cur = Label.new()
	_time_cur.add_theme_font_size_override("font_size", 22)
	_time_cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_box.add_child(_time_cur)

	_time_best = Label.new()
	_time_best.add_theme_font_size_override("font_size", 15)
	_time_best.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	_time_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_box.add_child(_time_best)

	_time_delta = Label.new()
	_time_delta.add_theme_font_size_override("font_size", 14)
	_time_delta.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	_time_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr_box.add_child(_time_delta)

	# --- TOP-CENTER: Circular F1 Starting Lights Overlay ---
	_lights_panel = PanelContainer.new()
	_lights_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lights_panel.offset_left = -175
	_lights_panel.offset_right = 175
	_lights_panel.offset_top = 22
	_lights_panel.offset_bottom = 86
	_lights_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(Color(0.04, 0.05, 0.08, 0.92), UITheme.BORDER_SUBTLE, 14, 2, 16, 8))
	_root.add_child(_lights_panel)

	_lights_canvas = _HUDDrawOverlay.new()
	_lights_canvas.custom_minimum_size = Vector2(310, 48)
	_lights_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lights_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lights_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lights_canvas.draw_cb = _draw_countdown_lights
	_lights_panel.add_child(_lights_canvas)

	# --- CENTER-UPPER: Event Banner (GO / FINAL LAP / PERFECT START / NEW BEST) ---
	_banner_label = Label.new()
	_banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_label.offset_left = -320
	_banner_label.offset_right = 320
	_banner_label.offset_top = 112
	_banner_label.offset_bottom = 178
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 42)
	_banner_label.add_theme_color_override("font_color", Color.WHITE)
	_banner_label.add_theme_constant_override("outline_size", 6)
	_banner_label.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.12, 0.9))
	_banner_label.visible = false
	_root.add_child(_banner_label)

	# --- WRONG WAY Flashing Warning ---
	_wrong_way_panel = PanelContainer.new()
	_wrong_way_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_wrong_way_panel.offset_left = -210
	_wrong_way_panel.offset_right = 210
	_wrong_way_panel.offset_top = 185
	_wrong_way_panel.offset_bottom = 236
	_wrong_way_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(Color(0.86, 0.10, 0.16, 0.92), Color(1.0, 0.85, 0.25), 10, 2, 16, 8))
	_wrong_way_panel.visible = false
	_root.add_child(_wrong_way_panel)

	var ww_lbl := Label.new()
	ww_lbl.name = "WWLabel"
	ww_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ww_lbl.add_theme_font_size_override("font_size", 22)
	ww_lbl.add_theme_color_override("font_color", Color.WHITE)
	_wrong_way_panel.add_child(ww_lbl)

	# --- DRIFT COMBO & 3-TIER CHARGE GAUGE Popup ---
	_drift_panel = PanelContainer.new()
	_drift_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_drift_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_drift_panel.offset_left = -165
	_drift_panel.offset_right = 165
	_drift_panel.offset_top = -64
	_drift_panel.offset_bottom = -64
	_drift_panel.add_theme_stylebox_override("panel", UITheme.make_panel_box(Color(0.06, 0.09, 0.17, 0.90), UITheme.ACCENT_CYAN, 10, 2, 14, 8))
	_drift_panel.visible = false
	_root.add_child(_drift_panel)

	var drift_vbox := VBoxContainer.new()
	drift_vbox.add_theme_constant_override("separation", 4)
	_drift_panel.add_child(drift_vbox)

	_drift_label = Label.new()
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_label.add_theme_font_size_override("font_size", 22)
	_drift_label.add_theme_color_override("font_color", Color.WHITE)
	drift_vbox.add_child(_drift_label)

	_drift_bar_canvas = _HUDDrawOverlay.new()
	_drift_bar_canvas.custom_minimum_size = Vector2(280, 14)
	_drift_bar_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drift_bar_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drift_bar_canvas.draw_cb = _draw_drift_charge_bar
	drift_vbox.add_child(_drift_bar_canvas)

	_drift_tier_label = Label.new()
	_drift_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_tier_label.add_theme_font_size_override("font_size", 13)
	_drift_tier_label.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	drift_vbox.add_child(_drift_tier_label)

	# --- BOTTOM-LEFT: Custom Vector Live Minimap ---
	_minimap_canvas = _HUDDrawOverlay.new()
	_minimap_canvas.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_minimap_canvas.offset_left = 22
	_minimap_canvas.offset_right = 202
	_minimap_canvas.offset_top = -206
	_minimap_canvas.offset_bottom = -26
	_minimap_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_canvas.draw_cb = _draw_minimap
	_root.add_child(_minimap_canvas)

	# --- BOTTOM-RIGHT: Custom Vector Speedometer, Tachometer & Nitro Cluster ---
	_gauge_canvas = _HUDDrawOverlay.new()
	_gauge_canvas.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_gauge_canvas.offset_left = -295
	_gauge_canvas.offset_right = -20
	_gauge_canvas.offset_top = -262
	_gauge_canvas.offset_bottom = -22
	_gauge_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge_canvas.draw_cb = _draw_tachometer
	_root.add_child(_gauge_canvas)

	# --- BOTTOM-CENTER: Compact Controls Bar ---
	_controls_bar = Label.new()
	_controls_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_controls_bar.offset_top = -30
	_controls_bar.offset_bottom = -8
	_controls_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_bar.add_theme_font_size_override("font_size", 13)
	_controls_bar.add_theme_color_override("font_color", Color(0.84, 0.88, 0.95, 0.85))
	_controls_bar.add_theme_constant_override("outline_size", 3)
	_controls_bar.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_root.add_child(_controls_bar)


func _refresh_labels() -> void:
	_pos_sub.text = GameState.t("hud_pos")
	if not track_data.is_empty():
		_track_label.text = GameState.get_localized_field(track_data, "name")
	_wrong_way_panel.get_node("WWLabel").text = GameState.t("hud_wrong_way")
	_controls_bar.text = GameState.t("hud_controls_bar")
	_controls_bar.visible = bool(GameState.settings.get("show_controls", true))


func set_countdown_lights(lit_count: int, is_green: bool, show_panel: bool) -> void:
	_lights_panel.visible = show_panel
	_lights_lit_count = lit_count
	_lights_is_green = is_green
	if _lights_canvas != null:
		_lights_canvas.queue_redraw()


func _draw_countdown_lights(ctrl: Control) -> void:
	var sz := ctrl.size
	var cy := sz.y * 0.5
	var spacing := minf(58.0, (sz.x - 40.0) / 4.0)
	var start_x := sz.x * 0.5 - spacing * 2.0
	for i in range(5):
		var c := Vector2(start_x + float(i) * spacing, cy)
		var lit := _lights_is_green or i < _lights_lit_count
		# Metallic outer bezel ring + recessed housing
		ctrl.draw_circle(c, 20.0, Color(0.12, 0.14, 0.20, 0.98))
		ctrl.draw_arc(c, 20.0, 0.0, TAU, 32, Color(0.32, 0.38, 0.50, 0.85), 1.8, true)
		ctrl.draw_circle(c, 16.5, Color(0.05, 0.04, 0.06, 1.0))
		if lit:
			var main_col := Color(0.10, 0.96, 0.36) if _lights_is_green else Color(0.98, 0.06, 0.08)
			var halo_col := Color(main_col.r, main_col.g, main_col.b, 0.26)
			ctrl.draw_circle(c, 22.5, halo_col)
			ctrl.draw_circle(c, 15.0, main_col)
			# Crisp top-left lens specular highlight
			ctrl.draw_circle(c + Vector2(-4.5, -4.5), 4.2, Color(1.0, 0.96, 0.96, 0.52))
		else:
			ctrl.draw_circle(c, 15.0, Color(0.16, 0.04, 0.05, 1.0))
			ctrl.draw_arc(c, 15.0, 0.0, TAU, 28, Color(0.28, 0.09, 0.11, 0.6), 1.2, true)


func show_banner(text: String, col: Color = Color.WHITE, duration: float = 2.0) -> void:
	_banner_label.text = text
	_banner_label.add_theme_color_override("font_color", col)
	_banner_label.visible = true
	_banner_timer = duration


func set_wrong_way(val: bool) -> void:
	_wrong_way = val


func set_camera_name(cam_mode: int) -> void:
	_camera_label_text = GameState.t("hud_cam_%d" % cam_mode)
	show_banner(_camera_label_text, UITheme.ACCENT_CYAN, 1.1)


func update_hud(delta: float, race_time: float) -> void:
	_elapsed_race_time = race_time
	if player_car == null:
		return

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_label.visible = false

	# Flashing Wrong-Way indicator
	if _wrong_way:
		_wrong_way_panel.visible = fmod(Time.get_ticks_msec() * 0.004, 1.0) < 0.72
	else:
		_wrong_way_panel.visible = false

	_refresh_dynamic_texts()

	_controls_bar.visible = bool(GameState.settings.get("show_controls", true))

	# Trigger custom canvas redraws
	_gauge_canvas.queue_redraw()
	_minimap_canvas.queue_redraw()
	_speedlines_canvas.queue_redraw()
	if _drift_bar_canvas != null and _drift_panel.visible:
		_drift_bar_canvas.queue_redraw()


func _refresh_dynamic_texts() -> void:
	if player_car == null:
		return
	# Position & Lap display
	if mode == "time_trial" or mode == "free_roam":
		_pos_value.text = GameState.t("hud_solo")
	else:
		_pos_value.text = "%d / %d" % [player_car.race_rank, maxi(1, all_cars.size())]

	if mode == "free_roam":
		_lap_value.text = "%s %d" % [GameState.t("hud_lap"), player_car.current_lap]
	else:
		_lap_value.text = "%s %d / %d" % [GameState.t("hud_lap"), mini(player_car.current_lap, total_laps), total_laps]

	# Timers (00:00.00 for active lap & total race timer; --:--.-- for unrecorded best)
	_time_cur.text = "%s  %s" % [GameState.t("hud_time"), GameState.format_time(player_car.current_lap_time, true)]
	var saved_best := float(GameState.get_track_record(str(track_data.get("id", ""))).get("best_lap", 0.0))
	var display_best := player_car.best_lap_time
	if display_best <= 0.0 or (saved_best > 0.0 and saved_best < display_best):
		display_best = saved_best
	_time_best.text = "%s  %s" % [GameState.t("hud_best"), GameState.format_time(display_best, false)]
	_time_delta.text = "%s  %s" % [GameState.t("hud_total"), GameState.format_time(_elapsed_race_time, true)]

	# Drift Combo & 3-Tier Exit Boost Charge Popup
	var show_drift := player_car.arcade_drift_active or player_car.is_drifting or player_car.current_drift_score >= 5.0
	if show_drift:
		_drift_panel.visible = true
		var tier := player_car.drift_boost_tier
		var tier_col := UITheme.ACCENT_CYAN
		if tier >= 3:
			tier_col = Color(0.88, 0.34, 1.0)
		elif tier == 2:
			tier_col = UITheme.ACCENT_GOLD
		elif tier == 1:
			tier_col = UITheme.ACCENT_CYAN
		else:
			tier_col = Color(0.68, 0.80, 0.94)

		_drift_label.text = "%s  +%d  (%.0f°)" % [
			GameState.t("hud_drift"),
			int(round(player_car.current_drift_score)),
			player_car.drift_angle_deg
		]
		_drift_label.add_theme_color_override("font_color", tier_col if tier >= 1 else Color.WHITE)

		if tier >= 1:
			_drift_tier_label.text = GameState.t("hud_drift_lv%d" % clampi(tier, 1, 3))
			_drift_tier_label.add_theme_color_override("font_color", tier_col)
			_drift_tier_label.visible = true
		elif player_car.arcade_drift_active:
			_drift_tier_label.text = GameState.t("hud_drift_lv1")
			_drift_tier_label.add_theme_color_override("font_color", Color(0.55, 0.68, 0.84))
			_drift_tier_label.visible = true
		else:
			_drift_tier_label.visible = false

		_drift_bar_canvas.visible = player_car.arcade_drift_active or player_car.drift_charge_progress > 0.01
		var sb := _drift_panel.get_theme_stylebox("panel")
		if sb is StyleBoxFlat:
			(sb as StyleBoxFlat).border_color = tier_col
	else:
		_drift_panel.visible = false


func _draw_minimap(ctrl: Control) -> void:
	var sz := ctrl.size
	var rect := Rect2(Vector2.ZERO, sz)
	ctrl.draw_rect(rect, Color(0.04, 0.06, 0.10, 0.78), true)
	ctrl.draw_rect(rect, UITheme.BORDER_SUBTLE, false, 1.5)

	if _minimap_pts.size() < 3 or spline == null:
		return

	var pad := 16.0
	var inner := sz - Vector2(pad * 2.0, pad * 2.0)
	var screen_pts := PackedVector2Array()
	screen_pts.resize(_minimap_pts.size() + 1)
	for i in range(_minimap_pts.size()):
		screen_pts[i] = Vector2(pad, pad) + _minimap_pts[i] * inner
	screen_pts[_minimap_pts.size()] = screen_pts[0]

	# Circuit shadow + crisp track outline
	ctrl.draw_polyline(screen_pts, Color(0.0, 0.0, 0.0, 0.65), 7.5, true)
	ctrl.draw_polyline(screen_pts, Color(0.76, 0.82, 0.92, 0.88), 3.6, true)

	# Start/Finish white dot
	ctrl.draw_circle(screen_pts[0], 4.5, UITheme.ACCENT_GOLD)

	# Rival dots
	for car in all_cars:
		if not is_instance_valid(car) or car == player_car:
			continue
		var mp := Vector2(pad, pad) + spline.world_to_minimap(car.global_position) * inner
		ctrl.draw_circle(mp, 4.2, Color(1.0, 0.36, 0.42))

	# Player arrow / highlighted dot
	if player_car != null and is_instance_valid(player_car):
		var pp := Vector2(pad, pad) + spline.world_to_minimap(player_car.global_position) * inner
		ctrl.draw_circle(pp, 7.0, Color(0.0, 0.88, 1.0, 0.35))
		ctrl.draw_circle(pp, 4.8, UITheme.ACCENT_CYAN)
		ctrl.draw_circle(pp, 2.0, Color.WHITE)


func _draw_tachometer(ctrl: Control) -> void:
	if player_car == null:
		return
	var font := UITheme.get_font()
	var sz := ctrl.size
	var center := Vector2(sz.x * 0.54, 98.0)
	var radius := 78.0

	# Backing dial
	ctrl.draw_circle(center, radius + 11.0, Color(0.04, 0.06, 0.11, 0.86))
	ctrl.draw_arc(center, radius + 11.0, 0.0, TAU, 48, UITheme.BORDER_SUBTLE, 1.6, true)

	# Symmetrical 270 deg RPM Arc (135 deg to 405 deg)
	var start_ang := deg_to_rad(135.0)
	var sweep := deg_to_rad(270.0)
	var rpm_ratio := clampf(player_car.motor_rpm / maxf(player_car.max_rpm, 1000.0), 0.0, 1.08)

	# Track background arc
	ctrl.draw_arc(center, radius, start_ang, start_ang + sweep, 44, Color(0.16, 0.20, 0.30, 0.9), 10.5, true)
	# Redline zone marker (82%..100%)
	ctrl.draw_arc(center, radius, start_ang + sweep * 0.82, start_ang + sweep, 14, Color(0.65, 0.10, 0.16, 0.72), 10.5, true)

	# Active RPM arc in 3 progressive clipped segments (0..65% Cyan -> 65..84% Gold -> 84..100% Red)
	var clamped_rpm := clampf(rpm_ratio, 0.0, 1.0)
	if clamped_rpm > 0.005:
		var seg1_end := minf(clamped_rpm, 0.65)
		ctrl.draw_arc(center, radius, start_ang, start_ang + sweep * seg1_end, 28, UITheme.ACCENT_CYAN, 10.5, true)
	if clamped_rpm > 0.65:
		var seg2_end := minf(clamped_rpm, 0.84)
		ctrl.draw_arc(center, radius, start_ang + sweep * 0.65, start_ang + sweep * seg2_end, 14, UITheme.ACCENT_GOLD, 10.5, true)
	if clamped_rpm > 0.84:
		ctrl.draw_arc(center, radius, start_ang + sweep * 0.84, start_ang + sweep * clamped_rpm, 12, UITheme.ACCENT_RED, 10.5, true)

	# Tick marks (9 ticks evenly across 270 deg)
	for i in range(9):
		var a := start_ang + sweep * (float(i) / 8.0)
		var p0 := center + Vector2(cos(a), sin(a)) * (radius - 9.5)
		var p1 := center + Vector2(cos(a), sin(a)) * (radius + 4.5)
		var tc := UITheme.ACCENT_RED if i >= 7 else Color(0.75, 0.82, 0.92, 0.8)
		ctrl.draw_line(p0, p1, tc, 2.0, true)

	# Speed KM/H numeric readout
	var spd_str := "%d" % int(round(player_car.get_speed_kmh()))
	ctrl.draw_string(font, center + Vector2(-54.0, 6.0), spd_str, HORIZONTAL_ALIGNMENT_CENTER, 108.0, 40, Color.WHITE)
	ctrl.draw_string(font, center + Vector2(-42.0, 23.0), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 84.0, 12, UITheme.TEXT_MUTED)

	# Sleek Redline Shift-Light LED Dot directly above the Gear Box
	var shift_pos := center + Vector2(0.0, 32.0)
	if rpm_ratio > 0.88:
		var flash := rpm_ratio > 0.94 and fmod(Time.get_ticks_msec() * 0.012, 1.0) < 0.5
		ctrl.draw_circle(shift_pos, 7.0, Color(1.0, 0.16, 0.24, 0.40))
		ctrl.draw_circle(shift_pos, 3.8, Color.WHITE if flash else UITheme.ACCENT_RED)
	else:
		ctrl.draw_circle(shift_pos, 3.4, Color(0.18, 0.22, 0.32, 0.90))

	# Gear Badge
	var gear_str := "N"
	if player_car.current_gear == -1:
		gear_str = "R"
	elif player_car.current_gear > 0:
		gear_str = str(player_car.current_gear)

	var gear_box := Rect2(center + Vector2(-21.0, 40.0), Vector2(42.0, 30.0))
	ctrl.draw_rect(gear_box, Color(0.11, 0.15, 0.24, 0.96), true)
	ctrl.draw_rect(gear_box, UITheme.ACCENT_RED if rpm_ratio > 0.88 else UITheme.ACCENT_CYAN, false, 2.0)
	ctrl.draw_string(font, gear_box.position + Vector2(0.0, 23.0), gear_str, HORIZONTAL_ALIGNMENT_CENTER, 42.0, 21, Color.WHITE)

	# Auto/Manual mini pill
	var trans_txt := GameState.t("hud_auto") if player_car.automatic_transmission else GameState.t("hud_manual")
	ctrl.draw_string(font, center + Vector2(28.0, 61.0), trans_txt, HORIZONTAL_ALIGNMENT_LEFT, 70.0, 12, UITheme.TEXT_MUTED)

	# High-Contrast Nitro Header Pill cleanly ABOVE the Nitro bar
	var bar_x := 18.0
	var bar_w := sz.x - 28.0
	var header_rect := Rect2(Vector2(bar_x, sz.y - 42.0), Vector2(bar_w, 18.0))
	ctrl.draw_rect(header_rect, Color(0.04, 0.06, 0.11, 0.82), true)
	var nitro_pct := int(round(player_car.nitro))
	var nitro_col := Color(0.25, 0.96, 1.0) if player_car.nitro_active else Color(0.05, 0.68, 0.98)
	ctrl.draw_string(font, header_rect.position + Vector2(6.0, 13.5), GameState.t("hud_nitro"), HORIZONTAL_ALIGNMENT_LEFT, 100.0, 12, UITheme.TEXT_PRIMARY)
	ctrl.draw_string(font, header_rect.position + Vector2(bar_w - 76.0, 13.5), "%d%%" % nitro_pct, HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 12, nitro_col if player_car.nitro_active else UITheme.ACCENT_CYAN)

	# Nitro Fill Bar along bottom of cluster
	var nb_rect := Rect2(Vector2(bar_x, sz.y - 21.0), Vector2(bar_w, 14.0))
	ctrl.draw_rect(nb_rect, Color(0.05, 0.07, 0.13, 0.94), true)
	var fill_w := (nb_rect.size.x - 4.0) * clampf(player_car.nitro / 100.0, 0.0, 1.0)
	if fill_w > 1.0:
		ctrl.draw_rect(Rect2(nb_rect.position + Vector2(2.0, 2.0), Vector2(fill_w, nb_rect.size.y - 4.0)), nitro_col, true)
	ctrl.draw_rect(nb_rect, nitro_col if player_car.nitro_active else UITheme.BORDER_SUBTLE, false, 1.5)


func _draw_drift_charge_bar(ctrl: Control) -> void:
	if player_car == null:
		return
	var sz := ctrl.size
	var gap := 6.0
	var seg_w := (sz.x - gap * 2.0) / 3.0
	var seg_h := sz.y
	var prog := clampf(player_car.drift_charge_progress, 0.0, 3.0)
	var tier_cols := [
		UITheme.ACCENT_CYAN,
		UITheme.ACCENT_GOLD,
		Color(0.88, 0.34, 1.0)
	]

	for i in range(3):
		var x := float(i) * (seg_w + gap)
		var rect := Rect2(Vector2(x, 1.0), Vector2(seg_w, seg_h - 2.0))
		ctrl.draw_rect(rect, Color(0.06, 0.09, 0.16, 0.94), true)
		var fill_frac := clampf(prog - float(i), 0.0, 1.0)
		var col: Color = tier_cols[i]
		if fill_frac > 0.005:
			var fw := (rect.size.x - 2.0) * fill_frac
			ctrl.draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), Vector2(fw, rect.size.y - 2.0)), col, true)
			if fill_frac >= 0.995:
				# Bright top highlight when a tier is fully charged!
				ctrl.draw_rect(Rect2(rect.position + Vector2(1.0, 1.0), Vector2(fw, 3.0)), Color(1.0, 1.0, 1.0, 0.45), true)
		var border_col := col if fill_frac >= 0.995 else Color(0.28, 0.36, 0.50, 0.75)
		ctrl.draw_rect(rect, border_col, false, 1.5)


func _draw_speed_effect(ctrl: Control) -> void:
	if player_car == null:
		return
	var exit_boost := player_car.drift_exit_boost_timer > 0.0
	var boosting := player_car.nitro_active or player_car.boost_pad_timer > 0.0 or player_car.launch_boost_timer > 0.0 or exit_boost
	var spd := player_car.get_speed_kmh()
	if not boosting and spd < 195.0:
		return
	var intensity := 0.62 if exit_boost else (0.55 if boosting else clampf((spd - 195.0) / 110.0, 0.0, 0.35))
	var sz := ctrl.size
	var center := sz * 0.5
	var col := Color(1.0, 1.0, 1.0, intensity * 0.22)
	if exit_boost:
		if player_car.drift_exit_boost_tier >= 3:
			col = Color(0.88, 0.32, 1.0, intensity * 0.52)
		elif player_car.drift_exit_boost_tier == 2:
			col = Color(1.0, 0.78, 0.16, intensity * 0.48)
		else:
			col = Color(0.0, 0.92, 1.0, intensity * 0.44)
	elif boosting:
		col = Color(0.0, 0.90, 1.0, intensity * 0.42)
	var phase := float(Time.get_ticks_msec() % 1000) * 0.015
	for i in range(18):
		var ang := float(i) * TAU / 18.0 + sin(phase + float(i)) * 0.04
		var dir := Vector2(cos(ang), sin(ang))
		var r_outer := maxf(sz.x, sz.y) * 0.62
		var r_inner := r_outer * (0.68 if exit_boost else (0.72 if boosting else 0.82))
		ctrl.draw_line(center + dir * r_inner, center + dir * r_outer, col, 2.8 if exit_boost else (2.4 if boosting else 1.5), true)


class _HUDDrawOverlay extends Control:
	var draw_cb: Callable
	func _draw() -> void:
		if draw_cb.is_valid():
			draw_cb.call(self)

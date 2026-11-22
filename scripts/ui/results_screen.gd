class_name ResultsScreen
extends CanvasLayer

## Post-Race Classification, Medal & New Record Showcase, and Grand Prix Podium Screen.

signal next_round_requested
signal rematch_requested
signal main_menu_requested

var _dim: ColorRect
var _title_lbl: Label
var _subtitle_lbl: Label
var _badges_box: HBoxContainer
var _table_box: VBoxContainer
var _btn_next: Button
var _btn_rematch: Button
var _btn_menu: Button


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.02, 0.03, 0.08, 0.72)
	_dim.theme = UITheme.build_theme()
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(760, 0)
	card.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.ACCENT_GOLD, 16, 2, 30, 24))
	center.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 34)
	_title_lbl.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
	vbox.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_lbl.add_theme_font_size_override("font_size", 16)
	_subtitle_lbl.add_theme_color_override("font_color", UITheme.ACCENT_CYAN)
	vbox.add_child(_subtitle_lbl)

	_badges_box = HBoxContainer.new()
	_badges_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_badges_box.add_theme_constant_override("separation", 14)
	vbox.add_child(_badges_box)

	vbox.add_child(HSeparator.new())

	_table_box = VBoxContainer.new()
	_table_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_table_box)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_btn_next = Button.new()
	UITheme.style_primary_button(_btn_next, UITheme.ACCENT_RED)
	_btn_next.pressed.connect(func():
		AudioManager.play_sfx("ui_confirm")
		next_round_requested.emit()
	)
	btn_row.add_child(_btn_next)

	_btn_rematch = Button.new()
	UITheme.style_primary_button(_btn_rematch, Color(0.06, 0.56, 0.84))
	_btn_rematch.pressed.connect(func():
		AudioManager.play_sfx("ui_confirm")
		rematch_requested.emit()
	)
	btn_row.add_child(_btn_rematch)

	_btn_menu = Button.new()
	_btn_menu.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		main_menu_requested.emit()
	)
	btn_row.add_child(_btn_menu)


func show_results(payload: Dictionary) -> void:
	visible = true
	var results: Array = payload.get("results", []).duplicate()
	var track_data: Dictionary = payload.get("track", {})
	var is_gp: bool = bool(payload.get("is_gp", false))
	var gp_round: int = int(payload.get("gp_round", 0))
	var has_next_gp: bool = bool(payload.get("has_next_gp", false))
	var is_new_record: bool = bool(payload.get("is_new_record", false))
	var medal: String = str(payload.get("medal", "none"))
	var drift_score: int = int(payload.get("drift_score", 0))
	var is_final_podium := is_gp and not has_next_gp

	if is_final_podium:
		results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := int(a.get("total_points", 0))
			var pb := int(b.get("total_points", 0))
			if pa != pb:
				return pa > pb
			return float(a.get("finish_time", 0.0)) < float(b.get("finish_time", 0.0))
		)
		_title_lbl.text = GameState.t("res_gp_complete")
	else:
		_title_lbl.text = GameState.t("res_race_complete")

	var tname := GameState.get_localized_field(track_data, "name")
	if is_gp:
		_subtitle_lbl.text = "%s  ·  %s" % [GameState.t("res_gp_round") % (gp_round + 1), tname]
	else:
		_subtitle_lbl.text = tname

	# Badges (New Record, Medal, Drift Score)
	for c in _badges_box.get_children():
		c.queue_free()
	if is_new_record:
		_add_badge(GameState.t("res_new_record"), UITheme.ACCENT_GOLD)
	if medal != "none":
		var mc := UITheme.ACCENT_GOLD if medal == "gold" else (Color(0.82, 0.86, 0.92) if medal == "silver" else Color(0.86, 0.54, 0.28))
		_add_badge(GameState.t("res_medal_earned") + GameState.t("medal_" + medal), mc)
	if drift_score > 0:
		_add_badge(GameState.t("res_drift_earned") % drift_score, UITheme.ACCENT_CYAN)

	# Classification Table
	for c in _table_box.get_children():
		c.queue_free()

	_add_row([
		GameState.t("res_rank"),
		GameState.t("res_driver"),
		GameState.t("res_car"),
		GameState.t("res_time"),
		GameState.t("res_best"),
		GameState.t("res_total_pts") if is_gp else ""
	], true, false, false)

	for i in range(results.size()):
		var r: Dictionary = results[i]
		var is_p := bool(r.get("is_player", false))
		var dname := GameState.t("res_you") if is_p else str(r.get("driver_name", "AI"))
		var car_spec := CarCatalog.get_car(int(r.get("car_idx", 0)))
		var cname := GameState.get_localized_field(car_spec, "name")
		var ftime := GameState.format_time(float(r.get("finish_time", 0.0)))
		var btime := GameState.format_time(float(r.get("best_lap", 0.0)))
		var pts_txt := ""
		if is_gp:
			if is_final_podium:
				pts_txt = "%d %s (+%d)" % [int(r.get("total_points", 0)), GameState.t("res_pts"), int(r.get("round_points", 0))]
			else:
				pts_txt = "+%d (%d)" % [int(r.get("round_points", 0)), int(r.get("total_points", 0))]
		_add_row(["#%d" % (i + 1), dname, cname, ftime, btime, pts_txt], false, is_p, i == 0)

	_btn_next.visible = is_gp and has_next_gp
	_btn_next.text = GameState.t("res_next_round")
	_btn_rematch.visible = not (is_gp and has_next_gp)
	_btn_rematch.text = GameState.t("res_rematch")
	_btn_menu.text = GameState.t("res_main_menu")


func _add_badge(txt: String, accent: Color) -> void:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.make_panel_box(Color(accent.r * 0.2, accent.g * 0.2, accent.b * 0.2, 0.9), accent, 8, 1, 12, 5))
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", accent)
	pc.add_child(lbl)
	_badges_box.add_child(pc)


func _add_row(cols: Array[String], is_header: bool, is_player: bool, is_first: bool) -> void:
	var pc := PanelContainer.new()
	var bg := Color(0.0, 0.0, 0.0, 0.0)
	var border := Color.TRANSPARENT
	if is_header:
		bg = Color(0.12, 0.16, 0.24, 0.75)
	elif is_player:
		bg = Color(0.06, 0.26, 0.36, 0.85)
		border = UITheme.ACCENT_CYAN
	else:
		bg = Color(0.08, 0.10, 0.16, 0.65)
	pc.add_theme_stylebox_override("panel", UITheme.make_panel_box(bg, border, 6, 1 if is_player else 0, 12, 7))
	_table_box.add_child(pc)

	var hb := HBoxContainer.new()
	pc.add_child(hb)
	var widths := [56, 165, 140, 108, 108, 122]
	for idx in range(cols.size()):
		var lbl := Label.new()
		lbl.text = cols[idx]
		lbl.custom_minimum_size = Vector2(widths[idx], 0)
		lbl.add_theme_font_size_override("font_size", 14 if is_header else 16)
		if is_header:
			lbl.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
		elif idx == 0 and is_first:
			lbl.add_theme_color_override("font_color", UITheme.ACCENT_GOLD)
		elif is_player:
			lbl.add_theme_color_override("font_color", Color.WHITE)
		hb.add_child(lbl)

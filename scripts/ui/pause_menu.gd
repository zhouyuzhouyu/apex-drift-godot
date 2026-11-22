class_name PauseMenu
extends CanvasLayer

## In-race Pause Overlay (Esc / P) with Resume, Restart, Camera Switch, Volume, Language & Quit.

signal resume_requested
signal restart_requested
signal camera_switch_requested
signal quit_requested

var _panel: Control
var _title: Label
var _btn_resume: Button
var _btn_restart: Button
var _btn_cam: Button
var _btn_lang: Button
var _btn_quit: Button
var _vol_label: Label
var _vol_slider: HSlider


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	GameState.language_changed.connect(_on_language_changed)


func _exit_tree() -> void:
	if GameState.language_changed.is_connected(_on_language_changed):
		GameState.language_changed.disconnect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	_refresh_texts()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause_game"):
		get_viewport().set_input_as_handled()
		AudioManager.play_sfx("ui_click")
		resume_requested.emit()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.07, 0.68)
	dim.theme = UITheme.build_theme()
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(390, 0)
	card.add_theme_stylebox_override("panel", UITheme.make_panel_box(UITheme.BG_DARK, UITheme.ACCENT_CYAN, 16, 2, 28, 24))
	center.add_child(card)
	_panel = card

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_title)

	vbox.add_child(HSeparator.new())

	_btn_resume = Button.new()
	UITheme.style_primary_button(_btn_resume, UITheme.ACCENT_RED)
	_btn_resume.pressed.connect(func():
		AudioManager.play_sfx("ui_confirm")
		resume_requested.emit()
	)
	vbox.add_child(_btn_resume)

	_btn_restart = Button.new()
	_btn_restart.pressed.connect(func():
		AudioManager.play_sfx("ui_confirm")
		restart_requested.emit()
	)
	vbox.add_child(_btn_restart)

	_btn_cam = Button.new()
	_btn_cam.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		camera_switch_requested.emit()
	)
	vbox.add_child(_btn_cam)

	# Quick Master Volume slider
	var vol_box := VBoxContainer.new()
	vol_box.add_theme_constant_override("separation", 4)
	vbox.add_child(vol_box)
	_vol_label = Label.new()
	_vol_label.add_theme_font_size_override("font_size", 14)
	_vol_label.add_theme_color_override("font_color", UITheme.TEXT_MUTED)
	vol_box.add_child(_vol_label)

	_vol_slider = HSlider.new()
	_vol_slider.min_value = 0.0
	_vol_slider.max_value = 1.0
	_vol_slider.step = 0.05
	_vol_slider.value = float(GameState.settings.get("master_volume", 0.85))
	_vol_slider.value_changed.connect(func(v: float):
		GameState.settings["master_volume"] = v
		GameState.save_data()
		GameState.settings_changed.emit()
	)
	vol_box.add_child(_vol_slider)

	_btn_lang = Button.new()
	_btn_lang.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		GameState.toggle_language()
	)
	vbox.add_child(_btn_lang)

	_btn_quit = Button.new()
	_btn_quit.pressed.connect(func():
		AudioManager.play_sfx("ui_click")
		quit_requested.emit()
	)
	vbox.add_child(_btn_quit)

	_refresh_texts()


func _refresh_texts() -> void:
	_title.text = GameState.t("pause_title")
	_btn_resume.text = GameState.t("pause_resume")
	_btn_restart.text = GameState.t("pause_restart")
	_btn_cam.text = GameState.t("pause_camera")
	_vol_label.text = GameState.t("set_master")
	_btn_lang.text = GameState.t("btn_lang")
	_btn_quit.text = GameState.t("pause_quit")

class_name PlayerController
extends Node

## Reads keyboard & gamepad inputs and feeds the player's RaceCar + AudioManager.

signal respawn_requested
signal camera_switch_requested
signal transmission_toggled(is_auto: bool)

var car: RaceCar
var active: bool = true


func setup(p_car: RaceCar) -> void:
	car = p_car
	if not car.gear_changed.is_connected(_on_gear_changed):
		car.gear_changed.connect(_on_gear_changed)
	if not car.impact_occurred.is_connected(_on_impact):
		car.impact_occurred.connect(_on_impact)
	if not car.boost_pad_hit.is_connected(_on_boost_pad):
		car.boost_pad_hit.connect(_on_boost_pad)


func _unhandled_input(event: InputEvent) -> void:
	if not active or car == null:
		return
	if event.is_action_pressed("respawn"):
		respawn_requested.emit()
	elif event.is_action_pressed("camera_switch"):
		camera_switch_requested.emit()
	elif event.is_action_pressed("toggle_transmission"):
		car.automatic_transmission = not car.automatic_transmission
		GameState.settings["auto_transmission"] = car.automatic_transmission
		GameState.save_data()
		GameState.settings_changed.emit()
		transmission_toggled.emit(car.automatic_transmission)
		AudioManager.play_sfx("ui_click")
	elif event.is_action_pressed("shift_up") and not car.automatic_transmission:
		car.manual_shift(1)
	elif event.is_action_pressed("shift_down") and not car.automatic_transmission:
		car.manual_shift(-1)
	elif event.is_action_pressed("nitro") and not car.controls_locked and car.nitro > 5.0:
		AudioManager.play_sfx("nitro_ignite", 1.0, 0.85)


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	if not active:
		car.throttle_input = 0.0
		car.brake_input = 0.6
		car.steering_input = 0.0
		car.handbrake_input = 0.0
		car.nitro_input = false
		return

	var raw_throttle := Input.get_action_strength("throttle")
	var raw_brake := Input.get_action_strength("brake")
	var raw_steer := Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	var raw_hb := Input.get_action_strength("handbrake")
	var raw_nitro := Input.is_action_pressed("nitro")

	# Smooth reverse-gear handling for automatic transmission
	if car.current_gear == -1 and car.automatic_transmission:
		car.throttle_input = raw_brake
		car.brake_input = raw_throttle
		if raw_throttle > 0.35 and car.speed < 2.2:
			car.shift(2) # jump cleanly back to 1st gear
	else:
		car.throttle_input = raw_throttle
		car.brake_input = raw_brake

	car.steering_input = clampf(raw_steer, -1.0, 1.0)
	car.handbrake_input = raw_hb
	car.clutch_input = 0.0
	car.nitro_input = raw_nitro

	AudioManager.update_driving_audio(
		car.motor_rpm,
		car.max_rpm,
		car.throttle_input,
		car.get_speed_kmh(),
		car.wheel_slip_intensity,
		car.nitro_active or car.boost_pad_timer > 0.0
	)


func _on_gear_changed(_new_gear: int) -> void:
	AudioManager.play_sfx("gear_shift", randf_range(0.92, 1.12), 0.65)


func _on_impact(intensity: float) -> void:
	AudioManager.play_sfx("collision", randf_range(0.85, 1.15), clampf(intensity * 1.1, 0.3, 1.0))


func _on_boost_pad() -> void:
	AudioManager.play_sfx("boost_pad", 1.0, 0.9)

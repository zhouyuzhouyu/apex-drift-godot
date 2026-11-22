class_name CarCatalog
extends RefCounted

## Complete roster of 4 playable race cars, 6 custom racing liveries, and 5 AI rivals.

static func get_cars() -> Array[Dictionary]:
	return [
		{
			"id": "apex_gtr",
			"name_zh": "极峰 GT-R",
			"name_en": "APEX GT-R",
			"class_zh": "均衡超跑 · 四驱",
			"class_en": "BALANCED GT · AWD",
			"desc_zh": "精准转向与强劲四驱抓地力的完美平衡，适合各种赛道的全能旗舰超跑。",
			"desc_en": "Razor-sharp cornering paired with confident AWD traction. An all-round championship machine.",
			"style": "gt",
			"stats": {"speed": 88, "accel": 86, "handling": 88, "drift": 78},
			"physics": {
				"vehicle_mass": 1300.0,
				"max_torque": 890.0,
				"max_rpm": 8400.0,
				"idle_rpm": 1050.0,
				"gear_ratios": [3.50, 2.36, 1.70, 1.28, 0.99, 0.78],
				"final_drive": 3.88,
				"front_torque_split": 0.35,
				"variable_torque_split": true,
				"front_variable_split": 0.48,
				"front_weight_distribution": 0.50,
				"center_of_gravity_height_offset": -0.26,
				"steering_speed": 4.9,
				"countersteer_speed": 12.5,
				"steering_speed_decay": 0.13,
				"max_steering_angle": deg_to_rad(36.0),
				"countersteer_assist": 0.85,
				"stability_yaw_strength": 6.5,
				"stability_yaw_ground_multiplier": 4.8,
				"road_cof": 3.10,
				"dirt_cof": 2.2,
				"grass_cof": 1.85,
				"kerb_cof": 2.80,
				"lateral_grip_assist": 0.13,
				"longitudinal_grip_ratio": 0.85,
				"coefficient_of_drag": 0.27,
				"downforce_coeff": 2.5,
				"max_speed_kmh": 258.0,
				"nitro_force": 14500.0,
				"nitro_charge_mult": 1.0,
				"drift_turn_rate": 1.04,
				"drift_neutral_deg": 29.0,
				"drift_max_deg": 39.0,
				"drift_speed_retention": 0.94,
				"drift_charge_rate": 1.05,
				"spring_length_front": 0.17,
				"spring_length_rear": 0.19,
				"damping_ratio": 0.65
			}
		},
		{
			"id": "kaze_drift",
			"name_zh": "疾风 DRIFT-S",
			"name_en": "KAZE DRIFT-S",
			"class_zh": "漂移战神 · 后驱",
			"class_en": "DRIFT COUPE · RWD",
			"desc_zh": "专为华丽横滑调校的后驱双门跑车，大角度轨道漂移几乎不掉速，出弯小喷与氮气充能最快。",
			"desc_en": "Wide-angle arcade drift master with effortless rail-slides, minimal speed loss, and fastest boost charging.",
			"style": "drift",
			"stats": {"speed": 84, "accel": 88, "handling": 82, "drift": 98},
			"physics": {
				"vehicle_mass": 1200.0,
				"max_torque": 935.0,
				"max_rpm": 8600.0,
				"idle_rpm": 1000.0,
				"gear_ratios": [3.35, 2.28, 1.62, 1.22, 0.94, 0.75],
				"final_drive": 4.00,
				"front_torque_split": 0.0,
				"variable_torque_split": false,
				"front_variable_split": 0.0,
				"front_weight_distribution": 0.52,
				"center_of_gravity_height_offset": -0.25,
				"steering_speed": 5.6,
				"countersteer_speed": 14.5,
				"steering_speed_decay": 0.11,
				"max_steering_angle": deg_to_rad(44.0),
				"countersteer_assist": 0.92,
				"stability_yaw_strength": 3.2,
				"stability_yaw_ground_multiplier": 2.2,
				"road_cof": 2.55,
				"dirt_cof": 2.0,
				"grass_cof": 1.7,
				"kerb_cof": 2.40,
				"lateral_grip_assist": 0.04,
				"longitudinal_grip_ratio": 0.96,
				"coefficient_of_drag": 0.29,
				"downforce_coeff": 1.9,
				"max_speed_kmh": 248.0,
				"nitro_force": 15200.0,
				"nitro_charge_mult": 1.40,
				"drift_turn_rate": 1.18,
				"drift_neutral_deg": 35.0,
				"drift_max_deg": 46.0,
				"drift_speed_retention": 0.97,
				"drift_charge_rate": 1.35,
				"spring_length_front": 0.18,
				"spring_length_rear": 0.20,
				"damping_ratio": 0.62
			}
		},
		{
			"id": "vortex_f0",
			"name_zh": "涡流 F-ZERO",
			"name_en": "VORTEX F-ZERO",
			"class_zh": "极速方程式 · 高下压力",
			"class_en": "AERO FORMULA · HIGH DF",
			"desc_zh": "轻量化空气动力学原型赛车，拥有最高极速与惊人的高速弯道贴地性能。",
			"desc_en": "Featherweight open-cockpit aero prototype with blistering top speed and immense high-speed cornering grip.",
			"style": "formula",
			"stats": {"speed": 98, "accel": 94, "handling": 95, "drift": 68},
			"physics": {
				"vehicle_mass": 1060.0,
				"max_torque": 950.0,
				"max_rpm": 9500.0,
				"idle_rpm": 1400.0,
				"gear_ratios": [3.22, 2.28, 1.70, 1.33, 1.05, 0.84],
				"final_drive": 3.70,
				"front_torque_split": 0.28,
				"variable_torque_split": true,
				"front_variable_split": 0.40,
				"front_weight_distribution": 0.48,
				"center_of_gravity_height_offset": -0.32,
				"steering_speed": 5.6,
				"countersteer_speed": 13.5,
				"steering_speed_decay": 0.12,
				"max_steering_angle": deg_to_rad(35.0),
				"countersteer_assist": 0.85,
				"stability_yaw_strength": 6.8,
				"stability_yaw_ground_multiplier": 4.8,
				"road_cof": 3.15,
				"dirt_cof": 1.85,
				"grass_cof": 1.55,
				"kerb_cof": 2.95,
				"lateral_grip_assist": 0.12,
				"longitudinal_grip_ratio": 0.84,
				"coefficient_of_drag": 0.22,
				"downforce_coeff": 2.5,
				"max_speed_kmh": 282.0,
				"nitro_force": 14600.0,
				"nitro_charge_mult": 0.90,
				"drift_turn_rate": 0.96,
				"drift_neutral_deg": 24.0,
				"drift_max_deg": 33.0,
				"drift_speed_retention": 0.93,
				"drift_charge_rate": 0.95,
				"spring_length_front": 0.14,
				"spring_length_rear": 0.15,
				"damping_ratio": 0.78
			}
		},
		{
			"id": "titan_rally",
			"name_zh": "泰坦 RALLY-X",
			"name_en": "TITAN RALLY-X",
			"class_zh": "涡轮拉力 · 全地形",
			"class_en": "TURBO RALLY · ALL-TERRAIN",
			"desc_zh": "强悍全时四驱拉力战车，起步爆发惊人，压路肩与砂石路肩毫不减速。",
			"desc_en": "Ferocious full-time AWD rally hatchback with explosive launch torque and unstoppable kerb & off-road grip.",
			"style": "rally",
			"stats": {"speed": 82, "accel": 95, "handling": 90, "drift": 88},
			"physics": {
				"vehicle_mass": 1170.0,
				"max_torque": 1005.0,
				"max_rpm": 8200.0,
				"idle_rpm": 1050.0,
				"gear_ratios": [3.80, 2.54, 1.78, 1.32, 0.99, 0.79],
				"final_drive": 4.12,
				"front_torque_split": 0.46,
				"variable_torque_split": true,
				"front_variable_split": 0.50,
				"front_weight_distribution": 0.52,
				"center_of_gravity_height_offset": -0.25,
				"steering_speed": 5.3,
				"countersteer_speed": 13.2,
				"steering_speed_decay": 0.12,
				"max_steering_angle": deg_to_rad(40.0),
				"countersteer_assist": 0.90,
				"stability_yaw_strength": 5.2,
				"stability_yaw_ground_multiplier": 3.6,
				"road_cof": 3.15,
				"dirt_cof": 2.95,
				"grass_cof": 2.60,
				"kerb_cof": 3.05,
				"lateral_grip_assist": 0.10,
				"longitudinal_grip_ratio": 0.88,
				"coefficient_of_drag": 0.30,
				"downforce_coeff": 2.2,
				"max_speed_kmh": 238.0,
				"nitro_force": 14800.0,
				"nitro_charge_mult": 1.15,
				"drift_turn_rate": 1.12,
				"drift_neutral_deg": 32.0,
				"drift_max_deg": 42.0,
				"drift_speed_retention": 0.95,
				"drift_charge_rate": 1.18,
				"spring_length_front": 0.22,
				"spring_length_rear": 0.24,
				"damping_ratio": 0.58
			}
		}
	]


static func get_liveries() -> Array[Dictionary]:
	return [
		{
			"id": "crimson",
			"name_zh": "炽焰红",
			"name_en": "Crimson Fury",
			"primary": Color(0.88, 0.11, 0.20),
			"accent": Color(0.98, 0.98, 1.0),
			"rim": Color(0.85, 0.87, 0.90)
		},
		{
			"id": "cyber_cyan",
			"name_zh": "赛博青",
			"name_en": "Cyber Cyan",
			"primary": Color(0.05, 0.68, 0.92),
			"accent": Color(1.0, 0.20, 0.55),
			"rim": Color(0.18, 0.20, 0.25)
		},
		{
			"id": "solar_gold",
			"name_zh": "流光金",
			"name_en": "Solar Gold",
			"primary": Color(0.96, 0.68, 0.08),
			"accent": Color(0.10, 0.12, 0.16),
			"rim": Color(0.20, 0.20, 0.22)
		},
		{
			"id": "sakura_pearl",
			"name_zh": "樱雪白",
			"name_en": "Sakura Pearl",
			"primary": Color(0.95, 0.94, 0.97),
			"accent": Color(0.96, 0.36, 0.56),
			"rim": Color(0.82, 0.68, 0.35)
		},
		{
			"id": "emerald_gt",
			"name_zh": "赛道绿",
			"name_en": "British GT",
			"primary": Color(0.07, 0.52, 0.32),
			"accent": Color(0.95, 0.82, 0.20),
			"rim": Color(0.86, 0.74, 0.36)
		},
		{
			"id": "phantom",
			"name_zh": "暗影黑",
			"name_en": "Carbon Phantom",
			"primary": Color(0.14, 0.16, 0.20),
			"accent": Color(0.0, 0.90, 1.0),
			"rim": Color(0.95, 0.22, 0.32)
		}
	]


static func get_ai_rivals() -> Array[Dictionary]:
	return [
		{"name": "KENJI", "car_idx": 1, "livery_idx": 2, "skill_offset": 0.05, "preferred_lane": -2.4, "aggression": 0.85},
		{"name": "ELENA", "car_idx": 2, "livery_idx": 1, "skill_offset": 0.08, "preferred_lane": 2.2, "aggression": 0.90},
		{"name": "MARCO", "car_idx": 0, "livery_idx": 4, "skill_offset": 0.01, "preferred_lane": -1.0, "aggression": 0.75},
		{"name": "SORA", "car_idx": 3, "livery_idx": 3, "skill_offset": -0.02, "preferred_lane": 1.6, "aggression": 0.80},
		{"name": "VIKTOR", "car_idx": 0, "livery_idx": 5, "skill_offset": -0.05, "preferred_lane": 0.0, "aggression": 0.70}
	]


static func get_car(idx: int) -> Dictionary:
	var cars := get_cars()
	return cars[clampi(idx, 0, cars.size() - 1)]


static func get_livery(idx: int) -> Dictionary:
	var liveries := get_liveries()
	return liveries[clampi(idx, 0, liveries.size() - 1)]

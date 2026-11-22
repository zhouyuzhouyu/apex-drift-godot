extends Node

## Global GameState Autoload
## Manages game mode, garage selection, Grand Prix championship, persistent save data,
## ghost lap recordings, settings, and Chinese/English localization.

const SAVE_PATH := "user://apex_drift_save.json"
const TEST_SAVE_PATH := "user://apex_drift_test_save.json"
const GP_POINTS := [10, 8, 6, 4, 2, 1]

var test_mode: bool = false

signal language_changed(lang: String)
signal settings_changed

# Active session selection
var mode: String = "quick_race" # quick_race, grand_prix, time_trial, free_roam
var selected_track_idx: int = 0
var selected_car_idx: int = 0
var selected_livery_idx: int = 0
var difficulty: int = 1 # 0=Novice, 1=Standard, 2=Master
var lap_count: int = 3

# Grand Prix tournament state
var gp_active: bool = false
var gp_round: int = 0
var gp_standings: Dictionary = {} # driver_name -> total points
var gp_last_round_results: Array[Dictionary] = []

# Persistent settings
var settings: Dictionary = {
	"language": "zh",
	"master_volume": 0.85,
	"sfx_volume": 0.90,
	"music_volume": 0.45,
	"camera_mode": 0,
	"auto_transmission": true,
	"show_controls": true,
	"stability_assist": true
}

# Persistent records & career
var records: Dictionary = {} # track_id -> {best_lap: float, medal: String, ghost: Array}
var career: Dictionary = {
	"races_finished": 0,
	"wins": 0,
	"gp_titles": 0,
	"total_drift_score": 0
}

const I18N := {
	"zh": {
		"game_title": "APEX DRIFT · 极速漂移",
		"game_subtitle": "GODOT 4 拟真街机竞速",
		"mode_grand_prix": "大奖赛锦标赛",
		"mode_grand_prix_desc": "连续征战全部 3 条赛道，累积积分争夺总冠军奖杯",
		"mode_quick_race": "单场竞速",
		"mode_quick_race_desc": "自选赛道与难度，与 5 名 AI 车手同场竞技",
		"mode_time_trial": "计时挑战",
		"mode_time_trial_desc": "挑战个人最快单圈幽灵车，冲击金牌纪录",
		"mode_free_roam": "自由练习",
		"mode_free_roam_desc": "无圈数限制，自由漂移与熟悉赛道走线",
		"btn_start_race": "开始比赛",
		"btn_garage": "车库与涂装",
		"btn_settings": "设置",
		"btn_controls": "操作指南",
		"btn_back": "返回",
		"btn_close": "关闭",
		"btn_lang": "EN / 中文",
		"select_mode": "选择模式",
		"select_track": "选择赛道",
		"select_car": "选择赛车",
		"select_livery": "车身涂装",
		"difficulty": "AI 难度",
		"diff_0": "新手",
		"diff_1": "标准",
		"diff_2": "大师",
		"laps": "比赛圈数",
		"laps_unit": "圈",
		"stat_speed": "极速",
		"stat_accel": "加速",
		"stat_handling": "操控",
		"stat_drift": "漂移",
		"best_lap": "最快单圈",
		"no_record": "--:--.--",
		"medal_gold": "金牌",
		"medal_silver": "银牌",
		"medal_bronze": "铜牌",
		"medal_none": "未获牌",
		"career_stats": "生涯战绩：完赛 %d 场 · 冠军 %d 次 · 锦标赛 %d 冠",
		"hud_pos": "排名",
		"hud_solo": "单人",
		"hud_lap": "圈数",
		"hud_time": "本圈",
		"hud_best": "最佳",
		"hud_total": "总计",
		"hud_nitro": "氮气",
		"hud_drift": "漂移",
		"hud_drift_lv1": "LV.1 蓝焰蓄力",
		"hud_drift_lv2": "LV.2 金焰强喷",
		"hud_drift_lv3": "LV.3 紫焰终极喷!",
		"hud_drift_boost_1": "漂移小喷！MINI BOOST!",
		"hud_drift_boost_2": "超级漂移喷射！SUPER BOOST!",
		"hud_drift_boost_3": "终极漂移爆发！ULTRA BOOST!",
		"hud_wrong_way": "⚠ 逆行警告 · 请调头",
		"hud_final_lap": "最后一圈！",
		"hud_lap_banner": "第 %d / %d 圈",
		"hud_go": "出发！GO!",
		"hud_perfect_start": "完美弹射起步！",
		"hud_new_best": "新圈速纪录！",
		"hud_auto": "自动挡",
		"hud_manual": "手动挡",
		"hud_cam_0": "近距视角",
		"hud_cam_1": "远距视角",
		"hud_cam_2": "车头视角",
		"hud_controls_bar": "W/S 油门刹车 | A/D 转向 | Space/轻点S 轨道漂移 | Shift 氮气 | C 视角 | R 重置 | Esc 暂停",
		"pause_title": "比赛暂停",
		"pause_resume": "继续比赛",
		"pause_restart": "重新开始",
		"pause_camera": "切换视角",
		"pause_quit": "返回主菜单",
		"settings_title": "游戏设置",
		"set_master": "主音量",
		"set_sfx": "引擎与音效",
		"set_music": "背景音乐",
		"set_auto_trans": "自动变速箱",
		"set_stability": "电子稳定辅助 (ESP)",
		"set_controls_hud": "显示操作提示条",
		"set_language": "界面语言",
		"res_race_complete": "比赛结束",
		"res_gp_complete": "大奖赛最终颁奖台！",
		"res_rank": "名次",
		"res_driver": "车手",
		"res_car": "赛车",
		"res_time": "成绩",
		"res_best": "最快圈",
		"res_pts": "积分",
		"res_next_round": "下一站赛道",
		"res_rematch": "再来一局",
		"res_main_menu": "返回主菜单",
		"res_you": "你 (PLAYER)",
		"res_gp_round": "大奖赛第 %d / 3 站",
		"res_total_pts": "总积分",
		"res_drift_earned": "本场漂移得分：%d",
		"res_new_record": "★ 刷新赛道纪录！",
		"res_medal_earned": "获得奖牌：",
		"ctrl_title": "驾驶控制指南",
		"ctrl_body": "W / ↑  — 油门加速\nS / ↓  — 刹车 / 倒车（高速转弯轻点即可触发漂移！）\nA / D 或 ← / →  — 左右转向（漂移中按内侧收紧贴弯心，反打外侧拉宽出弯）\nSpace  — 一键轨道起漂（漂移几乎不掉速，并快速蓄力 3 阶出弯小喷 + 氮气！）\nShift / N  — 喷射氮气加速\nC  — 切换视角（近距 / 远距 / 车头）\nB / V  — 后视镜回看\nR  — 立即复位至赛道中央\nM  — 切换自动挡 / 手动挡（Q 降挡 / E 升挡）\nEsc / P  — 暂停菜单\n\n漂移秘籍：入弯时按住方向轻点 Space（或轻点 S）立刻锁入大角度轨道漂移；\n保持滑行蓄满 LV.1 蓝焰 → LV.2 金焰 → LV.3 紫焰，出弯回正瞬间自动爆发【漂移小喷】！"
	},
	"en": {
		"game_title": "APEX DRIFT",
		"game_subtitle": "GODOT 4 ARCADE-SIMCADE RACER",
		"mode_grand_prix": "GRAND PRIX",
		"mode_grand_prix_desc": "Race all 3 circuits back-to-back for championship points and the trophy",
		"mode_quick_race": "QUICK RACE",
		"mode_quick_race_desc": "Pick any circuit and difficulty against 5 competitive AI rivals",
		"mode_time_trial": "TIME TRIAL",
		"mode_time_trial_desc": "Chase your saved Best Lap Ghost Car and earn Gold/Silver/Bronze medals",
		"mode_free_roam": "FREE ROAM",
		"mode_free_roam_desc": "Unlimited laps to practice racing lines and chain massive drifts",
		"btn_start_race": "START RACE",
		"btn_garage": "GARAGE & LIVERY",
		"btn_settings": "SETTINGS",
		"btn_controls": "CONTROLS",
		"btn_back": "BACK",
		"btn_close": "CLOSE",
		"btn_lang": "中文 / EN",
		"select_mode": "GAME MODE",
		"select_track": "CIRCUIT",
		"select_car": "VEHICLE",
		"select_livery": "LIVERY",
		"difficulty": "AI DIFFICULTY",
		"diff_0": "NOVICE",
		"diff_1": "STANDARD",
		"diff_2": "MASTER",
		"laps": "LAPS",
		"laps_unit": "Laps",
		"stat_speed": "TOP SPEED",
		"stat_accel": "ACCEL",
		"stat_handling": "HANDLING",
		"stat_drift": "DRIFT",
		"best_lap": "BEST LAP",
		"no_record": "--:--.--",
		"medal_gold": "GOLD",
		"medal_silver": "SILVER",
		"medal_bronze": "BRONZE",
		"medal_none": "NONE",
		"career_stats": "CAREER: %d Races · %d Wins · %d GP Titles",
		"hud_pos": "POS",
		"hud_solo": "SOLO",
		"hud_lap": "LAP",
		"hud_time": "TIME",
		"hud_best": "BEST",
		"hud_total": "TOTAL",
		"hud_nitro": "NITRO",
		"hud_drift": "DRIFT",
		"hud_drift_lv1": "LV.1 MINI BOOST",
		"hud_drift_lv2": "LV.2 SUPER BOOST",
		"hud_drift_lv3": "LV.3 ULTRA BOOST!",
		"hud_drift_boost_1": "DRIFT MINI BOOST!",
		"hud_drift_boost_2": "SUPER DRIFT BOOST!",
		"hud_drift_boost_3": "ULTRA DRIFT BOOST!",
		"hud_wrong_way": "⚠ WRONG WAY · TURN AROUND",
		"hud_final_lap": "FINAL LAP!",
		"hud_lap_banner": "LAP %d / %d",
		"hud_go": "GO!",
		"hud_perfect_start": "PERFECT LAUNCH!",
		"hud_new_best": "NEW BEST LAP!",
		"hud_auto": "AUTO",
		"hud_manual": "MANUAL",
		"hud_cam_0": "CHASE CLOSE",
		"hud_cam_1": "CHASE FAR",
		"hud_cam_2": "HOOD CAM",
		"hud_controls_bar": "W/S Throttle/Brake | A/D Steer | Space/Tap S Rail-Drift | Shift Nitro | C Cam | R Reset | Esc Pause",
		"pause_title": "RACE PAUSED",
		"pause_resume": "RESUME",
		"pause_restart": "RESTART RACE",
		"pause_camera": "SWITCH CAMERA",
		"pause_quit": "MAIN MENU",
		"settings_title": "SETTINGS",
		"set_master": "Master Volume",
		"set_sfx": "Engine & SFX",
		"set_music": "Music Volume",
		"set_auto_trans": "Automatic Transmission",
		"set_stability": "Stability Assist (ESP)",
		"set_controls_hud": "Show Controls Bar",
		"set_language": "Language",
		"res_race_complete": "RACE COMPLETE",
		"res_gp_complete": "GRAND PRIX CHAMPIONSHIP PODIUM!",
		"res_rank": "POS",
		"res_driver": "DRIVER",
		"res_car": "CAR",
		"res_time": "TIME",
		"res_best": "BEST LAP",
		"res_pts": "PTS",
		"res_next_round": "NEXT CIRCUIT",
		"res_rematch": "RACE AGAIN",
		"res_main_menu": "MAIN MENU",
		"res_you": "YOU (PLAYER)",
		"res_gp_round": "GRAND PRIX ROUND %d / 3",
		"res_total_pts": "TOTAL PTS",
		"res_drift_earned": "DRIFT SCORE: %d",
		"res_new_record": "★ NEW TRACK RECORD!",
		"res_medal_earned": "MEDAL EARNED: ",
		"ctrl_title": "DRIVING CONTROLS",
		"ctrl_body": "W / Up  — Accelerate\nS / Down  — Brake / Reverse (tap while turning to Brake-to-Drift!)\nA / D or Left / Right  — Steer (hold inside to hug apex, counter-steer to widen exit)\nSpace  — Instant Arcade Rail-Drift (near-zero speed loss + 3-tier Exit Boost & Nitro!)\nShift / N  — Nitro Boost\nC  — Cycle Camera (Close / Far / Hood)\nB / V  — Look Back\nR  — Reset Car to Track\nM  — Toggle Auto/Manual Gearbox (Q Down / E Up)\nEsc / P  — Pause Menu\n\nPro Tip: Tap Space or S into a turn to lock into a sweeping rail-drift.\nHold to charge LV.1 Cyan -> LV.2 Gold -> LV.3 Violet, then straighten out for an explosive EXIT BOOST!"
	}
}


func _ready() -> void:
	load_save()


func _exit_tree() -> void:
	UITheme.clear_cache()
	TextureFactory.clear_cache()


func enable_test_mode() -> void:
	test_mode = true
	records.clear()
	gp_standings.clear()
	gp_last_round_results.clear()
	career = {
		"races_finished": 0,
		"wins": 0,
		"gp_titles": 0,
		"total_drift_score": 0
	}


func _get_save_path() -> String:
	return TEST_SAVE_PATH if test_mode else SAVE_PATH


func t(key: String) -> String:
	var lang: String = settings.get("language", "zh")
	if I18N.has(lang) and I18N[lang].has(key):
		return I18N[lang][key]
	if I18N["en"].has(key):
		return I18N["en"][key]
	return key


func toggle_language() -> void:
	settings["language"] = "en" if settings.get("language", "zh") == "zh" else "zh"
	save_data()
	language_changed.emit(settings["language"])
	settings_changed.emit()


func get_localized_field(dict: Dictionary, base_key: String) -> String:
	var lang: String = settings.get("language", "zh")
	var k := "%s_%s" % [base_key, lang]
	if dict.has(k):
		return str(dict[k])
	return str(dict.get("%s_en" % base_key, ""))


func start_grand_prix() -> void:
	mode = "grand_prix"
	gp_active = true
	gp_round = 0
	selected_track_idx = 0
	lap_count = 3
	gp_standings.clear()
	gp_last_round_results.clear()


func advance_grand_prix_round() -> bool:
	gp_round += 1
	if gp_round >= TrackCatalog.get_tracks().size():
		gp_active = false
		return false
	selected_track_idx = gp_round
	return true


func record_grand_prix_results(results: Array[Dictionary]) -> void:
	for i in range(results.size()):
		var r: Dictionary = results[i]
		var pts: int = GP_POINTS[mini(i, GP_POINTS.size() - 1)]
		var dname: String = r["driver_name"]
		gp_standings[dname] = int(gp_standings.get(dname, 0)) + pts
		r["round_points"] = pts
		r["total_points"] = gp_standings[dname]
	gp_last_round_results = results.duplicate(true)
	if gp_round == TrackCatalog.get_tracks().size() - 1:
		# Award championship title using identical tie-break as ResultsScreen podium:
		# total_points descending, then final-round finish_time ascending
		var standings_rows := results.duplicate()
		standings_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := int(a.get("total_points", 0))
			var pb := int(b.get("total_points", 0))
			if pa != pb:
				return pa > pb
			return float(a.get("finish_time", INF)) < float(b.get("finish_time", INF))
		)
		if standings_rows.size() > 0 and bool(standings_rows[0].get("is_player", false)):
			career["gp_titles"] = int(career.get("gp_titles", 0)) + 1
			save_data()


func get_track_record(track_id: String) -> Dictionary:
	return records.get(track_id, {"best_lap": 0.0, "medal": "none", "ghost": []})


func save_lap_record(track_id: String, lap_time: float, ghost_frames: Array) -> Dictionary:
	var rec: Dictionary = records.get(track_id, {"best_lap": 0.0, "medal": "none", "ghost": []})
	var is_new_best := false
	if lap_time > 1.0 and (float(rec.get("best_lap", 0.0)) <= 0.0 or lap_time < float(rec["best_lap"])):
		rec["best_lap"] = lap_time
		is_new_best = true
		if ghost_frames.size() > 10:
			rec["ghost"] = ghost_frames
	# Determine medal
	var track_data := _find_track_by_id(track_id)
	var medal := str(rec.get("medal", "none"))
	var earned_now := "none"
	if not track_data.is_empty():
		var mt: Dictionary = track_data["medal_times"]
		if lap_time <= float(mt["gold"]):
			earned_now = "gold"
		elif lap_time <= float(mt["silver"]):
			earned_now = "silver"
		elif lap_time <= float(mt["bronze"]):
			earned_now = "bronze"
		if _medal_rank(earned_now) > _medal_rank(medal):
			rec["medal"] = earned_now
	records[track_id] = rec
	save_data()
	return {"is_new_best": is_new_best, "medal": earned_now}


func record_race_finished(player_rank: int, drift_score: int) -> void:
	career["races_finished"] = int(career.get("races_finished", 0)) + 1
	if player_rank == 1:
		career["wins"] = int(career.get("wins", 0)) + 1
	career["total_drift_score"] = int(career.get("total_drift_score", 0)) + drift_score
	save_data()


func _medal_rank(m: String) -> int:
	match m:
		"gold": return 3
		"silver": return 2
		"bronze": return 1
		_: return 0


func _find_track_by_id(track_id: String) -> Dictionary:
	for tr in TrackCatalog.get_tracks():
		if tr["id"] == track_id:
			return tr
	return {}


static func format_time(sec: float, allow_zero: bool = false) -> String:
	if not is_finite(sec) or sec < 0.0 or (not allow_zero and sec <= 0.0):
		return "--:--.--"
	var mins := int(sec / 60.0)
	var rem := sec - float(mins) * 60.0
	var whole := int(rem)
	var cs := int((rem - float(whole)) * 100.0)
	return "%02d:%02d.%02d" % [mins, whole, cs]


func save_data() -> void:
	var payload := {
		"settings": settings,
		"records": records,
		"career": career,
		"selection": {
			"track": selected_track_idx,
			"car": selected_car_idx,
			"livery": selected_livery_idx,
			"difficulty": difficulty,
			"laps": lap_count
		}
	}
	var f := FileAccess.open(_get_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(payload))
		f.close()


func load_save() -> void:
	var path := _get_save_path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if parsed.has("settings") and typeof(parsed["settings"]) == TYPE_DICTIONARY:
		for k in parsed["settings"]:
			settings[k] = parsed["settings"][k]
	if parsed.has("records") and typeof(parsed["records"]) == TYPE_DICTIONARY:
		records = parsed["records"]
	if parsed.has("career") and typeof(parsed["career"]) == TYPE_DICTIONARY:
		for k in parsed["career"]:
			career[k] = parsed["career"][k]
	if parsed.has("selection") and typeof(parsed["selection"]) == TYPE_DICTIONARY:
		var sel: Dictionary = parsed["selection"]
		selected_track_idx = clampi(int(sel.get("track", 0)), 0, TrackCatalog.get_tracks().size() - 1)
		selected_car_idx = clampi(int(sel.get("car", 0)), 0, CarCatalog.get_cars().size() - 1)
		selected_livery_idx = clampi(int(sel.get("livery", 0)), 0, CarCatalog.get_liveries().size() - 1)
		difficulty = clampi(int(sel.get("difficulty", 1)), 0, 2)
		lap_count = clampi(int(sel.get("laps", 3)), 2, 5)

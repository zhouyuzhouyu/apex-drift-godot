class_name TrackBuilder
extends RefCounted

## Builds the entire 3D circuit geometry, smooth trimesh road colliders, frictionless guardrails,
## start/finish F1 gantry lights, boost pads, corner chevron signs, grandstands, and themed scenery.

static func build_track(parent: Node3D, track_data: Dictionary) -> Dictionary:
	var spline := TrackSpline.new()
	spline.build_from_control_points(
		track_data["control_points"],
		float(track_data["road_width"]),
		float(track_data["bank_strength"]),
		3.0
	)

	var root := Node3D.new()
	root.name = "TrackWorld"
	parent.add_child(root)

	var theme: Dictionary = track_data["theme"]
	var half_road: float = float(track_data["road_width"]) * 0.5
	var kerb_w: float = 1.25
	var shoulder_w: float = float(track_data["shoulder_width"])
	var barrier_offset: float = half_road + kerb_w + shoulder_w - 0.35

	# 1. Sky, Fog & Sun Lighting
	_build_environment(root, theme)

	# 2. Road Asphalt Ribbon + Collider (Layer 1, Group "Road")
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_texture = TextureFactory.make_asphalt_texture(theme["road_color"], bool(theme["is_night"]))
	road_mat.roughness = float(theme["road_roughness"])
	road_mat.metallic = 0.08 if bool(theme["is_night"]) else 0.02
	road_mat.uv1_triplanar = false
	_build_ribbon_mesh(root, spline, -half_road, half_road, 0.0, 0.0, road_mat, 1, "Road", 0.08, "AsphaltRoad")

	# 3. Left & Right Racing Kerbs (Layer 1, Group "Kerb")
	var kerb_mat := StandardMaterial3D.new()
	kerb_mat.albedo_texture = TextureFactory.make_kerb_texture(theme["kerb_a"], theme["kerb_b"])
	kerb_mat.roughness = 0.72
	if bool(theme["is_night"]):
		kerb_mat.emission_enabled = true
		kerb_mat.emission_texture = kerb_mat.albedo_texture
		kerb_mat.emission_energy_multiplier = 0.85
	_build_ribbon_mesh(root, spline, -half_road - kerb_w, -half_road, 0.04, 0.0, kerb_mat, 1, "Kerb", 0.22, "LeftKerb")
	_build_ribbon_mesh(root, spline, half_road, half_road + kerb_w, 0.0, 0.04, kerb_mat, 1, "Kerb", 0.22, "RightKerb")

	# 4. Left & Right Shoulders / Verges (Layer 1, Group theme["shoulder_surface"])
	var shoulder_mat := StandardMaterial3D.new()
	shoulder_mat.albedo_texture = TextureFactory.make_shoulder_texture(theme["shoulder_color"])
	shoulder_mat.roughness = 0.92
	var sh_group := str(theme.get("shoulder_surface", "Grass"))
	_build_ribbon_mesh(root, spline, -half_road - kerb_w - shoulder_w, -half_road - kerb_w, -0.05, 0.03, shoulder_mat, 1, sh_group, 0.09, "LeftShoulder")
	_build_ribbon_mesh(root, spline, half_road + kerb_w, half_road + kerb_w + shoulder_w, 0.03, -0.05, shoulder_mat, 1, sh_group, 0.09, "RightShoulder")

	# 5. Outer Embankment Skirt (28m wide, always extending cleanly below BaseWorldPlane y = -12m!)
	var skirt_mat := StandardMaterial3D.new()
	skirt_mat.albedo_color = Color(theme["shoulder_color"]).darkened(0.26)
	skirt_mat.roughness = 0.95
	var outer_sh := half_road + kerb_w + shoulder_w
	_build_embankment_skirt(root, spline, -outer_sh, -outer_sh - 28.0, -0.05, true, skirt_mat, "LeftSkirt")
	_build_embankment_skirt(root, spline, outer_sh, outer_sh + 28.0, -0.05, false, skirt_mat, "RightSkirt")

	# 6. Continuous Smooth Guardrail Barriers (Layer 2, low friction so cars glide instead of snagging!)
	var barrier_mat := StandardMaterial3D.new()
	barrier_mat.albedo_texture = TextureFactory.make_barrier_texture(theme["barrier_accent"])
	barrier_mat.roughness = 0.45
	barrier_mat.metallic = 0.35
	if bool(theme["is_night"]):
		barrier_mat.emission_enabled = true
		barrier_mat.emission = theme["barrier_accent"]
		barrier_mat.emission_energy_multiplier = 0.35
	_build_guardrail_wall(root, spline, -barrier_offset, true, barrier_mat, "LeftBarrier")
	_build_guardrail_wall(root, spline, barrier_offset, false, barrier_mat, "RightBarrier")

	# 7. Ground / Ocean Base Plane below circuit
	_build_base_terrain(root, spline, theme)

	# 8. Start/Finish Checkered Line & F1 Starting Gantry (with 5 controllable lights!)
	var start_lights := _build_start_gantry(root, spline, half_road, theme)

	# 9. Boost Pads along track
	var boost_res := _build_boost_pads(root, spline, track_data.get("boost_fractions", []))

	# 10. Corner Warning Chevron Signs on sharp bends
	_build_corner_chevrons(root, spline, barrier_offset + 1.2, bool(theme["is_night"]))

	# 11. Grandstands & Themed Scenery (Trees, Torii Gates, Neon Arches, City Towers, Lighthouse)
	_build_grandstands(root, spline, barrier_offset + 5.5, theme)
	_build_scenery(root, spline, barrier_offset, theme)

	# 12. 8 Sequential Checkpoints (normalized progress fractions)
	var checkpoints: Array[float] = []
	for c in range(8):
		checkpoints.append(float(c + 1) / 8.0)

	return {
		"root": root,
		"spline": spline,
		"start_lights": start_lights,
		"boost_areas": boost_res["areas"],
		"boost_distances": boost_res["distances"],
		"checkpoints": checkpoints,
		"is_night": bool(theme["is_night"])
	}


static func _build_environment(root: Node3D, theme: Dictionary) -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = theme["sky_top"]
	sky_mat.sky_horizon_color = theme["sky_horizon"]
	sky_mat.ground_bottom_color = theme["ground_bottom"]
	sky_mat.ground_horizon_color = theme["ground_horizon"]
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme["ambient_color"]
	env.ambient_light_energy = float(theme["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = theme["fog_color"]
	env.fog_density = float(theme["fog_density"])
	world_env.environment = env
	root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = theme["sun_color"]
	sun.light_energy = float(theme["sun_energy"])
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	var ang: Vector3 = theme["sun_angles"]
	sun.rotation_degrees = ang
	root.add_child(sun)


static func _build_ribbon_mesh(
	root: Node3D,
	spline: TrackSpline,
	lat_left: float,
	lat_right: float,
	y_left: float,
	y_right: float,
	mat: Material,
	collision_layer: int,
	surface_group: String,
	uv_v_scale: float,
	node_name: String
) -> void:
	var n := spline.sample_count()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v_accum := 0.0
	for i in range(n):
		var nxt := (i + 1) % n
		var seg_len := spline.points[i].distance_to(spline.points[nxt])
		var v0 := v_accum * uv_v_scale
		var v1 := (v_accum + seg_len) * uv_v_scale
		v_accum += seg_len

		var p0l := spline.points[i] + spline.rights[i] * lat_left + spline.ups[i] * y_left
		var p0r := spline.points[i] + spline.rights[i] * lat_right + spline.ups[i] * y_right
		var p1l := spline.points[nxt] + spline.rights[nxt] * lat_left + spline.ups[nxt] * y_left
		var p1r := spline.points[nxt] + spline.rights[nxt] * lat_right + spline.ups[nxt] * y_right

		var n0 := spline.ups[i]
		var n1 := spline.ups[nxt]

		# Front-facing clockwise winding looking from +Y down in Godot:
		# (p0l -> p1l -> p1r) has cross (p1l-p0l)x(p1r-p0l) = fwd x right = -up,
		# so (p0l -> p0r -> p1r) has (right) x (fwd) = +up! Let's verify:
		# p0r - p0l = +right, p1r - p0l = +right + fwd -> (+right) x (+right + fwd) = right x fwd = +up!
		# Wait: Godot front face winding is CLOCKWISE when looking at the front face!
		# Standing at +Y looking down at XZ (fwd = -Z = up on screen, right = +X = right on screen):
		# p0l (bottom-left) -> p1l (top-left) -> p1r (top-right) IS CLOCKWISE!!
		# Let's double check Godot SurfaceTool convention:
		# In Godot, for a quad in XZ facing +Y:
		# v0=(0,0,1), v1=(0,0,0), v2=(1,0,0): clockwise from +Y -> front face points +Y!
		st.set_normal(n0); st.set_uv(Vector2(0.0, v0)); st.add_vertex(p0l)
		st.set_normal(n1); st.set_uv(Vector2(0.0, v1)); st.add_vertex(p1l)
		st.set_normal(n1); st.set_uv(Vector2(1.0, v1)); st.add_vertex(p1r)

		st.set_normal(n0); st.set_uv(Vector2(0.0, v0)); st.add_vertex(p0l)
		st.set_normal(n1); st.set_uv(Vector2(1.0, v1)); st.add_vertex(p1r)
		st.set_normal(n0); st.set_uv(Vector2(1.0, v0)); st.add_vertex(p0r)

	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	if collision_layer > 0:
		var body := StaticBody3D.new()
		body.name = node_name + "_Body"
		body.collision_layer = collision_layer
		body.collision_mask = 0
		if surface_group != "":
			body.add_to_group(surface_group)
		var col := CollisionShape3D.new()
		col.shape = mesh.create_trimesh_shape()
		body.add_child(col)
		root.add_child(body)


static func _build_embankment_skirt(
	root: Node3D,
	spline: TrackSpline,
	lat_inner: float,
	lat_outer: float,
	y_inner: float,
	is_left: bool,
	mat: Material,
	node_name: String
) -> void:
	# Builds a continuous sloped embankment skirt whose outer bottom edge always reaches
	# minf(spline_y - 16.0, -13.5), connecting elevated mountain tracks cleanly into BaseWorldPlane (-12m).
	var n := spline.sample_count()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v_accum := 0.0
	for i in range(n):
		var nxt := (i + 1) % n
		var seg_len := spline.points[i].distance_to(spline.points[nxt])
		var v0 := v_accum * 0.04
		var v1 := (v_accum + seg_len) * 0.04
		v_accum += seg_len

		var p0_in := spline.points[i] + spline.rights[i] * lat_inner + spline.ups[i] * y_inner
		var p1_in := spline.points[nxt] + spline.rights[nxt] * lat_inner + spline.ups[nxt] * y_inner

		var p0_out := spline.points[i] + spline.rights[i] * lat_outer
		p0_out.y = minf(spline.points[i].y - 16.0, -13.5)
		var p1_out := spline.points[nxt] + spline.rights[nxt] * lat_outer
		p1_out.y = minf(spline.points[nxt].y - 16.0, -13.5)

		var p0l := p0_out if is_left else p0_in
		var p0r := p0_in if is_left else p0_out
		var p1l := p1_out if is_left else p1_in
		var p1r := p1_in if is_left else p1_out

		st.set_uv(Vector2(0.0, v0)); st.add_vertex(p0l)
		st.set_uv(Vector2(0.0, v1)); st.add_vertex(p1l)
		st.set_uv(Vector2(1.0, v1)); st.add_vertex(p1r)

		st.set_uv(Vector2(0.0, v0)); st.add_vertex(p0l)
		st.set_uv(Vector2(1.0, v1)); st.add_vertex(p1r)
		st.set_uv(Vector2(1.0, v0)); st.add_vertex(p0r)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _build_guardrail_wall(
	root: Node3D,
	spline: TrackSpline,
	lat_offset: float,
	is_left: bool,
	mat: Material,
	node_name: String
) -> void:
	var n := spline.sample_count()
	var vis_h := 1.15
	var col_h := 4.0
	var vis_st := SurfaceTool.new()
	vis_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_st := SurfaceTool.new()
	col_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v_accum := 0.0
	for i in range(n):
		var nxt := (i + 1) % n
		var seg_len := spline.points[i].distance_to(spline.points[nxt])
		var u0 := v_accum * 0.25
		var u1 := (v_accum + seg_len) * 0.25
		v_accum += seg_len

		var b0 := spline.points[i] + spline.rights[i] * lat_offset - spline.ups[i] * 0.15
		var b1 := spline.points[nxt] + spline.rights[nxt] * lat_offset - spline.ups[nxt] * 0.15
		var t0 := b0 + spline.ups[i] * vis_h
		var t1 := b1 + spline.ups[nxt] * vis_h

		# Extend collision wall 0.5m below road edge and 4.0m high, plus a 0.55m backup inward wall
		var cb0 := spline.points[i] + spline.rights[i] * lat_offset - spline.ups[i] * 0.50
		var cb1 := spline.points[nxt] + spline.rights[nxt] * lat_offset - spline.ups[nxt] * 0.50
		var ct0 := cb0 + spline.ups[i] * (col_h + 0.50)
		var ct1 := cb1 + spline.ups[nxt] * (col_h + 0.50)

		var out_shift := -0.55 if is_left else 0.55
		var bb0 := cb0 + spline.rights[i] * out_shift
		var bb1 := cb1 + spline.rights[nxt] * out_shift
		var bt0 := ct0 + spline.rights[i] * out_shift
		var bt1 := ct1 + spline.rights[nxt] * out_shift

		var inward_n0 := spline.rights[i] if is_left else -spline.rights[i]
		var inward_n1 := spline.rights[nxt] if is_left else -spline.rights[nxt]

		# Double-sided visual guardrail + strictly inward-facing double-layer collision wall (prevents high-speed tunneling!)
		if is_left:
			_add_quad(vis_st, b0, t0, t1, b1, inward_n0, inward_n1, u0, u1)
			_add_quad(vis_st, b1, t1, t0, b0, -inward_n1, -inward_n0, u1, u0)
			_add_quad(col_st, cb0, ct0, ct1, cb1, inward_n0, inward_n1, u0, u1)
			_add_quad(col_st, bb0, bt0, bt1, bb1, inward_n0, inward_n1, u0, u1)
		else:
			_add_quad(vis_st, b1, t1, t0, b0, inward_n1, inward_n0, u1, u0)
			_add_quad(vis_st, b0, t0, t1, b1, -inward_n0, -inward_n1, u0, u1)
			_add_quad(col_st, cb1, ct1, ct0, cb0, inward_n1, inward_n0, u1, u0)
			_add_quad(col_st, bb1, bt1, bt0, bb0, inward_n1, inward_n0, u1, u0)

	var vis_mesh := vis_st.commit()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = vis_mesh
	mi.material_override = mat
	root.add_child(mi)

	var col_mesh := col_st.commit()
	var body := StaticBody3D.new()
	body.name = node_name + "_Body"
	body.collision_layer = 2 # TrackBarriers layer (wheel raycasts ignore layer 2!)
	body.collision_mask = 0
	var pmat := PhysicsMaterial.new()
	pmat.friction = 0.04 # Ultra-low friction so cars glide cleanly along guardrails!
	pmat.bounce = 0.14
	body.physics_material_override = pmat
	var shape := CollisionShape3D.new()
	shape.shape = col_mesh.create_trimesh_shape()
	body.add_child(shape)
	root.add_child(body)


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n0: Vector3, n1: Vector3, u0: float, u1: float) -> void:
	st.set_normal(n0); st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a)
	st.set_normal(n0); st.set_uv(Vector2(u0, 0.0)); st.add_vertex(b)
	st.set_normal(n1); st.set_uv(Vector2(u1, 0.0)); st.add_vertex(c)

	st.set_normal(n0); st.set_uv(Vector2(u0, 1.0)); st.add_vertex(a)
	st.set_normal(n1); st.set_uv(Vector2(u1, 0.0)); st.add_vertex(c)
	st.set_normal(n1); st.set_uv(Vector2(u1, 1.0)); st.add_vertex(d)


static func _build_base_terrain(root: Node3D, spline: TrackSpline, theme: Dictionary) -> void:
	var min_x := INF; var max_x := -INF; var min_z := INF; var max_z := -INF
	for p in spline.points:
		min_x = minf(min_x, p.x); max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z); max_z = maxf(max_z, p.z)
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(2600.0, 2600.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme["ground_plane_color"]
	mat.roughness = 0.30 if theme["id"] == "coastal" else 0.90
	mat.metallic = 0.25 if theme["id"] == "coastal" else 0.0
	var ground := MeshInstance3D.new()
	ground.name = "BaseWorldPlane"
	ground.mesh = plane_mesh
	ground.material_override = mat
	ground.position = Vector3(cx, -12.0, cz)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)

	# Stylized distant hills/mountains framing the horizon
	var hill_mat := StandardMaterial3D.new()
	if theme["id"] == "coastal":
		hill_mat.albedo_color = Color(0.24, 0.52, 0.30)
	elif theme["id"] == "sakura":
		hill_mat.albedo_color = Color(0.32, 0.26, 0.34)
	else:
		hill_mat.albedo_color = Color(0.08, 0.09, 0.18)
	hill_mat.roughness = 0.92

	var rng := RandomNumberGenerator.new()
	rng.seed = 4040 + theme["id"].hash()
	for i in range(18):
		var angle := float(i) * TAU / 18.0 + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(440.0, 680.0)
		var hill := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = rng.randf_range(12.0, 35.0)
		cyl.bottom_radius = rng.randf_range(90.0, 165.0)
		cyl.height = rng.randf_range(45.0, 120.0)
		cyl.radial_segments = 8
		hill.mesh = cyl
		hill.material_override = hill_mat
		hill.position = Vector3(cx + cos(angle) * dist, cyl.height * 0.5 - 16.0, cz + sin(angle) * dist)
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hill)


static func _build_start_gantry(root: Node3D, spline: TrackSpline, half_road: float, theme: Dictionary) -> Array[StandardMaterial3D]:
	var gantry := Node3D.new()
	gantry.name = "StartFinishGantry"
	gantry.transform = spline.get_transform_at_distance(0.0, 0.0, 0.0)
	root.add_child(gantry)

	# Checkered finish strip flush on the road
	var strip := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(half_road * 2.0, 3.6)
	var strip_mat := StandardMaterial3D.new()
	strip_mat.albedo_texture = TextureFactory.make_checkered_texture()
	strip_mat.roughness = 0.65
	strip.mesh = plane
	strip.material_override = strip_mat
	strip.position = Vector3(0.0, 0.04, 0.0)
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gantry.add_child(strip)

	# Gantry steel pillars & overhead bridge
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.14, 0.16, 0.22)
	steel_mat.metallic = 0.6
	steel_mat.roughness = 0.35

	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = theme["barrier_accent"]
	accent_mat.emission_enabled = true
	accent_mat.emission = theme["barrier_accent"]
	accent_mat.emission_energy_multiplier = 1.4 if bool(theme["is_night"]) else 0.45

	var span := half_road + 2.8
	var h := 7.4
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var pbox := BoxMesh.new()
		pbox.size = Vector3(0.95, h, 1.1)
		pillar.mesh = pbox
		pillar.material_override = steel_mat
		pillar.position = Vector3(side * span, h * 0.5, 0.0)
		gantry.add_child(pillar)

	var beam := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(span * 2.0 + 1.2, 1.55, 1.45)
	beam.mesh = bbox
	beam.material_override = steel_mat
	beam.position = Vector3(0.0, h, 0.0)
	gantry.add_child(beam)

	var accent_strip := MeshInstance3D.new()
	var abox := BoxMesh.new()
	abox.size = Vector3(span * 2.0 + 1.25, 0.22, 1.52)
	accent_strip.mesh = abox
	accent_strip.material_override = accent_mat
	accent_strip.position = Vector3(0.0, h + 0.62, 0.0)
	gantry.add_child(accent_strip)

	# Dark rectangular F1 light-pod housing behind the 5 gantry bulbs for crisp contrast
	var pod_mat := StandardMaterial3D.new()
	pod_mat.albedo_color = Color(0.04, 0.05, 0.07)
	pod_mat.roughness = 0.72
	pod_mat.metallic = 0.20
	var light_pod := MeshInstance3D.new()
	var lp_box := BoxMesh.new()
	lp_box.size = Vector3(7.6, 1.05, 0.44)
	light_pod.mesh = lp_box
	light_pod.material_override = pod_mat
	light_pod.position = Vector3(0.0, h - 0.12, 0.62)
	gantry.add_child(light_pod)

	# 5 F1 Starting Lights mounted on front (+Z face toward grid behind start line!)
	var light_mats: Array[StandardMaterial3D] = []
	for i in range(5):
		var lx := (float(i) - 2.0) * 1.45
		var bulb := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.34
		sph.height = 0.68
		sph.radial_segments = 12
		sph.rings = 8
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.14, 0.02, 0.02)
		lmat.emission_enabled = true
		lmat.emission = Color(0.03, 0.0, 0.0)
		lmat.emission_energy_multiplier = 0.15
		bulb.mesh = sph
		bulb.material_override = lmat
		bulb.position = Vector3(lx, h - 0.12, 0.84)
		gantry.add_child(bulb)
		light_mats.append(lmat)

	return light_mats


static func _build_boost_pads(root: Node3D, spline: TrackSpline, fractions: Array) -> Dictionary:
	var areas: Array[Area3D] = []
	var distances := PackedFloat32Array()
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_texture = TextureFactory.make_boost_pad_texture()
	pad_mat.emission_enabled = true
	pad_mat.emission_texture = pad_mat.albedo_texture
	pad_mat.emission_energy_multiplier = 1.65
	pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for idx in range(fractions.size()):
		var frac := float(fractions[idx])
		var dist := frac * spline.total_length
		distances.append(dist)
		var xf := spline.get_transform_at_distance(dist, 0.0, 0.06)

		var pad := Node3D.new()
		pad.name = "BoostPad_%d" % idx
		pad.transform = xf
		root.add_child(pad)

		var mesh_inst := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(6.0, 11.0)
		mesh_inst.mesh = pm
		mesh_inst.material_override = pad_mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.add_child(mesh_inst)

		var area := Area3D.new()
		area.name = "BoostTrigger_%d" % idx
		area.collision_layer = 8 # Triggers
		area.collision_mask = 4  # Vehicles
		area.monitoring = true
		area.set_meta("is_boost_pad", true)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(6.4, 2.6, 11.0)
		cs.shape = box
		cs.position = Vector3(0.0, 1.2, 0.0)
		area.add_child(cs)
		pad.add_child(area)
		areas.append(area)

	return {"areas": areas, "distances": distances}


static func _build_corner_chevrons(root: Node3D, spline: TrackSpline, offset: float, is_night: bool) -> void:
	var n := spline.sample_count()
	var chev_mat := StandardMaterial3D.new()
	chev_mat.albedo_texture = TextureFactory.make_chevron_texture(is_night)
	if is_night:
		chev_mat.emission_enabled = true
		chev_mat.emission_texture = chev_mat.albedo_texture
		chev_mat.emission_energy_multiplier = 1.6

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.22, 0.24, 0.28)

	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(3.4, 1.35, 0.16)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.09
	post_mesh.bottom_radius = 0.09
	post_mesh.height = 2.0

	var i := 4
	while i < n - 4:
		var c := spline.curvatures[i]
		if absf(c) > 0.0085:
			# Place chevron on outside of curve (positive curv = left turn -> outside is RIGHT = +offset)
			var side := 1.0 if c > 0.0 else -1.0
			var dist := spline.cum_lengths[i]
			var xf := spline.get_transform_at_distance(dist, side * offset, 0.0)
			var sign_node := Node3D.new()
			sign_node.transform = xf
			# Angle sign slightly toward oncoming traffic
			sign_node.rotate_y(deg_to_rad(-28.0 * side))
			root.add_child(sign_node)

			var board := MeshInstance3D.new()
			board.mesh = board_mesh
			board.material_override = chev_mat
			board.position = Vector3(0.0, 1.75, 0.0)
			sign_node.add_child(board)

			var post := MeshInstance3D.new()
			post.mesh = post_mesh
			post.material_override = post_mat
			post.position = Vector3(0.0, 0.9, 0.0)
			sign_node.add_child(post)
			i += 6
		else:
			i += 2


static func _build_grandstands(root: Node3D, spline: TrackSpline, offset: float, theme: Dictionary) -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.68, 0.70, 0.74) if not bool(theme["is_night"]) else Color(0.18, 0.20, 0.28)
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = theme["barrier_accent"]
	if bool(theme["is_night"]):
		roof_mat.emission_enabled = true
		roof_mat.emission = theme["barrier_accent"]
		roof_mat.emission_energy_multiplier = 0.65

	var seat_colors := [Color(0.92, 0.22, 0.28), Color(0.18, 0.58, 0.94), Color(0.96, 0.78, 0.16)]
	var stand_dists := [spline.total_length - 36.0, 34.0]
	for idx in range(stand_dists.size()):
		var side := -1.0 if idx == 0 else 1.0
		var stand := Node3D.new()
		stand.transform = spline.get_transform_at_distance(stand_dists[idx], side * offset, 0.0)
		if side < 0.0:
			stand.rotate_y(PI)
		root.add_child(stand)

		# 3 tiered seating steps
		for tier in range(3):
			var step := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(2.4, 1.15, 28.0)
			step.mesh = b
			var sm := StandardMaterial3D.new()
			sm.albedo_color = seat_colors[tier % seat_colors.size()]
			step.material_override = sm
			step.position = Vector3(1.8 + float(tier) * 2.1, 0.6 + float(tier) * 1.15, 0.0)
			stand.add_child(step)

		var back := MeshInstance3D.new()
		var back_box := BoxMesh.new()
		back_box.size = Vector3(0.8, 6.2, 28.5)
		back.mesh = back_box
		back.material_override = concrete
		back.position = Vector3(7.6, 3.1, 0.0)
		stand.add_child(back)

		var canopy := MeshInstance3D.new()
		var roof_box := BoxMesh.new()
		roof_box.size = Vector3(8.5, 0.45, 29.0)
		canopy.mesh = roof_box
		canopy.material_override = roof_mat
		canopy.position = Vector3(4.2, 6.4, 0.0)
		stand.add_child(canopy)

		# Solid concrete foundation plinth extending down into the embankment skirt
		var plinth := MeshInstance3D.new()
		var pl_box := BoxMesh.new()
		pl_box.size = Vector3(7.8, 12.0, 28.4)
		plinth.mesh = pl_box
		plinth.material_override = concrete
		plinth.position = Vector3(4.2, -6.0, 0.0)
		stand.add_child(plinth)


static func _build_scenery(root: Node3D, spline: TrackSpline, barrier_offset: float, theme: Dictionary) -> void:
	var style: String = str(theme["tree_style"])
	var n := spline.sample_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + style.hash()

	# Shared low-poly meshes for fast GPU rendering (extended trunk base anchors deeply into embankment slopes)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.24
	trunk_mesh.bottom_radius = 0.46
	trunk_mesh.height = 6.2
	trunk_mesh.radial_segments = 6

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.36, 0.24, 0.16)

	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 2.6
	foliage_mesh.height = 3.8
	foliage_mesh.radial_segments = 7
	foliage_mesh.rings = 5

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.2
	cone_mesh.bottom_radius = 2.4
	cone_mesh.height = 6.2
	cone_mesh.radial_segments = 7

	var foliage_mats: Array[StandardMaterial3D] = []
	if style == "sakura":
		for col in [Color(0.98, 0.66, 0.78), Color(0.96, 0.52, 0.68), Color(0.24, 0.46, 0.26)]:
			var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.85
			foliage_mats.append(m)
	elif style == "palm_cypress":
		for col in [Color(0.18, 0.56, 0.26), Color(0.26, 0.64, 0.28), Color(0.14, 0.44, 0.24)]:
			var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.85
			foliage_mats.append(m)
	else:
		# Neon cyber city towers!
		for col in [Color(0.09, 0.11, 0.20), Color(0.12, 0.10, 0.24), Color(0.07, 0.12, 0.22)]:
			var m := StandardMaterial3D.new(); m.albedo_color = col; m.roughness = 0.45; m.metallic = 0.4
			foliage_mats.append(m)

	var neon_cyan := StandardMaterial3D.new()
	neon_cyan.albedo_color = Color(0.0, 0.95, 1.0)
	neon_cyan.emission_enabled = true
	neon_cyan.emission = Color(0.0, 0.95, 1.0)
	neon_cyan.emission_energy_multiplier = 2.0

	var neon_pink := StandardMaterial3D.new()
	neon_pink.albedo_color = Color(1.0, 0.18, 0.60)
	neon_pink.emission_enabled = true
	neon_pink.emission = Color(1.0, 0.18, 0.60)
	neon_pink.emission_energy_multiplier = 2.0

	# Place scenery props along track outside barriers (skip near grandstands)
	var outer_shoulder := barrier_offset + 0.35
	var skirt_width := 28.0
	var step := 6
	for i in range(0, n, step):
		var dist := spline.cum_lengths[i]
		if dist < 55.0 or dist > spline.total_length - 60.0:
			continue
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.68:
				continue
			var min_extra := 7.8 if style != "neon_towers" else 8.5
			var max_extra := 19.5 if style == "palm_cypress" else 23.5
			var lat: float = side * (barrier_offset + rng.randf_range(min_extra, max_extra))
			var candidate: Vector3 = spline.points[i] + spline.rights[i] * lat
			# Ensure prop doesn't encroach on another part of the circuit
			var nearest := spline.get_closest_index(candidate, i)
			if spline.points[nearest].distance_to(candidate) < barrier_offset + 6.8:
				continue

			# Exact elevation matching the 28m embankment skirt clamped at BaseWorldPlane (y = -12.0)
			var abs_lat := absf(lat)
			var inner_pt := spline.points[i] + spline.rights[i] * (side * outer_shoulder) + spline.ups[i] * (-0.05)
			var outer_y := minf(spline.points[i].y - 16.0, -13.5)
			var t_skirt := clampf((abs_lat - outer_shoulder) / skirt_width, 0.0, 1.0)
			var slope_y := lerpf(inner_pt.y, outer_y, t_skirt)
			var world_y := maxf(slope_y, -12.0)

			if style == "neon_towers":
				var h := rng.randf_range(16.0, 48.0)
				var w := rng.randf_range(7.0, 14.0)
				var top_y := world_y + h
				var bot_y := -13.0
				var total_h := maxf(top_y - bot_y, 10.0)
				var tower := MeshInstance3D.new()
				var tb := BoxMesh.new()
				tb.size = Vector3(w, total_h, w)
				tower.mesh = tb
				tower.material_override = foliage_mats[i % foliage_mats.size()]
				tower.position = Vector3(candidate.x, (top_y + bot_y) * 0.5, candidate.z)
				tower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(tower)

				# Glowing rooftop neon crown band
				var crown := MeshInstance3D.new()
				var cb := BoxMesh.new()
				cb.size = Vector3(w + 0.35, 0.85, w + 0.35)
				crown.mesh = cb
				crown.material_override = neon_cyan if (i % 12 == 0) else neon_pink
				crown.position = Vector3(0.0, total_h * 0.5 - 1.25, 0.0)
				tower.add_child(crown)
			else:
				# On coastal track, avoid planting trees out on the ocean plane
				if style == "palm_cypress" and slope_y < -11.4:
					continue
				var tree := Node3D.new()
				var s := rng.randf_range(0.85, 1.55)
				tree.position = Vector3(candidate.x, world_y - 0.6, candidate.z)
				tree.scale = Vector3.ONE * s
				root.add_child(tree)

				var tr := MeshInstance3D.new()
				tr.mesh = trunk_mesh
				tr.material_override = trunk_mat
				tr.position = Vector3(0.0, 1.1, 0.0)
				tr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				tree.add_child(tr)

				if style == "sakura":
					var is_cone := rng.randf() < 0.30
					var top := MeshInstance3D.new()
					if is_cone:
						# Evergreen cypress cones ONLY use green material
						top.mesh = cone_mesh
						top.material_override = foliage_mats[2]
						top.position = Vector3(0.0, 5.2, 0.0)
						top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tree.add_child(top)
					else:
						# Lush multi-puff pink cherry blossom canopy
						var p_idx := rng.randi() % 2
						top.mesh = foliage_mesh
						top.material_override = foliage_mats[p_idx]
						top.position = Vector3(0.0, 4.6, 0.0)
						top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tree.add_child(top)

						var puff1 := MeshInstance3D.new()
						puff1.mesh = foliage_mesh
						puff1.material_override = foliage_mats[(p_idx + 1) % 2]
						puff1.position = Vector3(1.32, 3.95, 0.62)
						puff1.scale = Vector3(0.76, 0.72, 0.76)
						puff1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tree.add_child(puff1)

						var puff2 := MeshInstance3D.new()
						puff2.mesh = foliage_mesh
						puff2.material_override = foliage_mats[p_idx]
						puff2.position = Vector3(-1.26, 4.10, -0.68)
						puff2.scale = Vector3(0.70, 0.68, 0.72)
						puff2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						tree.add_child(puff2)
				else:
					var top := MeshInstance3D.new()
					var is_cone := rng.randf() < 0.55
					top.mesh = cone_mesh if is_cone else foliage_mesh
					top.material_override = foliage_mats[rng.randi() % foliage_mats.size()]
					top.position = Vector3(0.0, 5.2 if is_cone else 4.6, 0.0)
					top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					tree.add_child(top)

	# Overhead Neon Light Arches on Neon Midnight Circuit!
	if bool(theme.get("has_neon_arches", false)):
		var arch_span := barrier_offset + 0.4
		for k in range(1, 14):
			var d := (float(k) / 14.0) * spline.total_length
			var arch := Node3D.new()
			arch.transform = spline.get_transform_at_distance(d, 0.0, 0.0)
			root.add_child(arch)
			var mat_use := neon_cyan if (k % 2 == 0) else neon_pink
			for side in [-1.0, 1.0]:
				var leg := MeshInstance3D.new()
				var lb := BoxMesh.new(); lb.size = Vector3(0.42, 7.6, 0.42)
				leg.mesh = lb; leg.material_override = mat_use
				leg.position = Vector3(side * arch_span, 3.8, 0.0)
				leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				arch.add_child(leg)
			var bar := MeshInstance3D.new()
			var bb := BoxMesh.new(); bb.size = Vector3(arch_span * 2.0 + 0.5, 0.45, 0.45)
			bar.mesh = bb; bar.material_override = mat_use
			bar.position = Vector3(0.0, 7.6, 0.0)
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			arch.add_child(bar)

	# Scenic Vermilion Torii Gates on Sakura Mountain Pass!
	if bool(theme.get("has_torii", false)):
		var torii_mat := StandardMaterial3D.new()
		torii_mat.albedo_color = Color(0.84, 0.16, 0.12)
		torii_mat.roughness = 0.55
		var dark_cap := StandardMaterial3D.new()
		dark_cap.albedo_color = Color(0.12, 0.11, 0.13)
		var span := barrier_offset + 0.6
		for frac in [0.22, 0.52, 0.78]:
			var gate := Node3D.new()
			gate.transform = spline.get_transform_at_distance(frac * spline.total_length, 0.0, 0.0)
			root.add_child(gate)
			for side in [-1.0, 1.0]:
				var col_m := MeshInstance3D.new()
				var cm := CylinderMesh.new(); cm.top_radius = 0.48; cm.bottom_radius = 0.58; cm.height = 9.0
				col_m.mesh = cm; col_m.material_override = torii_mat
				col_m.position = Vector3(side * span, 4.5, 0.0)
				gate.add_child(col_m)
			var lintel := MeshInstance3D.new()
			var lbox := BoxMesh.new(); lbox.size = Vector3(span * 2.0 + 4.2, 0.95, 1.0)
			lintel.mesh = lbox; lintel.material_override = torii_mat
			lintel.position = Vector3(0.0, 8.9, 0.0)
			gate.add_child(lintel)
			var cap := MeshInstance3D.new()
			var cbox := BoxMesh.new(); cbox.size = Vector3(span * 2.0 + 4.8, 0.42, 1.2)
			cap.mesh = cbox; cap.material_override = dark_cap
			cap.position = Vector3(0.0, 9.5, 0.0)
			gate.add_child(cap)
			var sub_bar := MeshInstance3D.new()
			var sbox := BoxMesh.new(); sbox.size = Vector3(span * 2.0 + 2.0, 0.65, 0.65)
			sub_bar.mesh = sbox; sub_bar.material_override = torii_mat
			sub_bar.position = Vector3(0.0, 7.2, 0.0)
			gate.add_child(sub_bar)

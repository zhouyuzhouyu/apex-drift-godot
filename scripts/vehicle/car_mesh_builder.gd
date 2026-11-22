class_name CarMeshBuilder
extends RefCounted

## Builds stylized multi-part 3D race cars (GT, Drift, Formula, Rally) and detailed wheels.
## Forward is -Z, Right is +X, Up is +Y (matching GEVP Vehicle convention).

static func build_car_visuals(parent: Node3D, style: String, livery: Dictionary, is_ghost: bool = false) -> Dictionary:
	for c in parent.get_children():
		c.queue_free()

	var paint_col: Color = livery.get("primary", Color(0.88, 0.12, 0.22))
	var accent_col: Color = livery.get("accent", Color(0.98, 0.98, 1.0))

	var body_mat := _make_mat(paint_col, 0.22, 0.45, is_ghost)
	var accent_mat := _make_mat(accent_col, 0.28, 0.30, is_ghost)
	var carbon_mat := _make_mat(Color(0.11, 0.12, 0.15), 0.55, 0.25, is_ghost)
	var glass_mat := _make_mat(Color(0.08, 0.14, 0.22), 0.08, 0.85, is_ghost)
	if not is_ghost:
		glass_mat.metallic = 0.85
		glass_mat.roughness = 0.10

	var headlight_mat := StandardMaterial3D.new()
	headlight_mat.albedo_color = Color(1.0, 0.98, 0.90)
	headlight_mat.emission_enabled = true
	headlight_mat.emission = Color(1.0, 0.96, 0.84)
	headlight_mat.emission_energy_multiplier = 2.6 if not is_ghost else 0.9
	if is_ghost:
		headlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		headlight_mat.albedo_color.a = 0.45

	var brake_mat := StandardMaterial3D.new()
	brake_mat.albedo_color = Color(0.85, 0.08, 0.12)
	brake_mat.emission_enabled = true
	brake_mat.emission = Color(1.0, 0.10, 0.12)
	brake_mat.emission_energy_multiplier = 1.0 if not is_ghost else 0.5
	if is_ghost:
		brake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		brake_mat.albedo_color.a = 0.45

	var exhaust_mat := _make_mat(Color(0.45, 0.48, 0.54), 0.3, 0.85, is_ghost)

	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(0.15, 0.82, 1.0, 0.85)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(0.10, 0.85, 1.0)
	flame_mat.emission_energy_multiplier = 4.5
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# 1. Sculpted Main Chassis Hull using multi-station lofted prism
	match style:
		"formula":
			_build_formula_body(parent, body_mat, accent_mat, carbon_mat, glass_mat, headlight_mat, brake_mat)
		"rally":
			_build_rally_body(parent, body_mat, accent_mat, carbon_mat, glass_mat, headlight_mat, brake_mat)
		"drift":
			_build_coupe_body(parent, body_mat, accent_mat, carbon_mat, glass_mat, headlight_mat, brake_mat, true)
		_:
			_build_coupe_body(parent, body_mat, accent_mat, carbon_mat, glass_mat, headlight_mat, brake_mat, false)

	# 2. Twin Exhaust Pipes & Nitro Flame Cones
	var nitro_flames: Array[MeshInstance3D] = []
	var ex_z := 2.04 if style != "rally" else 1.88
	var ex_offsets := [-0.36, 0.36] if style != "formula" else [-0.18, 0.18]
	for ox in ex_offsets:
		var pipe := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.065
		pm.bottom_radius = 0.075
		pm.height = 0.26
		pipe.mesh = pm
		pipe.material_override = exhaust_mat
		pipe.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		pipe.position = Vector3(ox, 0.36, ex_z)
		parent.add_child(pipe)

		var flame := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.008
		fm.bottom_radius = 0.09
		fm.height = 0.92
		fm.radial_segments = 8
		flame.mesh = fm
		flame.material_override = flame_mat
		flame.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		flame.position = Vector3(ox, 0.36, ex_z + 0.48)
		flame.visible = false
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(flame)

		var core := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.005
		cm.bottom_radius = 0.048
		cm.height = 0.56
		cm.radial_segments = 8
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.95, 0.98, 1.0)
		cmat.emission_enabled = true
		cmat.emission = Color(0.90, 0.96, 1.0)
		cmat.emission_energy_multiplier = 6.0
		cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core.mesh = cm
		core.material_override = cmat
		core.position = Vector3(0.0, -0.14, 0.0)
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.add_child(core)

		nitro_flames.append(flame)

	return {
		"brake_mat": brake_mat,
		"headlight_mat": headlight_mat,
		"nitro_flames": nitro_flames
	}


static func _build_coupe_body(
	parent: Node3D,
	body_mat: Material,
	accent_mat: Material,
	carbon_mat: Material,
	glass_mat: Material,
	headlight_mat: Material,
	brake_mat: Material,
	is_drift: bool
) -> void:
	# Lower sculpted fuselage stations: [z, half_width, y_bottom, y_top]
	var hull_stations := [
		[-2.08, 0.72, 0.30, 0.48],
		[-1.85, 0.88, 0.28, 0.64],
		[-1.05, 0.94, 0.27, 0.74],
		[ 0.95, 0.96, 0.27, 0.78],
		[ 1.85, 0.91, 0.30, 0.80],
		[ 2.04, 0.78, 0.36, 0.74]
	]
	_add_loft(parent, hull_stations, body_mat, "ChassisHull")

	# Sleek Cabin Canopy (glass + roof)
	var cabin_stations := [
		[-0.90, 0.74, 0.72, 0.75],
		[-0.42, 0.68, 0.72, 1.15],
		[ 0.45, 0.66, 0.73, 1.14],
		[ 1.24, 0.72, 0.75, 0.80]
	]
	_add_loft(parent, cabin_stations, glass_mat, "CabinCanopy")

	# Painted Roof Cap on top of canopy
	_add_box(parent, Vector3(1.22, 0.06, 0.88), Vector3(0.0, 1.15, 0.02), body_mat)

	# Central Racing Stripe flush along sloped hood, roof & rear deck
	var hood_stripe := _add_box(parent, Vector3(0.26, 0.025, 0.82), Vector3(0.0, 0.70, -1.36), accent_mat)
	hood_stripe.rotation_degrees = Vector3(-7.2, 0.0, 0.0)
	_add_box(parent, Vector3(0.26, 0.025, 0.90), Vector3(0.0, 1.185, 0.02), accent_mat)
	_add_box(parent, Vector3(0.26, 0.025, 0.62), Vector3(0.0, 0.798, 1.50), accent_mat)

	# Carbon Front Splitter, Side Skirts & Rear Diffuser
	_add_box(parent, Vector3(1.88, 0.06, 0.42), Vector3(0.0, 0.27, -1.96), carbon_mat)
	for side in [-1.0, 1.0]:
		var skirt_w := 0.14 if is_drift else 0.09
		_add_box(parent, Vector3(skirt_w, 0.09, 2.05), Vector3(side * 0.94, 0.28, 0.0), carbon_mat)
		# Flared widebody fenders for drift coupe
		if is_drift:
			_add_box(parent, Vector3(0.12, 0.26, 0.92), Vector3(side * 0.98, 0.52, -1.25), accent_mat)
			_add_box(parent, Vector3(0.14, 0.28, 0.98), Vector3(side * 0.99, 0.54, 1.25), accent_mat)
	_add_box(parent, Vector3(1.68, 0.16, 0.24), Vector3(0.0, 0.33, 1.98), carbon_mat)

	# Front Grille Intake
	_add_box(parent, Vector3(1.18, 0.18, 0.08), Vector3(0.0, 0.42, -2.07), carbon_mat)

	# Twin Sleek Headlights
	for side in [-1.0, 1.0]:
		var hl := _add_box(parent, Vector3(0.36, 0.10, 0.12), Vector3(side * 0.62, 0.56, -1.98), headlight_mat)
		hl.rotation_degrees = Vector3(0.0, side * 14.0, 0.0)

	# Full-Width Glowing LED Tail/Brake Light Bar
	_add_box(parent, Vector3(1.54, 0.09, 0.08), Vector3(0.0, 0.68, 2.02), brake_mat)

	# Rear GT Spoiler Wing
	var wing_h := 1.12 if is_drift else 1.02
	var wing_w := 1.96 if is_drift else 1.78
	_add_box(parent, Vector3(wing_w, 0.06, 0.30), Vector3(0.0, wing_h, 1.84), accent_mat if is_drift else carbon_mat)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.06, wing_h - 0.74, 0.24), Vector3(side * 0.52, 0.76 + (wing_h - 0.76) * 0.5, 1.82), carbon_mat)
		_add_box(parent, Vector3(0.05, 0.22, 0.36), Vector3(side * (wing_w * 0.5), wing_h, 1.84), body_mat)


static func _build_formula_body(
	parent: Node3D,
	body_mat: Material,
	accent_mat: Material,
	carbon_mat: Material,
	glass_mat: Material,
	headlight_mat: Material,
	brake_mat: Material
) -> void:
	# Tapered Formula Nose & Monocoque
	var mono_stations := [
		[-2.24, 0.24, 0.30, 0.44],
		[-1.50, 0.42, 0.28, 0.58],
		[-0.50, 0.54, 0.26, 0.78],
		[ 0.70, 0.56, 0.26, 0.90],
		[ 1.85, 0.46, 0.30, 0.76],
		[ 2.06, 0.30, 0.34, 0.62]
	]
	_add_loft(parent, mono_stations, body_mat, "FormulaMonocoque")

	# Sidepods left & right
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.46, 0.36, 1.75), Vector3(side * 0.64, 0.46, 0.35), body_mat)
		_add_box(parent, Vector3(0.42, 0.07, 1.65), Vector3(side * 0.64, 0.65, 0.35), accent_mat)
		_add_box(parent, Vector3(0.36, 0.24, 0.08), Vector3(side * 0.64, 0.46, -0.53), carbon_mat)

	# Low Floor & Wide Front Aero Wing
	_add_box(parent, Vector3(1.86, 0.05, 2.95), Vector3(0.0, 0.24, 0.15), carbon_mat)
	_add_box(parent, Vector3(1.94, 0.06, 0.34), Vector3(0.0, 0.30, -2.10), accent_mat)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.05, 0.22, 0.38), Vector3(side * 0.96, 0.38, -2.10), body_mat)

	# Cockpit Canopy + Roll Hoop + Racing Stripe
	_add_box(parent, Vector3(0.56, 0.26, 0.92), Vector3(0.0, 0.86, -0.10), glass_mat)
	_add_box(parent, Vector3(0.24, 0.34, 0.46), Vector3(0.0, 0.98, 0.48), accent_mat)
	_add_box(parent, Vector3(0.18, 0.03, 1.60), Vector3(0.0, 0.59, -1.28), accent_mat)

	# Dual Front LED Strips & Rear Rain/Brake Light
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.24, 0.06, 0.08), Vector3(side * 0.56, 0.52, -0.55), headlight_mat)
	_add_box(parent, Vector3(0.22, 0.18, 0.08), Vector3(0.0, 0.48, 2.07), brake_mat)

	# Massive Dual-Plane Rear Aero Wing
	_add_box(parent, Vector3(1.84, 0.06, 0.34), Vector3(0.0, 1.06, 1.92), carbon_mat)
	_add_box(parent, Vector3(1.82, 0.05, 0.24), Vector3(0.0, 1.18, 1.98), accent_mat)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.05, 0.62, 0.46), Vector3(side * 0.91, 0.94, 1.92), body_mat)


static func _build_rally_body(
	parent: Node3D,
	body_mat: Material,
	accent_mat: Material,
	carbon_mat: Material,
	glass_mat: Material,
	headlight_mat: Material,
	brake_mat: Material
) -> void:
	# Muscular Compact Rally Hatchback Hull
	var hull_stations := [
		[-1.92, 0.78, 0.32, 0.56],
		[-1.65, 0.92, 0.30, 0.76],
		[-0.95, 0.96, 0.30, 0.82],
		[ 1.45, 0.96, 0.30, 0.84],
		[ 1.88, 0.86, 0.36, 0.82]
	]
	_add_loft(parent, hull_stations, body_mat, "RallyHull")

	# Upright Rally Cabin
	var cabin_stations := [
		[-0.86, 0.80, 0.80, 0.84],
		[-0.36, 0.76, 0.80, 1.32],
		[ 1.05, 0.76, 0.80, 1.30],
		[ 1.72, 0.80, 0.82, 0.86]
	]
	_add_loft(parent, cabin_stations, glass_mat, "RallyCabin")

	# Roof cap + Roof Air Scoop + Rally Stripes
	_add_box(parent, Vector3(1.44, 0.07, 1.40), Vector3(0.0, 1.33, 0.34), body_mat)
	_add_box(parent, Vector3(0.38, 0.14, 0.46), Vector3(0.0, 1.41, -0.05), accent_mat)
	_add_box(parent, Vector3(0.32, 0.03, 0.95), Vector3(0.0, 0.81, -1.30), accent_mat)

	# Heavy Skidplate, Mudflaps & Wide Fender Flares
	_add_box(parent, Vector3(1.88, 0.10, 0.32), Vector3(0.0, 0.32, -1.86), carbon_mat)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.14, 0.30, 0.96), Vector3(side * 0.97, 0.56, -1.22), carbon_mat)
		_add_box(parent, Vector3(0.14, 0.30, 0.96), Vector3(side * 0.97, 0.56, 1.22), carbon_mat)
		# Red/accent mudflaps behind rear wheels
		_add_box(parent, Vector3(0.34, 0.24, 0.04), Vector3(side * 0.82, 0.30, 1.78), accent_mat)

	# Quad Rally Nose Spotlights + Main Headlights
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.34, 0.14, 0.10), Vector3(side * 0.64, 0.68, -1.88), headlight_mat)
		_add_box(parent, Vector3(0.18, 0.16, 0.14), Vector3(side * 0.26, 0.66, -1.94), headlight_mat)
		_add_box(parent, Vector3(0.18, 0.16, 0.14), Vector3(side * 0.10, 0.66, -1.96), headlight_mat)

	# Rear Rally Tail Lights & Boxy Roof Wing
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.42, 0.16, 0.08), Vector3(side * 0.60, 0.72, 1.88), brake_mat)
	_add_box(parent, Vector3(1.66, 0.08, 0.36), Vector3(0.0, 1.36, 1.66), accent_mat)
	for side in [-1.0, 1.0]:
		_add_box(parent, Vector3(0.07, 0.26, 0.40), Vector3(side * 0.80, 1.26, 1.66), body_mat)


static func build_wheel_visual(parent: Node3D, radius: float, width: float, rim_col: Color, is_ghost: bool = false) -> void:
	for c in parent.get_children():
		c.queue_free()

	var tire_mat := _make_mat(Color(0.11, 0.12, 0.14), 0.88, 0.05, is_ghost)
	var barrel_mat := _make_mat(rim_col.darkened(0.35), 0.35, 0.72, is_ghost)
	var spoke_mat := _make_mat(rim_col.lightened(0.35), 0.20, 0.88, is_ghost)
	var hub_mat := _make_mat(Color(0.95, 0.18, 0.24), 0.28, 0.65, is_ghost)

	# Rubber Tire Cylinder (rotated so axle is along X)
	var tire := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = radius
	tm.bottom_radius = radius
	tm.height = width
	tm.radial_segments = 20
	tire.mesh = tm
	tire.material_override = tire_mat
	tire.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	parent.add_child(tire)

	# Recessed Rim Barrel
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = radius * 0.68
	rm.bottom_radius = radius * 0.68
	rm.height = width + 0.012
	rm.radial_segments = 16
	rim.mesh = rm
	rim.material_override = barrel_mat
	rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	parent.add_child(rim)

	# 6 Crisp Bright Alloy Spokes so wheel spin is clearly visible!
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(width + 0.032, radius * 1.26, radius * 0.13)
	for s in range(3):
		var sp := MeshInstance3D.new()
		sp.mesh = spoke_mesh
		sp.material_override = spoke_mat
		sp.rotation_degrees = Vector3(float(s) * 60.0, 0.0, 0.0)
		parent.add_child(sp)

	# Center Racing Locknut Hub
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = radius * 0.19
	hm.bottom_radius = radius * 0.19
	hm.height = width + 0.044
	hm.radial_segments = 10
	hub.mesh = hm
	hub.material_override = hub_mat
	hub.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	parent.add_child(hub)


static func _make_mat(col: Color, rough: float, metal: float, is_ghost: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if is_ghost:
		m.albedo_color = Color(0.18, 0.88, 1.0, 0.34)
		m.emission_enabled = true
		m.emission = Color(0.10, 0.82, 1.0)
		m.emission_energy_multiplier = 0.85
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.25
	else:
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
	return m


static func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _add_loft(parent: Node3D, stations: Array, mat: Material, node_name: String) -> MeshInstance3D:
	# Builds a closed watertight lofted mesh across Z stations: [z, half_w, y_bot, y_top]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(stations.size() - 1):
		var a: Array = stations[i]
		var b: Array = stations[i + 1]
		var z0: float = a[0]; var w0: float = a[1]; var yb0: float = a[2]; var yt0: float = a[3]
		var z1: float = b[0]; var w1: float = b[1]; var yb1: float = b[2]; var yt1: float = b[3]

		var tl0 := Vector3(-w0, yt0, z0); var tr0 := Vector3(w0, yt0, z0)
		var bl0 := Vector3(-w0, yb0, z0); var br0 := Vector3(w0, yb0, z0)
		var tl1 := Vector3(-w1, yt1, z1); var tr1 := Vector3(w1, yt1, z1)
		var bl1 := Vector3(-w1, yb1, z1); var br1 := Vector3(w1, yb1, z1)

		# Top face (+Y)
		_emit_quad(st, tl1, tl0, tr0, tr1)
		# Bottom face (-Y)
		_emit_quad(st, bl0, bl1, br1, br0)
		# Left face (-X): clockwise viewed from -X is front-bottom -> front-top -> rear-top -> rear-bottom
		_emit_quad(st, bl0, tl0, tl1, bl1)
		# Right face (+X): clockwise viewed from +X is rear-bottom -> rear-top -> front-top -> front-bottom
		_emit_quad(st, br1, tr1, tr0, br0)

	# Front cap (-Z)
	var f: Array = stations[0]
	_emit_quad(st, Vector3(f[1], f[2], f[0]), Vector3(f[1], f[3], f[0]), Vector3(-f[1], f[3], f[0]), Vector3(-f[1], f[2], f[0]))
	# Rear cap (+Z)
	var r: Array = stations[stations.size() - 1]
	_emit_quad(st, Vector3(-r[1], r[2], r[0]), Vector3(-r[1], r[3], r[0]), Vector3(r[1], r[3], r[0]), Vector3(r[1], r[2], r[0]))

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _emit_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

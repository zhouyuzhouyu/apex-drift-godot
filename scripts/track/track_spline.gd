class_name TrackSpline
extends RefCounted

## Closed periodic Catmull-Rom 3D racing spline with uniform arc-length resampling,
## smooth banking, curvature computation, grid spawn calculation, and fast progress queries.

var points: PackedVector3Array = PackedVector3Array()
var tangents: PackedVector3Array = PackedVector3Array()
var rights: PackedVector3Array = PackedVector3Array()
var ups: PackedVector3Array = PackedVector3Array()
var curvatures: PackedFloat32Array = PackedFloat32Array()
var cum_lengths: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0
var road_width: float = 14.0
var bank_strength: float = 0.14


func build_from_control_points(ctrl: Array, p_road_width: float = 14.0, p_bank_strength: float = 0.14, sample_spacing: float = 3.0) -> void:
	road_width = p_road_width
	bank_strength = p_bank_strength
	var n_ctrl := ctrl.size()
	if n_ctrl < 4:
		push_error("TrackSpline requires at least 4 control points")
		return

	# Step 1: Dense Catmull-Rom oversampling
	var dense: Array[Vector3] = []
	var steps_per_seg := 32
	for i in range(n_ctrl):
		var p0: Vector3 = ctrl[(i - 1 + n_ctrl) % n_ctrl]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[(i + 1) % n_ctrl]
		var p3: Vector3 = ctrl[(i + 2) % n_ctrl]
		for s in range(steps_per_seg):
			var t := float(s) / float(steps_per_seg)
			dense.append(_catmull_rom(p0, p1, p2, p3, t))

	# Step 2: Cumulative length table on dense polyline
	var dense_n := dense.size()
	var dense_len := PackedFloat32Array()
	dense_len.resize(dense_n + 1)
	dense_len[0] = 0.0
	for i in range(dense_n):
		var nxt := dense[(i + 1) % dense_n]
		dense_len[i + 1] = dense_len[i] + dense[i].distance_to(nxt)
	total_length = dense_len[dense_n]

	# Step 3: Uniform arc-length resampling
	var count := maxi(64, int(round(total_length / sample_spacing)))
	var step := total_length / float(count)
	points.resize(count)
	cum_lengths.resize(count)
	var d_idx := 0
	for i in range(count):
		var target_d := float(i) * step
		cum_lengths[i] = target_d
		while d_idx < dense_n - 1 and dense_len[d_idx + 1] < target_d:
			d_idx += 1
		var seg_start := dense_len[d_idx]
		var seg_end := dense_len[d_idx + 1]
		var alpha := 0.0
		if seg_end > seg_start + 0.0001:
			alpha = clampf((target_d - seg_start) / (seg_end - seg_start), 0.0, 1.0)
		points[i] = dense[d_idx].lerp(dense[(d_idx + 1) % dense_n], alpha)

	# Step 4: Tangents and signed horizontal curvature
	tangents.resize(count)
	curvatures.resize(count)
	for i in range(count):
		var prev_p := points[(i - 1 + count) % count]
		var next_p := points[(i + 1) % count]
		tangents[i] = (next_p - prev_p).normalized()

	var raw_curv := PackedFloat32Array()
	raw_curv.resize(count)
	for i in range(count):
		var t_prev := tangents[(i - 2 + count) % count]
		var t_next := tangents[(i + 2) % count]
		var f_prev := Vector2(t_prev.x, t_prev.z).normalized()
		var f_next := Vector2(t_next.x, t_next.z).normalized()
		# Signed turn angle (+ = left turn in Godot XZ where -Z is forward, -X is left)
		var cross_y := f_prev.x * f_next.y - f_prev.y * f_next.x
		var dot_v := clampf(f_prev.dot(f_next), -1.0, 1.0)
		var angle := atan2(-cross_y, dot_v)
		raw_curv[i] = angle / maxf(step * 4.0, 0.1)

	# Smooth curvature for natural banking and AI speed profile
	for i in range(count):
		var acc := 0.0
		for k in range(-3, 4):
			acc += raw_curv[(i + k + count) % count]
		curvatures[i] = acc / 7.0

	# Step 5: Compute banked Right and Up vectors
	# Note: Right = forward.cross(UP), Up = right.cross(forward)
	rights.resize(count)
	ups.resize(count)
	for i in range(count):
		var fwd := tangents[i]
		var flat_right := fwd.cross(Vector3.UP).normalized()
		var flat_up := flat_right.cross(fwd).normalized()
		# Positive curvature = left turn -> bank inward (right side higher = roll around fwd)
		var bank_angle := clampf(curvatures[i] * bank_strength * 28.0, -deg_to_rad(6.5), deg_to_rad(6.5))
		var r := flat_right.rotated(fwd, -bank_angle).normalized()
		var u := r.cross(fwd).normalized()
		rights[i] = r
		ups[i] = u


static func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func sample_count() -> int:
	return points.size()


func get_closest_index(world_pos: Vector3, hint_idx: int = -1) -> int:
	var n := points.size()
	if n == 0:
		return 0
	var best_idx := 0
	var best_d2 := INF

	if hint_idx >= 0 and hint_idx < n:
		# Local window search first (~±24 samples = ±72m)
		for offset in range(-24, 25):
			var idx := (hint_idx + offset + n) % n
			var d2 := points[idx].distance_squared_to(world_pos)
			if d2 < best_d2:
				best_d2 = d2
				best_idx = idx
		if best_d2 < 900.0: # Within 30m -> trust local search
			return best_idx

	# Full scan fallback
	best_d2 = INF
	for i in range(n):
		var d2 := points[i].distance_squared_to(world_pos)
		if d2 < best_d2:
			best_d2 = d2
			best_idx = i
	return best_idx


func get_progress(world_pos: Vector3, hint_idx: int = -1) -> Dictionary:
	var n := points.size()
	var idx := get_closest_index(world_pos, hint_idx)
	var p := points[idx]
	var fwd := tangents[idx]
	var r := rights[idx]
	var u := ups[idx]
	var delta := world_pos - p
	var along := delta.dot(fwd)
	var lateral := delta.dot(r)
	var dist_along := fposmod(cum_lengths[idx] + along, total_length)
	return {
		"index": idx,
		"progress": dist_along / maxf(total_length, 1.0),
		"distance_along": dist_along,
		"lateral": lateral,
		"distance": delta.length(),
		"closest_point": p,
		"forward": fwd,
		"right": r,
		"up": u
	}


func get_index_at_distance(dist: float) -> int:
	var n := points.size()
	if n == 0:
		return 0
	var wrapped := fposmod(dist, total_length)
	var frac := wrapped / maxf(total_length, 1.0)
	return clampi(int(round(frac * float(n))) % n, 0, n - 1)


func get_transform_at_distance(dist: float, lateral_offset: float = 0.0, y_offset: float = 0.0) -> Transform3D:
	var n := points.size()
	var wrapped := fposmod(dist, total_length)
	var f_idx := (wrapped / maxf(total_length, 1.0)) * float(n)
	var i0 := int(floorf(f_idx)) % n
	var i1 := (i0 + 1) % n
	var t: float = f_idx - floorf(f_idx)

	var p := points[i0].lerp(points[i1], t)
	var fwd := tangents[i0].lerp(tangents[i1], t).normalized()
	var up := ups[i0].lerp(ups[i1], t).normalized()
	var right := fwd.cross(up).normalized()
	up = right.cross(fwd).normalized()

	var pos := p + right * lateral_offset + up * y_offset
	# GEVP vehicles face -Z forward, +X right, +Y up -> Basis(right, up, -fwd)
	var basis := Basis(right, up, -fwd).orthonormalized()
	return Transform3D(basis, pos)


func get_grid_transform(slot_index: int) -> Transform3D:
	# Staggered 2-column motorsport starting grid behind start/finish line (dist = 0)
	var row := slot_index / 2
	var col := slot_index % 2
	var lateral := -2.6 if col == 0 else 2.6
	var back_dist := 10.0 + float(row) * 9.5 + (3.2 if col == 1 else 0.0)
	var dist := fposmod(total_length - back_dist, total_length)
	return get_transform_at_distance(dist, lateral, 0.05)


func get_max_curvature_ahead(start_idx: int, min_ahead_m: float, max_ahead_m: float) -> float:
	var n := points.size()
	if n == 0:
		return 0.0
	var step := total_length / float(n)
	var i_min := maxi(1, int(min_ahead_m / step))
	var i_max := maxi(i_min + 1, int(max_ahead_m / step))
	var max_c := 0.0
	for k in range(i_min, i_max + 1):
		var c := absf(curvatures[(start_idx + k) % n])
		if c > max_c:
			max_c = c
	return max_c


func get_minimap_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	if n == 0:
		return out
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span := maxf(max_x - min_x, max_z - min_z)
	if span < 1.0:
		span = 1.0
	var ox := (span - (max_x - min_x)) * 0.5
	var oz := (span - (max_z - min_z)) * 0.5
	# Downsample to ~120 crisp vector points
	var stride := maxi(1, n / 120)
	var i := 0
	while i < n:
		var p := points[i]
		out.append(Vector2((p.x - min_x + ox) / span, (p.z - min_z + oz) / span))
		i += stride
	return out


func world_to_minimap(world_pos: Vector3) -> Vector2:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for p in points:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	var span := maxf(max_x - min_x, max_z - min_z)
	if span < 1.0:
		span = 1.0
	var ox := (span - (max_x - min_x)) * 0.5
	var oz := (span - (max_z - min_z)) * 0.5
	return Vector2((world_pos.x - min_x + ox) / span, (world_pos.z - min_z + oz) / span)


func validate_geometry() -> Dictionary:
	## Sanity-checks spline closure, max grade, and absence of road self-intersections.
	var n := points.size()
	var max_grade := 0.0
	var min_non_adj_dist := INF
	for i in range(n):
		var nxt := (i + 1) % n
		var d := points[nxt] - points[i]
		var horiz := Vector2(d.x, d.z).length()
		if horiz > 0.01:
			max_grade = maxf(max_grade, absf(d.y) / horiz)
		# Check non-adjacent points (> 25 samples away) don't come within road_width * 1.4
		for j in range(i + 26, n):
			var wrap_gap := mini(j - i, n - (j - i))
			if wrap_gap < 26:
				continue
			var sep := points[i].distance_to(points[j])
			if sep < min_non_adj_dist:
				min_non_adj_dist = sep
	return {
		"sample_count": n,
		"total_length": total_length,
		"max_grade": max_grade,
		"min_non_adjacent_sep": min_non_adj_dist,
		"is_valid": n >= 64 and max_grade < 0.22 and min_non_adj_dist > road_width * 1.6
	}

class_name TextureFactory
extends RefCounted

## Generates crisp procedural textures for tracks, kerbs, barriers, chevrons, and boost pads.

static var _cache: Dictionary = {}


static func make_asphalt_texture(base_col: Color, is_night: bool) -> ImageTexture:
	var key := "asphalt_%s_%s" % [base_col.to_html(false), str(is_night)]
	if _cache.has(key):
		return _cache[key]
	var w := 256
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 202601
	var edge_col := Color(0.0, 0.92, 1.0) if is_night else Color(0.95, 0.95, 0.96)
	var center_col := Color(1.0, 0.25, 0.62) if is_night else Color(0.95, 0.85, 0.25)

	for y in range(h):
		for x in range(w):
			var u := float(x) / float(w)
			var n := rng.randf_range(-0.032, 0.032)
			# Subtle dual racing tire wear grooves around u = 0.28 and u = 0.72
			var g1 := exp(-pow((u - 0.28) * 14.0, 2.0))
			var g2 := exp(-pow((u - 0.72) * 14.0, 2.0))
			var wear := (g1 + g2) * 0.045
			var col := Color(
				clampf(base_col.r + n - wear, 0.04, 1.0),
				clampf(base_col.g + n - wear, 0.04, 1.0),
				clampf(base_col.b + n - wear, 0.04, 1.0),
				1.0
			)
			# Crisp outer lane edge lines
			if (u > 0.028 and u < 0.055) or (u > 0.945 and u < 0.972):
				col = edge_col
			# Dashed centerline
			elif absf(u - 0.5) < 0.011 and (y % 64) < 34:
				col = center_col
			img.set_pixel(x, y, col)

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func make_kerb_texture(col_a: Color, col_b: Color) -> ImageTexture:
	var key := "kerb_%s_%s" % [col_a.to_html(false), col_b.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var w := 64
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var stripe := (y / 32) % 2 == 0
		var c := col_a if stripe else col_b
		for x in range(w):
			var u := float(x) / float(w)
			var shade := 1.0 - absf(u - 0.5) * 0.22
			img.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func make_shoulder_texture(base_col: Color) -> ImageTexture:
	var key := "shoulder_%s" % base_col.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8844
	for y in range(h):
		for x in range(w):
			var n := rng.randf_range(-0.055, 0.055)
			var stripe := sin(float(y) * 0.25) * 0.02
			img.set_pixel(x, y, Color(
				clampf(base_col.r + n + stripe, 0.02, 1.0),
				clampf(base_col.g + n + stripe, 0.02, 1.0),
				clampf(base_col.b + n + stripe, 0.02, 1.0),
				1.0
			))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func make_checkered_texture() -> ImageTexture:
	if _cache.has("checkered"):
		return _cache["checkered"]
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var cx := (x / 16) % 2
			var cy := (y / 16) % 2
			var col := Color(0.96, 0.96, 0.98) if ((cx + cy) % 2 == 0) else Color(0.08, 0.09, 0.12)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["checkered"] = tex
	return tex


static func make_barrier_texture(accent_col: Color) -> ImageTexture:
	var key := "barrier_%s" % accent_col.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := float(y) / float(h)
		for x in range(w):
			var panel := (x / 32) % 2 == 0
			var col := Color(0.76, 0.78, 0.82) if panel else Color(0.68, 0.70, 0.75)
			if v > 0.36 and v < 0.62:
				col = accent_col
			elif v < 0.12 or v > 0.88:
				col = Color(0.22, 0.24, 0.28)
			elif x % 32 < 2:
				col = col.darkened(0.28)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func make_chevron_texture(is_night: bool) -> ImageTexture:
	var key := "chevron_%s" % str(is_night)
	if _cache.has(key):
		return _cache[key]
	var w := 128
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bg := Color(0.08, 0.09, 0.14)
	var fg := Color(0.0, 0.95, 1.0) if is_night else Color(1.0, 0.82, 0.08)
	for y in range(h):
		var dy := absf(float(y) - 31.5)
		for x in range(w):
			var band := int(float(x) + dy * 1.15) % 40
			var is_arrow := band < 18 and y > 6 and y < h - 6
			img.set_pixel(x, y, fg if is_arrow else bg)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func make_boost_pad_texture() -> ImageTexture:
	if _cache.has("boost_pad"):
		return _cache["boost_pad"]
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var dx := absf(float(x) - 63.5)
			var chev := int(float(y) + dx * 1.1) % 64
			var col := Color(0.04, 0.10, 0.22, 0.92)
			if x < 8 or x >= w - 8:
				col = Color(0.0, 0.95, 1.0, 1.0)
			elif chev < 26 and dx < 52.0:
				var glow := 1.0 - float(chev) / 26.0
				col = Color(0.0, 0.85, 1.0).lerp(Color(1.0, 0.92, 0.35), glow * 0.7)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache["boost_pad"] = tex
	return tex

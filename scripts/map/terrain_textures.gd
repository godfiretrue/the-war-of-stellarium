class_name TerrainTextures
extends RefCounted
## Procedural terrain art, generated once and shared by every province.
##
## Each texture covers the whole world (WORLD_SIZE) and provinces sample it in
## world coordinates, so neighbouring provinces of the same terrain blend into
## one continuous landscape instead of looking like separate tiles.

const WORLD_SIZE := Vector2i(1152, 648)

static var _cache: Dictionary = {}


## "plains", "forest" or "mountain" for a province.
static func kind_for(province: ProvinceData) -> String:
	if province.terrain == Balance.Terrain.MOUNTAINS:
		return "mountain"
	if province.territory_type in ["Deep Forest", "Forest Coast", "Sacred Glade"]:
		return "forest"
	return "plains"


static func get_texture(kind: String) -> Texture2D:
	if _cache.has(kind):
		return _cache[kind]

	var texture: NoiseTexture2D
	match kind:
		"forest":
			texture = _make(WORLD_SIZE, 31, 0.016, FastNoiseLite.FRACTAL_FBM, 4, [
				[0.00, Color(0.08, 0.19, 0.10)],
				[0.45, Color(0.13, 0.28, 0.14)],
				[0.75, Color(0.19, 0.36, 0.18)],
				[1.00, Color(0.26, 0.42, 0.21)],
			])
		"mountain":
			texture = _make(WORLD_SIZE, 47, 0.022, FastNoiseLite.FRACTAL_FBM, 5, [
				[0.00, Color(0.30, 0.27, 0.24)],
				[0.40, Color(0.42, 0.38, 0.34)],
				[0.70, Color(0.54, 0.50, 0.45)],
				[1.00, Color(0.66, 0.63, 0.58)],
			])
		"ocean":
			texture = _make(Vector2i(1200, 760), 63, 0.006, FastNoiseLite.FRACTAL_FBM, 3, [
				[0.00, Color(0.03, 0.10, 0.20)],
				[0.55, Color(0.05, 0.17, 0.30)],
				[1.00, Color(0.09, 0.26, 0.40)],
			])
		_:
			texture = _make(WORLD_SIZE, 17, 0.013, FastNoiseLite.FRACTAL_FBM, 4, [
				[0.00, Color(0.28, 0.40, 0.19)],
				[0.40, Color(0.40, 0.54, 0.25)],
				[0.70, Color(0.54, 0.62, 0.31)],
				[1.00, Color(0.70, 0.68, 0.38)],
			])

	_cache[kind] = texture
	return texture


## stops: Array of [offset, Color].
static func _make(size: Vector2i, noise_seed: int, frequency: float, fractal: int, octaves: int, stops: Array) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_type = fractal
	noise.fractal_octaves = octaves

	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop: Array in stops:
		offsets.append(float(stop[0]))
		colors.append(stop[1] as Color)
	var ramp := Gradient.new()
	ramp.offsets = offsets
	ramp.colors = colors

	var texture := NoiseTexture2D.new()
	texture.width = size.x
	texture.height = size.y
	texture.noise = noise
	texture.color_ramp = ramp
	texture.seamless = false
	return texture

extends Control
## Static pixel starfield baked into one texture at startup.
##
## Star positions are stored normalised (0..1) so the field stretches with the
## authored canvas. A fixed seed keeps the sky identical between runs. Baking
## the stars avoids hundreds of per-frame draw calls: on the project's
## virtualised GPU that made the menu run at ~6 FPS with 170 circles.

@export var star_count: int = 170
@export var seed_value: int = 7
## Bake resolution matches the authored canvas, so stars land on whole pixels.
@export var bake_size: Vector2i = Vector2i(1152, 648)

var _texture: ImageTexture = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_texture = _bake_stars()
	resized.connect(queue_redraw)


## Build the sky once. One pixel per star, with a few brighter neighbours for
## the larger ones; the result is already pixel art, so no shader is needed.
func _bake_stars() -> ImageTexture:
	var image := Image.create(bake_size.x, bake_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _i in star_count:
		var tint := rng.randf()
		var x := mini(int(rng.randf() * float(bake_size.x)), bake_size.x - 1)
		var y := mini(int(rng.randf() * float(bake_size.y)), bake_size.y - 1)
		var radius := rng.randf_range(0.6, 1.7)
		var alpha := rng.randf_range(0.25, 0.85)
		var color := Color(0.75 + tint * 0.2, 0.82 + tint * 0.1, 1.0, alpha)
		_set_pixel_safe(image, x, y, color)
		if radius > 1.35:
			var edge := Color(color.r, color.g, color.b, alpha * 0.5)
			_set_pixel_safe(image, x - 1, y, edge)
			_set_pixel_safe(image, x + 1, y, edge)
			_set_pixel_safe(image, x, y - 1, edge)
			_set_pixel_safe(image, x, y + 1, edge)
	return ImageTexture.create_from_image(image)


func _set_pixel_safe(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < bake_size.x and y >= 0 and y < bake_size.y:
		image.set_pixel(x, y, color)


func _draw() -> void:
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)

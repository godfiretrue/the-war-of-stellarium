extends Control
## Soft twinkling starfield drawn in code (no textures needed).
##
## Star positions are stored normalised (0..1) so the field stretches with
## the window. A fixed seed keeps the sky identical between runs.

@export var star_count: int = 170
@export var seed_value: int = 7

var _stars: Array[Dictionary] = []
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for _i in star_count:
		var tint := rng.randf()
		_stars.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(0.6, 1.7),
			"base": rng.randf_range(0.25, 0.85),
			"speed": rng.randf_range(0.4, 1.6),
			"phase": rng.randf() * TAU,
			"color": Color(0.75 + tint * 0.2, 0.82 + tint * 0.1, 1.0),
		})
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for star: Dictionary in _stars:
		var twinkle := 0.7 + 0.3 * sin(_time * float(star["speed"]) + float(star["phase"]))
		var color: Color = star["color"]
		color.a = float(star["base"]) * twinkle
		var point: Vector2 = star["pos"]
		draw_circle(Vector2(point.x * size.x, point.y * size.y), float(star["radius"]), color)

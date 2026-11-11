extends RefCounted

## Tileable 3D cloud noise, built once per run and shared. R: billowy perlin-worley base, G: fine inverted worley.

const CT := preload("res://scripts/clouds/cloud_tuning.gd")

static var _texture: ImageTexture3D = null


static func get_texture() -> ImageTexture3D:
	if _texture == null:
		_texture = _build(CT.NOISE_SIZE)
	return _texture


static func _build(size: int) -> ImageTexture3D:
	var perlin := FastNoiseLite.new()
	perlin.noise_type = FastNoiseLite.TYPE_PERLIN
	perlin.frequency = 3.0 / size
	perlin.fractal_type = FastNoiseLite.FRACTAL_FBM
	perlin.fractal_octaves = 3
	perlin.seed = 7

	var worley := FastNoiseLite.new()
	worley.noise_type = FastNoiseLite.TYPE_CELLULAR
	worley.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	worley.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	worley.frequency = 4.0 / size
	worley.fractal_type = FastNoiseLite.FRACTAL_FBM
	worley.fractal_octaves = 2
	worley.seed = 13

	var fine := FastNoiseLite.new()
	fine.noise_type = FastNoiseLite.TYPE_CELLULAR
	fine.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	fine.frequency = 9.0 / size
	fine.fractal_type = FastNoiseLite.FRACTAL_FBM
	fine.fractal_octaves = 2
	fine.seed = 29

	var p_slices: Array[Image] = perlin.get_seamless_image_3d(size, size, size, false, 0.15)
	var w_slices: Array[Image] = worley.get_seamless_image_3d(size, size, size, true, 0.15)
	var f_slices: Array[Image] = fine.get_seamless_image_3d(size, size, size, true, 0.15)

	var slices: Array[Image] = []
	var count: int = size * size
	for z: int in size:
		var p: PackedByteArray = _luma(p_slices[z])
		var w: PackedByteArray = _luma(w_slices[z])
		var f: PackedByteArray = _luma(f_slices[z])
		var out := PackedByteArray()
		out.resize(count * 2)
		for i: int in count:
			# Perlin-worley: perlin pushed toward the billows of the inverted worley.
			var pv: float = p[i] / 255.0
			var wv: float = w[i] / 255.0
			var base: float = clampf(pv * 0.55 + wv * 0.65 - 0.1, 0.0, 1.0)
			out[i * 2] = int(base * 255.0)
			out[i * 2 + 1] = f[i]
		slices.append(Image.create_from_data(size, size, false, Image.FORMAT_RG8, out))

	var tex := ImageTexture3D.new()
	var err: Error = tex.create(Image.FORMAT_RG8, size, size, size, false, slices)
	if err != OK:
		push_error("[CloudNoise] ImageTexture3D.create failed (%d)" % err)
	return tex


static func _luma(img: Image) -> PackedByteArray:
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()

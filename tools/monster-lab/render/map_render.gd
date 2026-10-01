extends SceneTree
# Renders a map dump (map_dump.luau) from a few cameras.
#   godot --path . -s map_render.gd -- jobs.json
# jobs.json: [{ "json": path, "views": [{ "out", "w", "h", "pos": [x,y,z], "look": [x,y,z],
#              "fov", "flashlight": bool, "overview": bool }] }]

var _tex := {}
var _mats := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_run(jobs)

func _run(jobs: Array) -> void:
	await process_frame
	for job in jobs:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(job["json"]))
		for view in job["views"]:
			await _render(data, view)
	quit()

func _pattern(kind: String) -> ImageTexture:
	var key := "pat_" + kind
	if _tex.has(key):
		return _tex[key]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v := 1.0
			match kind:
				"Brick":
					var row := y / 16
					var off := 16 if row % 2 == 1 else 0
					if y % 16 < 2 or (x + off) % 32 < 2:
						v = 0.55
					else:
						v = 0.9 + 0.1 * sin(float(x * 7 + y * 13 + row * 31))
				"CeramicTiles":
					v = 0.62 if (x % 32 < 1 or y % 32 < 1) else 1.0
				"WoodPlanks":
					var plank := y / 16
					v = 0.72 if y % 16 < 1 else 0.88 + 0.12 * sin(float(x) * 0.15 + float(plank) * 2.1) * sin(float(x) * 0.023 + float(plank))
				"DiamondPlate":
					v = 0.75 if ((x + y) % 16 < 2 or (x - y + 256) % 16 < 2) else 1.0
				"Carpet":
					v = 0.92 + 0.08 * sin(float(x * 3 + y * 5))
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t

func _noise_tex(kind: String) -> Array:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	var alb := NoiseTexture2D.new()
	var nrm := NoiseTexture2D.new()
	alb.width = 256; alb.height = 256; alb.seamless = true
	nrm.width = 256; nrm.height = 256; nrm.seamless = true; nrm.as_normal_map = true
	var ramp := Gradient.new()
	match kind:
		"Marble":
			n.noise_type = FastNoiseLite.TYPE_PERLIN
			n.frequency = 0.012
			n.fractal_octaves = 5
			n.domain_warp_enabled = true
			n.domain_warp_amplitude = 40.0
			ramp.set_color(0, Color(0.8, 0.8, 0.8)); ramp.set_color(1, Color(1, 1, 1))
			for v in [0.32, 0.45, 0.58, 0.7]:
				ramp.add_point(v - 0.02, Color(1, 1, 1)); ramp.add_point(v, Color(0.7, 0.7, 0.72)); ramp.add_point(v + 0.015, Color(1, 1, 1))
			nrm.bump_strength = 1.0
		"Slate", "Basalt", "Rock":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.05
			ramp.set_color(0, Color(0.7, 0.7, 0.7)); ramp.set_color(1, Color(1, 1, 1))
			nrm.bump_strength = 6.0
		_:
			n.noise_type = FastNoiseLite.TYPE_PERLIN
			n.frequency = 0.08
			n.fractal_octaves = 4
			ramp.set_color(0, Color(0.82, 0.82, 0.82)); ramp.set_color(1, Color(1, 1, 1))
			nrm.bump_strength = 2.0
	alb.noise = n; alb.color_ramp = ramp
	nrm.noise = n
	_tex[kind] = [alb, nrm]
	return _tex[kind]

func _mat(p: Dictionary) -> StandardMaterial3D:
	var c := Color(p["color"][0], p["color"][1], p["color"][2])
	var mat: String = p["material"]
	var tr: float = p.get("transparency", 0.0)
	var refl: float = p.get("reflectance", 0.0)
	var key := "%s|%s|%.2f|%.2f" % [mat, c.to_html(), tr, refl]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic_specular = 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var pattern := ""
	var noise := ""
	var scale := 0.25
	match mat:
		"Neon":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c.lightened(0.2)
		"Brick":
			pattern = "Brick"; scale = 0.25; m.roughness = 0.9
		"CeramicTiles":
			pattern = "CeramicTiles"; scale = 0.25; m.roughness = 0.3
		"WoodPlanks":
			pattern = "WoodPlanks"; scale = 0.2; m.roughness = 0.7
		"DiamondPlate":
			pattern = "DiamondPlate"; scale = 0.4; m.roughness = 0.4; m.metallic = 0.5
		"Carpet":
			pattern = "Carpet"; scale = 1.0; m.roughness = 1.0
		"Marble":
			noise = "Marble"; scale = 0.1; m.roughness = 0.3; m.metallic_specular = 0.6
		"Slate", "Basalt", "Rock":
			noise = mat; scale = 0.2; m.roughness = 0.85
		"Concrete", "Plaster", "Pebble", "Sand", "Asphalt":
			noise = "Concrete"; scale = 0.15; m.roughness = 0.95; m.metallic_specular = 0.2
		"Fabric":
			noise = "Fabric"; scale = 0.5; m.roughness = 1.0; m.metallic_specular = 0.1
		"Wood":
			noise = "Wood"; scale = 0.3; m.roughness = 0.7
		"Metal", "CorrodedMetal", "Foil":
			m.metallic = 0.6; m.roughness = 0.45 if mat == "Metal" else 0.8
			if mat == "CorrodedMetal":
				noise = "Concrete"; scale = 0.3
		"Glass":
			m.roughness = 0.05; m.metallic_specular = 0.9
		"SmoothPlastic":
			m.roughness = 0.35
		_:
			m.roughness = 0.6
	if pattern != "":
		m.albedo_texture = _pattern(pattern)
		m.uv1_scale = Vector3(scale, scale, scale)
	elif noise != "":
		var t: Array = _noise_tex(noise)
		m.albedo_texture = t[0]
		m.normal_enabled = true
		m.normal_texture = t[1]
		m.normal_scale = 0.4
		m.uv1_scale = Vector3(scale, scale, scale)
	if refl > 0.0:
		m.roughness = min(m.roughness, 0.15)
		m.metallic = max(m.metallic, refl * 1.2)
	if tr > 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 1.0 - tr
	_mats[key] = m
	return m

var _boxes := {}
func _mesh_for(shape: String, s: Vector3) -> Array:
	# returns [mesh, local transform]
	match shape:
		"Ball":
			var sm := SphereMesh.new()
			var r: float = min(s.x, min(s.y, s.z)) / 2.0
			sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 16; sm.rings = 8
			return [sm, Transform3D.IDENTITY]
		"MeshSphere":
			var sm2 := SphereMesh.new()
			sm2.radius = 0.5; sm2.height = 1.0; sm2.radial_segments = 24; sm2.rings = 12
			return [sm2, Transform3D(Basis.from_scale(s), Vector3.ZERO)]
		"Cylinder":
			var cm := CylinderMesh.new()
			var rr: float = min(s.y, s.z) / 2.0
			cm.top_radius = rr; cm.bottom_radius = rr; cm.height = s.x; cm.radial_segments = 16
			return [cm, Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3.ZERO)]
		_:
			var bm := BoxMesh.new()
			bm.size = s
			return [bm, Transform3D.IDENTITY]

func _render(data: Dictionary, view: Dictionary) -> void:
	var vp := SubViewport.new()
	var ss := 2
	vp.size = Vector2i(int(view["w"]) * ss, int(view["h"]) * ss)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var overview: bool = view.get("overview", false)
	var L: Dictionary = data["lighting"]
	var fogc := Color(L["fog"][0], L["fog"][1], L["fog"][2])

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = fogc if not overview else Color(0.02, 0.02, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var amb := Color(L["ambient"][0], L["ambient"][1], L["ambient"][2])
	env.ambient_light_color = amb if not overview else amb.lightened(0.12)
	if view.get("inspect", false):
		env.ambient_light_color = amb.lightened(0.1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = pow(2.0, float(L["exposure"])) * float(view.get("exposure", 1.0))
	env.glow_enabled = true
	env.glow_intensity = 0.6 + float(L["bloom"]) * 0.4
	env.glow_hdr_threshold = 0.95
	if not overview and not view.get("inspect", false):
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_light_color = fogc
		env.fog_depth_begin = float(L["fogStart"])
		env.fog_depth_end = float(L["fogEnd"])
		env.fog_depth_curve = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var cam_pos := Vector3(view["pos"][0], view["pos"][1], view["pos"][2])
	var look := Vector3(view["look"][0], view["look"][1], view["look"][2])
	var ceil: float = data["ceiling"]
	for p in data["parts"]:
		var nm: String = p["name"]
		if overview and (nm.contains("Ceiling") or (p["cf"][1] > ceil - 1.5 and nm != "Bulb")):
			continue
		var s := Vector3(p["size"][0], p["size"][1], p["size"][2])
		var c: Array = p["cf"]
		var basis := Basis(Vector3(c[3], c[6], c[9]), Vector3(c[4], c[7], c[10]), Vector3(c[5], c[8], c[11]))
		var xf := Transform3D(basis, Vector3(c[0], c[1], c[2]))
		var mm: Array = _mesh_for(p["shape"], s)
		var mi := MeshInstance3D.new()
		mi.mesh = mm[0]
		mi.transform = xf * mm[1]
		mi.material_override = _mat(p)
		if not p.get("shadow", true) or p["material"] == "Neon":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)

	for t in data["texts"]:
		var lab := Label3D.new()
		var c: Array = t["cf"]
		var basis := Basis(Vector3(c[3], c[6], c[9]), Vector3(c[4], c[7], c[10]), Vector3(c[5], c[8], c[11]))
		lab.transform = Transform3D(basis, Vector3(c[0], c[1], c[2])) * Transform3D(Basis(), Vector3(0, 0, -0.06))
		lab.text = t["text"]
		lab.modulate = Color(t["color"][0], t["color"][1], t["color"][2])
		lab.shaded = not t["glow"]
		lab.double_sided = false
		lab.font_size = 64
		lab.outline_size = 0
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.width = float(t["size"][0]) / 0.004
		lab.pixel_size = 0.004 * clamp(float(t["size"][1]) / 1.2, 0.4, 3.0)
		lab.width = float(t["size"][0]) / lab.pixel_size
		lab.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(-float(t["rotation"])))
		world.add_child(lab)

	# lamps: shadows only for the ones nearest the camera
	var lights: Array = data["lights"].filter(func(l): return l["enabled"])
	lights.sort_custom(func(a, b): return Vector3(a["pos"][0], a["pos"][1], a["pos"][2]).distance_to(cam_pos) < Vector3(b["pos"][0], b["pos"][1], b["pos"][2]).distance_to(cam_pos))
	var i := 0
	for l in lights:
		var col := Color(l["color"][0], l["color"][1], l["color"][2])
		var pos := Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		var light: Light3D
		if l["kind"] == "SpotLight":
			var sl := SpotLight3D.new()
			sl.spot_range = float(l["range"])
			sl.spot_angle = float(l["angle"]) / 2.0
			sl.spot_attenuation = 0.6
			light = sl
			world.add_child(sl)
			sl.position = pos
			var d := Vector3(l["dir"][0], l["dir"][1], l["dir"][2])
			if d.length() > 0.1:
				sl.look_at(pos + d, Vector3.UP if abs(d.normalized().y) < 0.95 else Vector3.FORWARD)
		else:
			var ol := OmniLight3D.new()
			ol.omni_range = float(l["range"])
			ol.omni_attenuation = 0.55
			light = ol
			world.add_child(ol)
			ol.position = pos
		light.light_color = col
		light.light_energy = float(l["brightness"]) * float(view.get("lamp", 1.5))
		light.shadow_enabled = l["shadows"] and i < 10
		light.shadow_bias = 0.15
		light.shadow_normal_bias = 1.5
		i += 1

	var cam := Camera3D.new()
	cam.fov = float(view.get("fov", 70.0))
	cam.far = 1500.0
	world.add_child(cam)
	cam.position = cam_pos
	cam.look_at(cam_pos + look, Vector3.UP)
	cam.current = true

	if view.get("flashlight", false):
		var fl := SpotLight3D.new()
		fl.light_color = Color(1.0, 0.97, 0.9)
		fl.light_energy = 2.6 * 2.4
		fl.spot_range = 48.0
		fl.spot_angle = 23.0
		fl.spot_attenuation = 0.45
		fl.shadow_enabled = true
		cam.add_child(fl)
		fl.position = Vector3(0.4, -0.35, 0)
		var spill := SpotLight3D.new()
		spill.light_color = Color(1.0, 0.97, 0.9)
		spill.light_energy = 2.6 * 0.22 * 2.4
		spill.spot_range = 16.0
		spill.spot_angle = 55.0
		cam.add_child(spill)
	if overview:
		var moon := DirectionalLight3D.new()
		moon.light_energy = float(view.get("moon", 0.35))
		moon.light_color = Color(0.75, 0.8, 0.95)
		moon.rotation = Vector3(deg_to_rad(-60), deg_to_rad(30), 0)
		moon.shadow_enabled = true
		world.add_child(moon)

	for k in _tex:
		var tt = _tex[k]
		if tt is Array:
			for x in tt:
				if (x as NoiseTexture2D).get_image() == null:
					await (x as NoiseTexture2D).changed
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(int(view["w"]), int(view["h"]), Image.INTERPOLATE_LANCZOS)
	img.save_png(view["out"])
	print("saved ", view["out"])
	vp.queue_free()
	await process_frame

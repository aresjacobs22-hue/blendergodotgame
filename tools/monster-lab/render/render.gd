extends SceneTree
# Renders monster part dumps (from dump.luau) to PNGs.
#   godot --path . -s render.gd -- jobs.json
# jobs.json: [{ "json": path, "mood": "house", "shots": [{ "out": png, "view": "front|side|head|back", "w": px, "h": px }] }]

const MOODS = {
	"house": {"bg": Color(0.035, 0.035, 0.035), "amb": Color(0.10, 0.10, 0.10), "key": Color(1.0, 0.96, 0.9), "key_e": 2.6, "rim": Color(0.85, 0.88, 0.95), "rim_e": 5.0, "fill": Color(0.6, 0.6, 0.62), "fill_e": 0.45, "floor": Color(0.035, 0.035, 0.035), "floor_r": 0.7, "fog": Color(0.02, 0.02, 0.02)},
	"ward": {"bg": Color(0.06, 0.006, 0.006), "amb": Color(0.12, 0.02, 0.02), "key": Color(1.0, 0.9, 0.86), "key_e": 2.2, "rim": Color(1.0, 0.1, 0.06), "rim_e": 3.2, "fill": Color(1.0, 0.2, 0.15), "fill_e": 0.6, "floor": Color(0.09, 0.07, 0.07), "floor_r": 0.8, "fog": Color(0.12, 0.01, 0.01)},
	"sewer": {"bg": Color(0.012, 0.035, 0.028), "amb": Color(0.04, 0.09, 0.07), "key": Color(0.95, 1.0, 0.95), "key_e": 2.6, "rim": Color(0.35, 1.0, 0.7), "rim_e": 5.0, "fill": Color(0.3, 0.7, 0.55), "fill_e": 0.5, "floor": Color(0.07, 0.1, 0.08), "floor_r": 0.15, "fog": Color(0.02, 0.06, 0.045)},
	"atrium": {"bg": Color(0.2, 0.23, 0.29), "amb": Color(0.2, 0.22, 0.27), "key": Color(1.0, 0.98, 0.95), "key_e": 2.4, "rim": Color(0.7, 0.8, 1.0), "rim_e": 2.2, "fill": Color(0.6, 0.7, 0.9), "fill_e": 0.35, "floor": Color(0.42, 0.42, 0.41), "floor_r": 0.3, "fog": Color(0.25, 0.28, 0.34)},
	"void": {"bg": Color(0.035, 0.0, 0.06), "amb": Color(0.16, 0.08, 0.24), "key": Color(0.95, 0.9, 1.0), "key_e": 3.4, "rim": Color(0.75, 0.3, 1.0), "rim_e": 7.0, "fill": Color(0.6, 0.35, 1.0), "fill_e": 1.0, "floor": Color(0.05, 0.03, 0.07), "floor_r": 0.15, "fog": Color(0.05, 0.0, 0.09)},
}

var _tex := {}

func _noise_tex(kind: String) -> Array:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	var alb := NoiseTexture2D.new()
	var nrm := NoiseTexture2D.new()
	alb.width = 512; alb.height = 512; alb.seamless = true
	nrm.width = 512; nrm.height = 512; nrm.seamless = true; nrm.as_normal_map = true
	var ramp := Gradient.new()
	match kind:
		"Marble":
			n.noise_type = FastNoiseLite.TYPE_PERLIN
			n.frequency = 0.006
			n.fractal_octaves = 5
			n.domain_warp_enabled = true
			n.domain_warp_amplitude = 60.0
			ramp.set_color(0, Color(0.78, 0.78, 0.78)); ramp.set_color(1, Color(1, 1, 1))
			for v in [0.3, 0.42, 0.5, 0.61, 0.72]:
				ramp.add_point(v - 0.025, Color(1, 1, 1)); ramp.add_point(v, Color(0.66, 0.66, 0.68)); ramp.add_point(v + 0.02, Color(1, 1, 1))
			nrm.bump_strength = 1.0
		"Slate":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.03
			n.fractal_octaves = 3
			ramp.set_color(0, Color(0.7, 0.7, 0.7)); ramp.set_color(1, Color(1, 1, 1))
			nrm.bump_strength = 6.0
		"Fabric":
			n.noise_type = FastNoiseLite.TYPE_VALUE
			n.frequency = 0.25
			ramp.set_color(0, Color(0.85, 0.85, 0.85)); ramp.set_color(1, Color(1, 1, 1))
			nrm.bump_strength = 3.0
		_:
			n.noise_type = FastNoiseLite.TYPE_PERLIN
			n.frequency = 0.05
			ramp.set_color(0, Color(0.9, 0.9, 0.9)); ramp.set_color(1, Color(1, 1, 1))
			nrm.bump_strength = 1.5
	alb.noise = n; alb.color_ramp = ramp
	nrm.noise = n
	_tex[kind] = [alb, nrm]
	return _tex[kind]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_run(jobs)

func _run(jobs: Array) -> void:
	await process_frame
	for job in jobs:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(job["json"]))
		for shot in job["shots"]:
			await _render(data, job["mood"], shot)
	quit()

func _mat(p: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := Color(p["color"][0], p["color"][1], p["color"][2])
	m.albedo_color = c
	var mat: String = p["material"]
	match mat:
		"Neon":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c.lightened(0.25)
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 2.5
		"Slate":
			m.roughness = 0.88
			m.metallic_specular = 0.15
		"Marble":
			m.roughness = 0.32
			m.metallic_specular = 0.6
		"Plastic":
			m.roughness = 0.62
			m.metallic_specular = 0.35
		"Fabric":
			m.roughness = 0.95
			m.metallic_specular = 0.2
		"Concrete", "Rock", "Basalt":
			m.roughness = 0.95
		"Glass":
			m.roughness = 0.05
			m.metallic_specular = 0.9
		_:
			m.roughness = 0.42
	if mat in ["Marble", "Slate", "Fabric", "Plastic", "Concrete"]:
		var t: Array = _noise_tex(mat)
		m.albedo_texture = t[0]
		m.normal_enabled = true
		m.normal_texture = t[1]
		m.normal_scale = 0.35 if mat != "Slate" else 0.6
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3(0.22, 0.22, 0.22) if mat == "Marble" else Vector3(0.35, 0.35, 0.35)
	var refl: float = p.get("reflectance", 0.0)
	if refl > 0.0:
		m.roughness = min(m.roughness, 0.25)
		m.metallic = refl * 1.5
	var tr: float = p.get("transparency", 0.0)
	if tr > 0.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = 1.0 - tr
	return m

func _wedge_mesh() -> ArrayMesh:
	# Roblox WedgePart in a 1x1x1 box: full-height face at +Z, slope down to -Z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, -0.5, -0.5); var b := Vector3(0.5, -0.5, -0.5)
	var c := Vector3(-0.5, -0.5, 0.5); var d := Vector3(0.5, -0.5, 0.5)
	var e := Vector3(-0.5, 0.5, 0.5); var f := Vector3(0.5, 0.5, 0.5)
	for tri in [[a, b, d], [a, d, c], [c, d, f], [c, f, e], [a, e, f], [a, f, b], [a, c, e], [b, f, d]]:
		for v in tri:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func _build(root: Node3D, data: Dictionary) -> Array:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var head := Vector3.ZERO
	var head_size := 1.5
	var head_fwd := Vector3(0, 0, -1)
	for p in data["parts"]:
		var s := Vector3(p["size"][0], p["size"][1], p["size"][2])
		var c: Array = p["cf"]
		var basis := Basis(Vector3(c[3], c[6], c[9]), Vector3(c[4], c[7], c[10]), Vector3(c[5], c[8], c[11]))
		var xf := Transform3D(basis, Vector3(c[0], c[1], c[2]))
		var mi := MeshInstance3D.new()
		var shape: String = p["shape"]
		var mesh_xf := Transform3D.IDENTITY
		match shape:
			"Ball":
				var sm := SphereMesh.new()
				var r: float = min(s.x, min(s.y, s.z)) / 2.0
				sm.radius = r; sm.height = r * 2.0
				sm.radial_segments = 32; sm.rings = 16
				mi.mesh = sm
			"MeshSphere":
				var sm2 := SphereMesh.new()
				sm2.radius = 0.5; sm2.height = 1.0
				sm2.radial_segments = 40; sm2.rings = 20
				mi.mesh = sm2
				mesh_xf = Transform3D(Basis.from_scale(s), Vector3.ZERO)
			"Cylinder":
				var cm := CylinderMesh.new()
				var rr: float = min(s.y, s.z) / 2.0
				cm.top_radius = rr; cm.bottom_radius = rr; cm.height = s.x
				cm.radial_segments = 32
				mi.mesh = cm
				mesh_xf = Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3.ZERO)
			"Wedge":
				mi.mesh = _wedge_mesh()
				mesh_xf = Transform3D(Basis.from_scale(s), Vector3.ZERO)
			_:
				var bm := BoxMesh.new()
				bm.size = s
				mi.mesh = bm
		mi.transform = xf * mesh_xf
		mi.material_override = _mat(p)
		if not p.get("shadow", true) or p["material"] == "Neon":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var r2 := s.length() / 2.0
		lo = lo.min(xf.origin - Vector3(r2, r2, r2) * 0.6)
		hi = hi.max(xf.origin + Vector3(r2, r2, r2) * 0.6)
		if p["name"] == "Head" and head == Vector3.ZERO:
			head = xf.origin
			head_size = max(s.x, max(s.y, s.z))
			head_fwd = -basis.z
	for l in data["lights"]:
		var ol := OmniLight3D.new()
		ol.position = Vector3(l["pos"][0], l["pos"][1], l["pos"][2])
		ol.light_color = Color(l["color"][0], l["color"][1], l["color"][2])
		ol.omni_range = l["range"]
		ol.light_energy = l["brightness"] * 1.2
		root.add_child(ol)
	lo.y = max(lo.y, 0.0)
	return [lo, hi, head, head_size, head_fwd]

func _render(data: Dictionary, mood_name: String, shot: Dictionary) -> void:
	var mood: Dictionary = MOODS[mood_name]
	var ss := 2
	var vp := SubViewport.new()
	vp.size = Vector2i(int(shot["w"]) * ss, int(shot["h"]) * ss)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	root.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = mood["bg"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = mood["amb"]
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = mood["fog"]
	env.fog_density = 0.012
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var monster := Node3D.new()
	world.add_child(monster)
	var b: Array = _build(monster, data)
	var lo: Vector3 = b[0]; var hi: Vector3 = b[1]; var head: Vector3 = b[2]
	var center := (lo + hi) / 2.0
	var height: float = max(hi.y, 2.0)
	var extent: float = max(height, max(hi.x - lo.x, hi.z - lo.z) * 0.8)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = mood["floor"]
	fm.roughness = mood["floor_r"]
	floor_mi.material_override = fm
	world.add_child(floor_mi)

	var view: String = shot["view"]
	var cam := Camera3D.new()
	cam.fov = 34.0
	var yaw := deg_to_rad(-32.0)
	var target := Vector3(center.x, height * 0.5, center.z)
	var dist: float = extent * 1.9 + 3.0 + max(0.0, max(hi.x - lo.x, hi.z - lo.z) - height) * 0.9
	var cam_h := height * 0.42
	match view:
		"side":
			yaw = deg_to_rad(-90.0)
		"back":
			yaw = deg_to_rad(150.0)
		"head":
			var hf := Vector3(b[4].x, 0, b[4].z)
			if hf.length() < 0.2:
				hf = Vector3(0, 0, -1)
			hf = hf.normalized()
			yaw = atan2(hf.x, -hf.z) - deg_to_rad(22.0)
			target = head
			dist = float(b[3]) * 3.0 + 1.2
			cam_h = head.y + 0.15
			cam.fov = 32.0
		"low":
			yaw = deg_to_rad(-12.0)
			cam_h = 1.6
			dist = extent * 1.4 + 2.0
			target = Vector3(center.x, height * 0.62, center.z)
			cam.fov = 44.0
	var off := Vector3(sin(yaw), 0, -cos(yaw)) * dist
	world.add_child(cam)
	cam.position = Vector3(target.x + off.x, cam_h, target.z + off.z)
	cam.look_at(target, Vector3.UP)
	cam.current = true

	# key: a flashlight-ish spot from the camera side, high and to the left
	var key := SpotLight3D.new()
	key.light_color = mood["key"]
	key.light_energy = mood["key_e"] * 9.0
	key.spot_range = 80.0
	key.spot_angle = 30.0
	key.spot_attenuation = 1.0
	key.shadow_enabled = true
	key.shadow_bias = 0.35
	key.shadow_normal_bias = 4.0
	key.shadow_blur = 1.5
	var kp := Vector3(sin(yaw - 0.5), 0, -cos(yaw - 0.5)) * (extent * 1.6 + 6.0)
	key.position = Vector3(center.x + kp.x, height * 1.1 + 2.0, center.z + kp.z)
	world.add_child(key)
	key.look_at(Vector3(center.x, height * 0.5, center.z), Vector3.UP)
	# rim: behind, coloured by the night
	for sgn in [-1.0, 1.0]:
		var rim := SpotLight3D.new()
		rim.light_color = mood["rim"]
		rim.light_energy = mood["rim_e"] * 10.0
		rim.spot_range = 80.0
		rim.spot_angle = 35.0
		var rp := Vector3(sin(yaw + PI + sgn * 0.7), 0, -cos(yaw + PI + sgn * 0.7)) * (extent * 1.4 + 5.0)
		rim.position = Vector3(center.x + rp.x, height * 1.2 + 1.5, center.z + rp.z)
		world.add_child(rim)
		rim.look_at(Vector3(center.x, height * 0.55, center.z), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = mood["fill"]
	fill.light_energy = mood["fill_e"]
	fill.rotation = Vector3(deg_to_rad(-35), yaw + deg_to_rad(60), 0)
	world.add_child(fill)

	for i in 4:
		await process_frame
	for k in _tex:
		for t in _tex[k]:
			if (t as NoiseTexture2D).get_image() == null:
				await (t as NoiseTexture2D).changed
	for i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.resize(int(shot["w"]), int(shot["h"]), Image.INTERPOLATE_LANCZOS)
	img.save_png(shot["out"])
	print("saved ", shot["out"])
	vp.queue_free()
	await process_frame

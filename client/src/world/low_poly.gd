class_name LowPoly
extends RefCounted
## Petits utilitaires pour fabriquer des formes provisoires (en attendant les vrais modèles 2.5D).


static func material(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func mesh(m: Mesh, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material(color, emission)
	mi.position = pos
	return mi


static func box(size: Vector3, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh(b, color, pos)


static func cylinder(top: float, bottom: float, height: float, color: Color, pos := Vector3.ZERO, segments := 6) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return mesh(c, color, pos)


static func sphere(radius: float, color: Color, pos := Vector3.ZERO, emission := 0.0) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 8
	s.rings = 4
	return mesh(s, color, pos, emission)


static func capsule(radius: float, height: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 8
	c.rings = 2
	return mesh(c, color, pos)


static func tree(rng: RandomNumberGenerator, corrupted: bool) -> Node3D:
	var t := Node3D.new()
	var h := rng.randf_range(2.2, 3.6)
	t.add_child(cylinder(0.18, 0.25, h * 0.4, Color("5a3b2a"), Vector3(0, h * 0.2, 0)))
	var leaves := Color("6b3f86") if corrupted else Color("3f8a4a")
	t.add_child(cylinder(0.0, h * 0.35, h * 0.75, leaves, Vector3(0, h * 0.7, 0)))
	t.set_meta("leaves", t.get_child(1))
	return t


static func environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2238")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8a6c9")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	return we


static func sun() -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_color = Color("ffe2b8")
	light.light_energy = 1.0
	light.shadow_enabled = true
	return light

extends Node3D

class_name FuelStation

func _ready() -> void:
	_build_pad()
	_build_tanks()
	_build_pumps()

func _build_pad() -> void:
	var pad := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(18.0, 0.3, 10.0)
	pad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.35, 0.38)
	mat.roughness = 0.8
	pad.material_override = mat
	pad.position = Vector3(0, mesh.size.y * 0.5, 0)
	add_child(pad)

func _build_tanks() -> void:
	for i in range(2):
		var tank := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 1.4
		mesh.bottom_radius = 1.4
		mesh.height = 3.5
		tank.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.85, 0.9)
		mat.roughness = 0.4
		tank.material_override = mat
		var x_offset := -3.0 + float(i) * 3.0
		tank.position = Vector3(x_offset, mesh.height * 0.5 + 0.3, -1.0)
		add_child(tank)

func _build_pumps() -> void:
	for i in range(2):
		var pump := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 1.6, 0.7)
		pump.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.2, 0.2)
		mat.roughness = 0.4
		pump.material_override = mat
		var x_offset := -2.0 + float(i) * 2.0
		pump.position = Vector3(x_offset, mesh.size.y * 0.5 + 0.3, 2.0)
		add_child(pump)


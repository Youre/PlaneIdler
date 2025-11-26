extends Node3D

class_name ControlTower

func _ready() -> void:
	# Build a simple tower from primitive meshes so we don't rely
	# on external models. Everything is local to this node so the
	# scene can position the tower safely away from stands.
	_build_shaft()
	_build_cab()
	_build_roof()

func _build_shaft() -> void:
	var shaft := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4.0, 18.0, 4.0)
	shaft.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.75)
	mat.roughness = 0.7
	shaft.material_override = mat
	shaft.position = Vector3(0, mesh.size.y * 0.5, 0)
	add_child(shaft)

func _build_cab() -> void:
	var cab := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(7.0, 3.0, 7.0)
	cab.mesh = mesh
	var mat := StandardMaterial3D.new()
	# Slight blue tint for glassy feel.
	mat.albedo_color = Color(0.3, 0.5, 0.8)
	mat.metallic = 0.1
	mat.roughness = 0.3
	cab.material_override = mat
	cab.position = Vector3(0, 18.0 + mesh.size.y * 0.5, 0)
	add_child(cab)

func _build_roof() -> void:
	var roof := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(7.5, 0.8, 7.5)
	roof.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.2)
	mat.roughness = 0.4
	roof.material_override = mat
	roof.position = Vector3(0, 18.0 + 3.0 + mesh.size.y * 0.5, 0)
	add_child(roof)


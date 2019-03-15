extends Node

enum FILE_TYPE { TEXT, RESOURCE }

var YAML = preload("res://addons/godot-yaml/gdyaml.gdns").new()

func load_map(path : String) -> Map:
	var map := Map.new()
	var file = File.new()
	
	if not file.open(path, file.READ) == OK:
		print("Loader: failed to load ", path, ", return null")
		file.close()
		return null
	
	var y = 0
	while not file.eof_reached():
		var line = file.get_csv_line()
		for x in range(line.size()):
			var item = line[x].strip_edges().split("^")
			var base = item[0]
			var id = map.tile_set.find_tile_by_name(base)
			map.set_cell(x, y, id)
			if (item.size() == 2):
				var overlay_id = map.tile_set.find_tile_by_name("^" + item[1])
				map.overlay.set_cell(x, y, overlay_id)
		y += 1
	
	file.close()
	return map

func load_dir(path : String, file_type : int) -> Dictionary:
	var directory_data := _get_directory_data(path, [], file_type)
	var dict := {}
	
	for file_data in directory_data:
		match(file_type):
			FILE_TYPE.TEXT:
				dict[file_data.id] = YAML.parse(file_data.data)
			FILE_TYPE.RESOURCE:
				dict[file_data.id] = file_data.data
	return dict


func _get_directory_data(path : String, directory_data : Array, file_type : int) -> Array:
	
	var directory := Directory.new()
	
	if not directory.open(path) == OK:
		print("Loader: failed to load ", path, ", return [] (open)")
		return []
	
	if not directory.list_dir_begin(true, true) == OK:
		print("Loader: failed to load ", path, ", return [] (list_dir_begin)")
		return []
	
	var sub_path := ""
	
	while true:
		sub_path = directory.get_next()
		
		if sub_path == "." or sub_path == ".." or sub_path.begins_with("_"):
			continue
		
		elif sub_path == "":
			break
		
		elif directory.current_is_dir():
			directory_data = _get_directory_data(directory.get_current_dir() + "/" + sub_path, directory_data, file_type)
		
		else:
			if sub_path.ends_with(".import"):
				continue
			
			var file_data = _get_file_data(directory.get_current_dir() + "/" + sub_path, sub_path, file_type)
			directory_data.append(file_data)
	
	directory.list_dir_end()
	return directory_data

func _get_file_data(path : String, file_name : String, file_type : int) -> Dictionary:
	
	var file_data := {}
	var file_id := file_name.split(".")[0]
	
	match(file_type):
		
		FILE_TYPE.TEXT:
			
			var file := File.new()
		
			if not file.open(path, file.READ) == OK:
				print("Loader: failed to load file: ", path, ", return {}")
				file.close()
				return file_data
			
			print("Loader: load file: ", path)
			
			file_data = { 
				id = file_id,
				data = file.get_as_text()
			}
			
			file.close()
		
		FILE_TYPE.RESOURCE:
			
			print("Loader: load file: ", path)
			
			file_data = { 
				id = file_id,
				data = load(path)
			}
	
	return file_data
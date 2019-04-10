extends TileMap
class_name Map

const OFFSET := Vector2(36, 36)
const CELL_SIZE := Vector2(54, 72)

const DEFAULT_TERRAIN := "Gg"

var width := 0
var height := 0

var labels := []
var locations := {}
var grid: Grid = null
var ZOC_tiles := {}

var village_count := 0

onready var overlay := $Overlay as TileMap
onready var cover := $Cover as TileMap
onready var fog := $Fog as TileMap

onready var cover_tile: int = tile_set.find_tile_by_name("Xv")
onready var fog_tile: int = fog.tile_set.find_tile_by_name("XV")

onready var transitions := $Transitions as Transitions

onready var cell_selector := $CellSelector as Node2D

func _ready() -> void:
	_update_size()
	_initialize_locations()
	_initialize_grid()
	_initialize_border()
	_initialize_transitions()

	# So the initial size is also correct when first entering the editor.
	call_deferred("_update_size")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_cell: Vector2 = world_to_map(get_global_mouse_position())
		var loc: Location = get_location(mouse_cell)

		if loc:
			cell_selector.position = loc.position

func map_to_world_centered(cell: Vector2) -> Vector2:
	return map_to_world(cell) + OFFSET

func world_to_world_centered(cell: Vector2) -> Vector2:
	return map_to_world_centered(world_to_map(cell))

func find_path(start_loc: Location, end_loc: Location) -> Array:
	var loc_path := []
	var cell_path: Array = grid.find_path_by_cell(start_loc.cell, end_loc.cell)
	cell_path.pop_front()
	for cell in cell_path:
		loc_path.append(get_location(cell))

	return loc_path

func find_all_viewable_cells(unit: Unit) -> Dictionary:
	update_weight(unit)
	var paths := {}
	paths[unit.location] = []
	var cells := Hex.get_cells_in_range(unit.location.cell, unit.type.moves, width, height)
	cells.pop_front()
	cells.invert()
	for cell in cells:
		if paths.has(cell):
			continue
		var path: Array = find_path(unit.location, get_location(cell))
		if path.empty():
			continue
		var new_path := []
		var cost := 0
		for path_cell in path:
			var cell_cost = grid.astar.get_point_weight_scale(_flatten(path_cell.cell))
			if ZOC_tiles.has(path_cell):
				cell_cost = 1
			if cost + cell_cost > unit.type.moves:
				break

			cost += cell_cost
			new_path.append(path_cell)
			paths[path_cell] = new_path.duplicate(true)
			if ZOC_tiles.has(path_cell):
				var attack_path = new_path.duplicate(true)
				for enemey_cell in ZOC_tiles[path_cell]:
					if not paths.has(enemey_cell):
						attack_path.append(enemey_cell)
						paths[enemey_cell] = attack_path.duplicate(true)
						attack_path.pop_back()
				break
			if cost == unit.type.moves:
				break
	return paths

func update_terrain() -> void:
	_initialize_locations()
	_initialize_grid()
	_initialize_transitions()

func update_weight(unit: Unit) -> void:
	#for label in labels:
	#	remove_child(label)
	#labels.clear()
	for loc in ZOC_tiles.keys():
		grid.unblock_cell(loc.cell)
		for val in ZOC_tiles[loc]:
			grid.unblock_cell(val.cell)
	ZOC_tiles.clear()
	print("cell: " + String(unit.location.cell))
	for y in height:
		for x in width:
			var cell := Vector2(x, y)
			var id: int = _flatten(cell)
			var location: Location = locations[id]
			var cost: int = unit.get_movement_cost(location)

			var other_unit = location.unit
			if other_unit:
				if not other_unit.side.number == unit.side.number:
					cost = 1
					var current_cell := Vector2(cell.x, cell.y + 1)
					var next_cell := Vector2(cell.x, cell.y + 1)
					var neighbors: Array = Hex.get_neighbors(location.cell)
					for neighbor in neighbors:
						if not _is_cell_in_map(neighbor):
							continue
						if unit.location.cell == neighbor:
							continue
						grid.block_cell(neighbor)
						var new_neighbors = Hex.get_neighbors(neighbor)
						for new_neighbor in new_neighbors:
							if not _is_cell_in_map(new_neighbor):
								continue
							if new_neighbor in neighbors and not unit.location.cell == new_neighbor:
								continue
							if new_neighbor == location.cell:
								grid.astar.connect_points(_flatten(neighbor),_flatten(new_neighbor),false)
							elif get_location(new_neighbor) in ZOC_tiles.keys():
								if grid.astar.are_points_connected(_flatten(new_neighbor),_flatten(neighbor)):
									grid.astar.disconnect_points(_flatten(new_neighbor),_flatten(neighbor))
							else:
								grid.astar.connect_points(_flatten(new_neighbor),_flatten(neighbor),false)
						#print("zoc - " + String(current_cell))
						if ZOC_tiles.has(get_location(neighbor)):
							ZOC_tiles[get_location(neighbor)].append(location)
						else:
							ZOC_tiles[get_location(neighbor)] = [location]
			#print(cost)

			grid.astar.set_point_weight_scale(id, cost)
	#for loc in ZOC_tiles:
	#	var label : Label = Label.new()
	#	label.text = "ZOC"
	#	label.set_position(loc.position)
	#	labels.append(label)
	#	add_child(label)

func set_size(cell: Vector2) -> void:
	width = int(cell.x)
	height = int(cell.y)

	_initialize_locations()
	_initialize_grid()
	_initialize_border()

func set_tile(global_pos: Vector2, id: int):
	var cell: Vector2 = world_to_map(global_pos)

	if not _is_cell_in_map(cell):
		return

	if id == -1:
		set_cellv(cell, id)
		overlay.set_cellv(cell, id)
		_update_size()

		return

	var code: String = tile_set.tile_get_name(id)
	if code.begins_with("^"):
		overlay.set_cellv(cell, id)
		if get_cellv(cell) == -1:
			var grass_id: int = tile_set.find_tile_by_name(DEFAULT_TERRAIN)
			set_cellv(cell, grass_id)
	else:
		set_cellv(cell, id)
	_update_size()

func set_time_of_day(daytime: DayTime) -> void:
	# TODO: global shader not taking individual time areas into account...
	for loc in locations.values():
		loc.terrain.time_of_day = daytime

	var curr_tint: Vector3 = material.get_shader_param("delta")
	var next_tint: Vector3 = daytime.color_adjust

	if not curr_tint or curr_tint == next_tint :
		material.set_shader_param("delta", next_tint)
		return

	# TODO: can we use a tween?
	for i in range(1, 10):
		curr_tint = lerp(curr_tint, next_tint, 0.1)
		material.set_shader_param("delta", curr_tint)
		yield(get_tree().create_timer(0.01), "timeout")

func get_location(cell: Vector2) -> Location:
	if not _is_cell_in_map(cell):
		return null
	return locations[_flatten(cell)]

func get_map_string() -> String:
	var string := ""

	for y in height:
		for x in width:
			var id: int = _flatten(Vector2(x, y))
			if get_cell(x, y) == TileMap.INVALID_CELL:
				set_cell(x, y, tile_set.find_tile_by_name(DEFAULT_TERRAIN))
				overlay.set_cell(x, y, TileMap.INVALID_CELL)

			var code: String = tile_set.tile_get_name(get_cell(x, y))
			var overlay_code := ""

			var overlay_cell: int = overlay.get_cell(x, y)

			if overlay_cell != TileMap.INVALID_CELL:
				overlay_code = tile_set.tile_get_name(overlay_cell)
			if x < width - 1 and y < height - 1:
				string += code + overlay_code + ","
			else:
				string += code + overlay_code
		string += "\n"

	return string

func _initialize_locations() -> void:
	for y in height:
		for x in width:
			var cell := Vector2(x, y)
			var id: int = _flatten(cell)

			var base_code := ""
			var overlay_code := ""

			var location := Location.new()

			location.map = self

			if get_cellv(cell) == TileMap.INVALID_CELL:
				set_cellv(cell, tile_set.find_tile_by_name(DEFAULT_TERRAIN))
				overlay.set_cellv(cell, TileMap.INVALID_CELL)

			if overlay.get_cellv(cell) != TileMap.INVALID_CELL:
				overlay_code = tile_set.tile_get_name(overlay.get_cellv(cell))
				if overlay_code == "^Vh":
					village_count += 1

			cover.set_cellv(cell, cover_tile)
			fog.set_cellv(cell, fog_tile)

			base_code = tile_set.tile_get_name(get_cell(x, y))

			if overlay_code == "":
				location.terrain = Terrain.new([Registry.terrain[base_code]])
			else:
				location.terrain = Terrain.new([Registry.terrain[base_code], Registry.terrain[overlay_code]])

			location.id = id
			location.cell = Vector2(x, y)
			location.position = map_to_world_centered(cell)
			locations[id] = location

func _initialize_grid() -> void:
	grid = Grid.new(self, width, height)

func _update_size() -> void:
	if get_cell(0, 0) == -1:
		set_cell(0, 0, tile_set.find_tile_by_name(DEFAULT_TERRAIN))
	else:
		# Hack so 'get_used_rect()' returns a correct value when tiles are
		# removed. It will be fixed by GH-27080.
		var cell: int = get_cell(0, 0)
		set_cell(0, 0, 0 if cell == -1 else -1)
		set_cell(0, 0, cell)
	width = int(get_used_rect().size.x)
	height = int(get_used_rect().size.y)
	if width % 2 == 0:
		$MapBorder.rect_size =\
				map_to_world(Vector2(width, height)) + Vector2(18, 36)
	else:
		$MapBorder.rect_size =\
				map_to_world(Vector2(width, height)) + Vector2(18, 0)

func _initialize_border() -> void:
	var size := Vector2(width, height)
	print(size)
	$MapBorder.rect_size = map_to_world(size) + Vector2(18, 36)

func _initialize_transitions() -> void:
		transitions.update_transitions(self)

func _flatten(cell: Vector2) -> int:
	return int(cell.y)*int(width) + int(cell.x)

func _is_cell_in_map(cell: Vector2) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height

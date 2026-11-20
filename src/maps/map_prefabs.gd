class_name MapPrefabs
extends RefCounted
## Stock prefabs available in every map, plus lookup across stock and map-saved prefabs.
## A prefab is {"id", "name", "pieces": [piece dictionaries relative to a bottom-centre pivot]}
## and is placed as one grouped unit. Stock prefabs are plain catalogue pieces, so anything
## placed from them can be rebuilt by hand.

const STOCK_PREFIX: String = "stock_"


static func stock() -> Array[Dictionary]:
	return [
		{"id": "stock_doorway", "name": "Doorway with flanking walls", "pieces": [
			_p("wall_adobe", Vector3(-3.5, 0, 0), Vector3(4, 3, 0.4)),
			_p("doorway", Vector3(0, 0, 0), Vector3(3, 3, 0.4)),
			_p("wall_adobe", Vector3(3.5, 0, 0), Vector3(4, 3, 0.4)),
		]},
		{"id": "stock_stair_house", "name": "Covered stair entrance (6 m opening)", "pieces": stair_house()},
		{"id": "stock_stair_run", "name": "Stair run with landing", "pieces": [
			_p("stairs_stone", Vector3(0, 0, 2), Vector3(3, 1.5, 4)),
			_p("platform", Vector3(0, 0, -1.5), Vector3(3, 1.5, 3)),
		]},
		{"id": "stock_crate_stack", "name": "Crate stack", "pieces": [
			_p("crate_large", Vector3(-0.6, 0, 0), Vector3(2, 2, 2)),
			_p("crate", Vector3(1.0, 0, 0.4), Vector3(1.2, 1.2, 1.2)),
			_p("crate", Vector3(-0.6, 2, 0), Vector3(1.2, 1.2, 1.2)),
		]},
		{"id": "stock_market_row", "name": "Market row", "pieces": [
			_p("market_stall", Vector3(-2, 0, 0), Vector3(3, 2.6, 1.6)),
			_p("market_stall", Vector3(2, 0, 0), Vector3(3, 2.6, 1.6)),
			_p("barrel", Vector3(4.2, 0, 0.3), Vector3(0.7, 1.0, 0.7)),
		]},
	]


## Open-bottom entrance shell. Centre it over a shaft with its landing at +Z.
static func stair_house() -> Array[Dictionary]:
	var pieces: Array[Dictionary] = [
		_p("wall", Vector3(-3.3,0,0.3), Vector3(0.6,3.9,12.2)),
		_p("wall", Vector3(3.3,0,0.3), Vector3(0.6,3.9,12.2)),
		_p("roof", Vector3(0,3.9,-0.1), Vector3(7.8,0.35,14.2)),
		_p("wall", Vector3(0,2.7,6.225), Vector3(6,1.2,0.35)),
		_p("wall", Vector3(0,2.75,-5.625), Vector3(6,1.15,0.35)),
	]
	var finishes := ["mud_brick","mud_brick","slate","wood_dark","limewash"]
	for i in pieces.size():
		pieces[i]["material"] = finishes[i]
	return pieces


## Stock prefabs followed by the prefabs saved in [param doc].
static func all(doc: MapDocument) -> Array[Dictionary]:
	var list := stock()
	list.append_array(doc.prefabs)
	return list


static func find(doc: MapDocument, prefab_id: String) -> Dictionary:
	for entry: Dictionary in all(doc):
		if entry["id"] == prefab_id:
			return entry
	return {}


static func is_stock(prefab_id: String) -> bool:
	return prefab_id.begins_with(STOCK_PREFIX)


static func _p(type: String, position: Vector3, size: Vector3) -> Dictionary:
	return MapDocument.make_piece(type, position, 0.0, size)

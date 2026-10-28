extends Node
func _ready() -> void:
	var m = load("res://scenes/main_menu.tscn").instantiate()
	add_child(m)
	await get_tree().process_frame
	await get_tree().process_frame
	print("menu OK, dzieci: ", m.get_child_count())
	get_tree().quit()

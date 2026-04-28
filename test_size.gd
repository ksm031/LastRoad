extends SceneTree
func _init():
	var i1 = Image.load_from_file("d:/Git/LastRoad/Asset/Image/Character/watcher_idle_01.png")
	var d1 = Image.load_from_file("d:/Git/LastRoad/Asset/Image/Character/watcher_down_01.png")
	print("idle_01 size: ", i1.get_size())
	print("down_01 size: ", d1.get_size())
	quit()

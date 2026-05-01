extends SceneTree
func _init():
    var tex = ImageTexture.create_from_image(Image.create(1480, 920, false, Image.FORMAT_RGBA8))
    var scale = Vector2(1280.0 / (float(tex.get_width()) - 200.0), 720.0  / (float(tex.get_height()) - 200.0))
    print("Scale: ", scale)
    quit()

extends RefCounted

## 本地设置：音量、全屏、窗口尺寸。存 user://settings.cfg（一行一个 key=value）。

const PATH := "user://settings.cfg"
const SIZES := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

static var volume := 80      # 0-100，作用于 Master 总线
static var fullscreen := false
static var size := Vector2i(1280, 720)


static func load() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var kv := line.split("=", true, 1)
		if kv.size() != 2:
			continue
		var key := kv[0].strip_edges()
		var val := kv[1].strip_edges()
		match key:
			"volume": volume = clampi(int(val), 0, 100)
			"fullscreen": fullscreen = val == "1"
			"width", "height":
				var w := size.x
				var h := size.y
				if key == "width":
					w = int(val)
				else:
					h = int(val)
				size = Vector2i(w, h)


static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string("volume=%d\nfullscreen=%d\nwidth=%d\nheight=%d\n" % [
		volume, 1 if fullscreen else 0, size.x, size.y])


## 把当前设置套到引擎上。启动时和玩家改完都调一次。
static func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(volume) / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0)
	if DisplayServer.get_name() == "headless":
		return  # 无窗口环境改不了窗口，跳过
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		# 居中，别让窗口跑到屏幕外
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - size) / 2)

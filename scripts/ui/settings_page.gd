extends PanelContainer

## 设置页：音量、全屏、窗口尺寸。改完立刻生效并写盘，下次启动沿用。

signal closed

const GameSettings := preload("res://scripts/game/game_settings.gd")

@onready var _vol: HSlider = $Center/Card/Margin/Vb/VolRow/Vol
@onready var _vol_val: Label = $Center/Card/Margin/Vb/VolRow/VolVal
@onready var _fs: CheckButton = $Center/Card/Margin/Vb/FsRow/Fs
@onready var _res: OptionButton = $Center/Card/Margin/Vb/ResRow/Res
@onready var _close: Button = $Center/Card/Margin/Vb/CloseRow/CloseBtn


func _ready() -> void:
	for s in GameSettings.SIZES:
		_res.add_item("%d × %d" % [s.x, s.y])
	_vol.value_changed.connect(_on_volume)
	_fs.toggled.connect(_on_fullscreen)
	_res.item_selected.connect(_on_resolution)
	_close.pressed.connect(func() -> void:
		hide()
		closed.emit())


func open() -> void:
	GameSettings.load()
	_vol.set_value_no_signal(GameSettings.volume)
	_vol_val.text = str(GameSettings.volume)
	_fs.set_pressed_no_signal(GameSettings.fullscreen)
	_sync_res()
	show()


func _sync_res() -> void:
	var idx := 0
	for i in GameSettings.SIZES.size():
		if GameSettings.SIZES[i] == GameSettings.size:
			idx = i
	_res.select(idx)


func _on_volume(v: float) -> void:
	GameSettings.volume = int(v)
	_vol_val.text = str(GameSettings.volume)
	GameSettings.apply()
	GameSettings.save()


func _on_fullscreen(on: bool) -> void:
	GameSettings.fullscreen = on
	_res.disabled = on
	GameSettings.apply()
	GameSettings.save()


func _on_resolution(i: int) -> void:
	GameSettings.size = GameSettings.SIZES[i]
	GameSettings.apply()
	GameSettings.save()

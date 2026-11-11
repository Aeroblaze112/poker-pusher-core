extends RefCounted

## 音效入口：代码里的调用点都接好了，素材还没有——所以现在全是静默。
## 要出声：把 ogg / wav 丢进 assets/audio/，文件名对上 CUES 里的值即可，不用改代码。
## 音量走 Master 总线，设置页那个滑块已经在控制它。

const DIR := "res://assets/audio/"
const CUES := {
	"deal": "deal",       # 发牌
	"fix": "fix",         # 固定进构筑组
	"flip": "flip",       # 效果牌翻面 / 弃
	"draw": "draw",       # 摸牌
	"gain": "gain",       # 结算加分
	"win": "win",         # 获胜
	"lose": "lose",       # 未获胜
	"click": "click",     # 按钮
}

static var _streams := {}
static var _bgm: AudioStreamPlayer


## 播一个音效。素材不存在就安静返回，不报错也不留节点。
static func play(cue: String, volume_db := 0.0) -> void:
	var s := _load(cue)
	if s == null:
		return
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	if root == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## 背景音乐（同一时刻只有一首，换曲会顶掉上一首）
static func play_bgm(cue: String, volume_db := -8.0) -> void:
	var s := _load(cue)
	if s == null:
		return
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	if root == null:
		return
	if is_instance_valid(_bgm):
		_bgm.queue_free()
	_bgm = AudioStreamPlayer.new()
	_bgm.stream = s
	_bgm.volume_db = volume_db
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	root.add_child(_bgm)
	_bgm.play()


static func stop_bgm() -> void:
	if is_instance_valid(_bgm):
		_bgm.queue_free()
	_bgm = null


static func _load(cue: String) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue]
	var base: String = CUES.get(cue, cue)
	for ext in [".ogg", ".wav", ".mp3"]:
		var path: String = DIR + base + ext
		if ResourceLoader.exists(path):
			var s := load(path) as AudioStream
			_streams[cue] = s
			return s
	_streams[cue] = null   # 记下来，免得每次调用都去查文件系统
	return null

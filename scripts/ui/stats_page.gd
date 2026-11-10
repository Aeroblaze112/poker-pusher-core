extends PanelContainer

## 战绩页：累计场次 / 胜率 / 最佳分 + 最近若干局。数据由主控从 UserDB 取，这里只排版。

signal closed

const MAX_ROWS := 8

@onready var _who: Label = $Center/Card/Margin/Vb/Who
@onready var _summary: Label = $Center/Card/Margin/Vb/Summary
@onready var _history: VBoxContainer = $Center/Card/Margin/Vb/History
@onready var _close: Button = $Center/Card/Margin/Vb/CloseRow/CloseBtn


func _ready() -> void:
	_close.pressed.connect(func() -> void:
		hide()
		closed.emit())


func open(pname: String, stats: Dictionary) -> void:
	show()
	_who.text = "👤 %s" % pname
	# 历史里存的是 Unix 时间戳（UTC），显示前换算成本机时区
	var tz_off := int(Time.get_unix_time_from_datetime_dict(Time.get_datetime_dict_from_system()) - Time.get_unix_time_from_system())
	var games := int(stats.get("games", 0))
	var wins := int(stats.get("wins", 0))
	var rate := 0.0 if games == 0 else float(wins) / float(games) * 100.0
	_summary.text = "共 %d 场 · %d 胜 · 胜率 %.0f%% · 最佳 %d 分 · 最近 %d 分" % [
		games, wins, rate, int(stats.get("best", 0)), int(stats.get("last", 0))]
	for ch in _history.get_children():
		_history.remove_child(ch)
		ch.queue_free()
	var hist: Array = stats.get("history", [])
	if hist.is_empty():
		_history.add_child(_row("还没有记录，打一局就会有了", Color(0.70, 0.72, 0.66)))
		return
	var start: int = maxi(0, hist.size() - MAX_ROWS)
	for i in range(hist.size() - 1, start - 1, -1):
		var h: Dictionary = hist[i]
		var stamp := int(h.get("t", 0)) + tz_off
		var when := Time.get_datetime_string_from_unix_time(stamp, true).replace("T", " ")
		var won := int(h.get("w", 0)) == 1
		_history.add_child(_row("%s    %d 分    %s" % [when.substr(5, 11), int(h.get("s", 0)), "胜" if won else "负"],
			Color(0.85, 0.70, 0.32) if won else Color(0.80, 0.80, 0.76)))


func _row(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

class_name GameUI
extends RefCounted

## 界面构建 / 刷新 / 动画（纯表现层）
## 通过 game（主控制器）读取游戏状态，通过信号把玩家输入回传给控制器。

signal card_clicked(card: PCard, zone: String)
signal confirm_pressed
signal difficulty_chosen(key: String)
signal host_requested(port: int, pname: String)
signal join_requested(ip: String, port: int, pname: String)
signal start_net_requested
signal restart_requested
signal reconnect_requested
signal login_requested(pname: String, pwd: String)
signal register_requested(pname: String, pwd: String)
signal logout_requested

var game  # 主控制器（场景根 Control 节点），动态访问其状态字段
var player_count := 4     # 本局人数（构建布局前由控制器写入）

## 开局界面当前选中的人数（住在菜单场景里）
var selected_count: int:
	get:
		return _menu.selected_count if is_instance_valid(_menu) else 4

# ---- 控件引用 ----
var round_label: Label
var phase_label: Label
var joker_label: Label
var piles_label: Label
var prompt_label: Label
var log_view: RichTextLabel
var table_row: HBoxContainer
var hand_fan: Control           # 手牌扇形区
var joker_tex: TextureRect
var back_icon: TextureRect
var log_popup: PanelContainer   # 日志弹窗
var d2_popup: PanelContainer    # 弃牌堆2 查看弹窗
var d2_title: Label
var d2_flow: HFlowContainer
var rules_popup: PanelContainer    # 玩法说明页（首页入口打开，懒构建）
var confirm_btn: Button
var restart_btn: Button

var _menu                 # 开局菜单场景实例
var _reconnect_btn: Button

var _ring: Control             # 对手构筑框的环形区域
var _ring_center := Vector2.ZERO
var _ring_radii := Vector2.ZERO
var _strip_labels := {}        # idx -> 名字/总分标签（贴在各人构筑框外侧）
var _own_box: HBoxContainer    # 自己那条构筑框的落位容器
var _score_row_boxes: Array = []

var _tex_cache := {}
var _strips: Array = []         # 构筑框 [{idx, holder, pos, rot}]
var _score_rows: Array = []     # 记分板 [[name_label, score_label]]


# ============================== 贴图 ==============================
func load_tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


func card_tex(c: PCard) -> Texture2D:
	return load_tex("res://assets/ui/牌面/%s.png" % c.texture_name())


# ============================== 主题（赌场典雅：墨绿绒面 + 鎏金 + 象牙字） ==============================
const C_GOLD := Color(0.85, 0.70, 0.32)
const C_GOLD_DIM := Color(0.85, 0.70, 0.32, 0.45)
const C_IVORY := Color(0.95, 0.93, 0.86)
const C_MUTED := Color(0.70, 0.72, 0.66)
const C_PANEL := Color(0.045, 0.095, 0.075, 0.88)      # 深绿半透明面板
const C_BTN := Color(0.10, 0.17, 0.14, 0.95)
const C_BTN_HOVER := Color(0.17, 0.26, 0.21, 0.97)
const C_BTN_PRESS := Color(0.06, 0.11, 0.09, 0.97)
const C_ACCENT := Color(0.16, 0.42, 0.27, 0.97)        # 主行动按钮（墨绿）
const C_ACCENT_HOVER := Color(0.22, 0.52, 0.34, 0.98)


func _sb(bg: Color, border: Color, rad := 10, bw := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(rad)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


## 按钮四态统一上妆；accent = 主行动（确认/开始）
func style_button(b: Button, accent := false) -> void:
	var normal := C_ACCENT if accent else C_BTN
	var hover := C_ACCENT_HOVER if accent else C_BTN_HOVER
	b.add_theme_stylebox_override("normal", _sb(normal, C_GOLD_DIM, 9))
	b.add_theme_stylebox_override("hover", _sb(hover, C_GOLD, 9))
	b.add_theme_stylebox_override("pressed", _sb(C_BTN_PRESS, C_GOLD, 9))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.08, 0.10, 0.09, 0.6), Color(0.4, 0.4, 0.38, 0.3), 9))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", C_IVORY)
	b.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.8))
	b.add_theme_color_override("font_pressed_color", C_GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.48))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 深绿半透明 + 鎏金描边面板
func style_panel(p: PanelContainer, rad := 14) -> void:
	p.add_theme_stylebox_override("panel", _sb(C_PANEL, C_GOLD_DIM, rad))


## 卡牌按钮：去掉灰底按钮壳，只留牌面；悬停/选中描金边
func style_card_button(b: Button) -> void:
	var flat := StyleBoxEmpty.new()
	b.add_theme_stylebox_override("normal", flat)
	b.add_theme_stylebox_override("focus", flat)
	var hov := StyleBoxFlat.new()
	hov.bg_color = Color(1, 1, 1, 0.06)
	hov.border_color = C_GOLD_DIM
	hov.set_border_width_all(2)
	hov.set_corner_radius_all(10)
	b.add_theme_stylebox_override("hover", hov)
	var pr := StyleBoxFlat.new()
	pr.bg_color = Color(0.85, 0.70, 0.32, 0.16)
	pr.border_color = C_GOLD
	pr.set_border_width_all(3)
	pr.set_corner_radius_all(10)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", flat)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## 输入框：深底鎏金描边
func style_input(e: LineEdit) -> void:
	e.add_theme_stylebox_override("normal", _sb(Color(0.03, 0.07, 0.05, 0.9), C_GOLD_DIM, 8))
	e.add_theme_stylebox_override("focus", _sb(Color(0.05, 0.10, 0.08, 0.95), C_GOLD, 8))
	e.add_theme_stylebox_override("read_only", _sb(Color(0.05, 0.08, 0.07, 0.6), Color(0.4, 0.4, 0.38, 0.3), 8))
	e.add_theme_color_override("font_color", C_IVORY)
	e.add_theme_color_override("font_placeholder_color", C_MUTED)
	e.add_theme_color_override("caret_color", C_GOLD)


## 标题字：鎏金 + 柔和投影
func style_title(l: Label, size: int, color := C_GOLD) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)


# ============================== 构建 ==============================
func build() -> void:
	var board = (load("res://scenes/ui/board.tscn") as PackedScene).instantiate()
	game.add_child(board)
	board.bottom_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())  # 底栏不要黑框，手牌直接摆在桌布上

	# 场景里的控件挂到同名成员上，下面所有刷新逻辑照旧用这些字段
	round_label = board.round_label
	phase_label = board.phase_label
	joker_label = board.joker_label
	piles_label = board.piles_label
	prompt_label = board.prompt_label
	joker_tex = board.joker_tex
	back_icon = board.back_icon
	table_row = board.table_row
	hand_fan = board.hand_fan
	confirm_btn = board.confirm_btn
	restart_btn = board.restart_btn
	_reconnect_btn = board.reconnect_btn
	_ring = board.opp_ring
	_own_box = board.my_build_box

	board.log_pressed.connect(toggle_log)
	board.d2_pressed.connect(show_d2)
	board.confirm_pressed.connect(func() -> void: confirm_pressed.emit())
	board.restart_pressed.connect(func() -> void: restart_requested.emit())
	board.reconnect_pressed.connect(func() -> void: reconnect_requested.emit())

	# 对手构筑框随人数重建，你的构筑框固定摆在牌桌下沿
	build_strips()
	_make_build_strip(0, 1.0)

	_build_log_popup()
	_build_d2_popup()
	_build_start_menu()


func _build_log_popup() -> void:
	log_popup = PanelContainer.new()
	log_popup.visible = false
	style_panel(log_popup)
	log_popup.set_anchors_preset(Control.PRESET_CENTER)
	log_popup.offset_left = -400
	log_popup.offset_top = -250
	log_popup.offset_right = 400
	log_popup.offset_bottom = 250
	var lp_vb := VBoxContainer.new()
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = false
	log_view.scroll_following = true
	log_view.add_theme_color_override("default_color", C_IVORY)
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lp_vb.add_child(log_view)
	var lp_close := Button.new()
	lp_close.text = "关闭"
	style_button(lp_close)
	lp_close.pressed.connect(func() -> void: log_popup.hide())
	lp_vb.add_child(lp_close)
	log_popup.add_child(lp_vb)
	game.add_child(log_popup)


func _build_d2_popup() -> void:
	d2_popup = PanelContainer.new()
	d2_popup.visible = false
	d2_popup.set_anchors_preset(Control.PRESET_CENTER)
	d2_popup.offset_left = -380
	d2_popup.offset_top = -220
	d2_popup.offset_right = 380
	d2_popup.offset_bottom = 220
	var d2_vb := VBoxContainer.new()
	d2_title = Label.new()
	d2_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_title(d2_title, 18, C_IVORY)
	d2_vb.add_child(d2_title)
	var d2_scroll := ScrollContainer.new()
	d2_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d2_flow = HFlowContainer.new()
	d2_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d2_scroll.add_child(d2_flow)
	d2_vb.add_child(d2_scroll)
	var d2_close := Button.new()
	d2_close.text = "关闭"
	style_button(d2_close)
	d2_close.pressed.connect(func() -> void: d2_popup.hide())
	d2_vb.add_child(d2_close)
	d2_popup.add_child(d2_vb)
	style_panel(d2_popup)
	game.add_child(d2_popup)


## 开局菜单：画面在 start_menu.tscn 里，这里只实例化 + 把信号转给控制器
func _build_start_menu() -> void:
	_menu = (load("res://scenes/ui/start_menu.tscn") as PackedScene).instantiate()
	game.add_child(_menu)
	_menu.difficulty_chosen.connect(difficulty_chosen.emit)
	_menu.login_requested.connect(login_requested.emit)
	_menu.register_requested.connect(register_requested.emit)
	_menu.logout_requested.connect(logout_requested.emit)
	_menu.host_requested.connect(host_requested.emit)
	_menu.join_requested.connect(join_requested.emit)
	_menu.start_net_requested.connect(start_net_requested.emit)
	_menu.rules_requested.connect(show_rules)


## 账户状态、联机大厅这些都住在菜单场景里，这里只做转发
func set_account(pname: String, stats: Dictionary) -> void:
	if is_instance_valid(_menu):
		_menu.set_account(pname, stats)


func set_account_status(t: String) -> void:
	if is_instance_valid(_menu):
		_menu.set_account_status(t)


# ============================== 构筑框 ==============================
## 对手构筑框：围着牌桌排一圈，180° 在左、270° 在上、360° 在右。
## 人越少铺得越开，人越多越往两侧压；越靠上（离自己越远）整体越小。
func build_strips() -> void:
	# 只重建对手框：主视角框（idx 0，在 build() 里单独创建）不能一起销毁
	for i in range(_strips.size() - 1, -1, -1):
		var e: Dictionary = _strips[i]
		if e.idx == 0:
			continue
		e.holder.get_parent().remove_child(e.holder)
		e.holder.queue_free()
		_strips.remove_at(i)
		if _strip_labels.has(e.idx):
			var lab: Label = _strip_labels[e.idx]
			lab.get_parent().remove_child(lab)
			lab.queue_free()
			_strip_labels.erase(e.idx)
	var opponents := player_count - 1
	if opponents <= 0:
		return
	var area := _ring.size
	if area.x < 10.0:  # 场景还没布局完成时按设计尺寸算
		area = Vector2(1280, 486)
	_ring_center = area * 0.5
	_ring_radii = area * 0.5
	# 每个模式一套摆位，不共用公式：桌子形状不一样，位置就该各写各的
	var seats: Array
	match player_count:
		2: seats = _seats_for_two()
		5: seats = _seats_for_five()
		6: seats = _seats_for_six()
		_: seats = _seats_for_four()
	for i in seats.size():
		var s: Array = seats[i]
		_make_build_strip(1 + i, s[2], s[0], s[1])


## 每个座位：[落点, 旋转弧度, 缩放]，坐标按 1280×486 的牌桌区手摆
## 2 人：对手正对面
func _seats_for_two() -> Array:
	return [
		[Vector2(640, 140), 0.0, 0.96],
	]


## 4 人：对面 + 左右两侧侧坐
func _seats_for_four() -> Array:
	return [
		[Vector2(126, 272), PI / 2.0, 0.84],
		[Vector2(640, 64), 0.0, 0.90],
		[Vector2(1154, 272), -PI / 2.0, 0.84],
	]


## 5 人：对面空着，四个对手压在两侧
func _seats_for_five() -> Array:
	return [
		[Vector2(146, 300), PI / 2.0, 0.78],
		[Vector2(372, 158), -PI / 6.0, 0.62],
		[Vector2(908, 158), PI / 6.0, 0.62],
		[Vector2(1134, 300), -PI / 2.0, 0.78],
	]


## 6 人：六边形，自己在底边中点，五个对手占另外五个角
func _seats_for_six() -> Array:
	return [
		[Vector2(197, 408), -PI / 6.0, 0.66],
		[Vector2(197, 194), PI / 6.0, 0.66],
		[Vector2(640, 88), 0.0, 0.66],
		[Vector2(1083, 194), -PI / 6.0, 0.66],
		[Vector2(1083, 408), PI / 6.0, 0.66],
	]


## 人数变化时重建对手构筑框（联机开局 / 单机选人数）
func set_player_count(n: int) -> void:
	if n == player_count and not _strips.is_empty():
		return
	player_count = n
	build_strips()
	refresh_build_strips()


## 构筑框：场景实例。给了 pos 就走环形摆位，不给就交给容器（主视角那条）
func _make_build_strip(idx: int, s: float, pos := Vector2.INF, rot := 0.0) -> Control:
	var holder: Control = (load("res://scenes/ui/build_strip.tscn") as PackedScene).instantiate()
	holder.setup(idx, s)
	_strips.append({idx = idx, holder = holder, pos = pos, rot = rot, s = s})
	if pos == Vector2.INF:
		_own_box.add_child(holder)
	else:
		_ring.add_child(holder)
		_place_ring(holder, pos, rot)
	return holder


## 环形摆位：枢轴放中心，转完中心正好落在 pos
func _place_ring(holder: Control, pos: Vector2, rot: float) -> void:
	var size := holder.custom_minimum_size
	holder.pivot_offset = size * 0.5
	holder.rotation = rot
	holder.position = pos - size * 0.5


func _mini_card_tex(c: PCard) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.texture = card_tex(c)
	t.custom_minimum_size = Vector2(40, 56)
	t.pivot_offset = Vector2(20, 28)
	_add_hover(t)
	return t


## 鼠标悬停放大动画（除主视角构筑牌外通用）
func _add_hover(c: Control, max_scale := 1.18) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_entered.connect(func() -> void:
		c.z_index = 50
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(max_scale, max_scale), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	c.mouse_exited.connect(func() -> void:
		c.z_index = 0
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2.ONE, 0.12))


func refresh_build_strips() -> void:
	if game.SIM or game.players.is_empty():
		return
	for e in _strips:
		var strip: Control = e.holder
		var idx: int = e.idx
		strip.refresh(game.players[idx] if idx < game.players.size() else null)
		if e.pos != Vector2.INF:  # 尺寸变了要重新摆位，转轴才对得上
			_place_ring(strip, e.pos, e.rot)
	_layout_strip_labels()


## 每人一块分板：名字 + 总分贴在各自构筑框的外侧，不跟着框旋转
func _strip_label(idx: int) -> Label:
	if _strip_labels.has(idx):
		return _strip_labels[idx]
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", C_IVORY)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.z_index = 20
	_ring.add_child(l)
	_strip_labels[idx] = l
	return l


func _layout_strip_labels() -> void:
	var ring_rect := Rect2(Vector2.ZERO, _ring.size)
	for e in _strips:
		var idx: int = e.idx
		var lab := _strip_label(idx)
		var p: PPlayer = game.players[idx] if idx < game.players.size() else null
		if p == null:
			lab.visible = false
			continue
		lab.visible = true
		lab.text = "%s%s%s  %d" % [p.pname,
			" ［离线］" if p.dropped else "",
			" ［终局］" if p.j_emptied else "", p.score]
		lab.add_theme_color_override("font_color", C_GOLD if idx == 0 else C_IVORY)
		var holder: Control = e.holder
		var mid: Vector2
		if e.pos != Vector2.INF:
			mid = e.pos  # 环形里 pos 就是绕中心转过的落点，旋转过的框拿不到可靠的中心
		else:
			mid = holder.get_global_rect().get_center() - _ring.get_global_rect().position
		var dir := Vector2.UP
		var gap := 24.0
		var dist := 0.0
		if e.pos != Vector2.INF:
			# 两侧的人把分板放在靠桌心的一侧，对面的放在框上方
			var dxn: float = (float(e.pos.x) - _ring_center.x) / maxf(_ring_radii.x, 1.0)
			var dyn: float = (float(e.pos.y) - _ring_center.y) / maxf(_ring_radii.y, 1.0)
			if absf(dxn) > absf(dyn):
				dir = Vector2(-signf(dxn), 0.0)
			var half: Vector2 = holder.custom_minimum_size * 0.5
			dist = absf(cos(e.rot)) * half.x + absf(sin(e.rot)) * half.y
		else:
			dist = holder.custom_minimum_size.y * 0.5
			gap = 22.0
		lab.size = Vector2.ZERO
		lab.reset_size()
		var want: Vector2 = mid + dir * (dist + gap) - lab.size * 0.5
		want.x = clampf(want.x, 8.0, ring_rect.size.x - lab.size.x - 8.0)
		want.y = clampf(want.y, 3.0, ring_rect.size.y - lab.size.y - 3.0)
		lab.position = want


## 分数跳动：结算加分时给某人那块分板一个放大回弹
func bump_score(idx: int) -> void:
	var lab := _strip_label(idx)
	lab.pivot_offset = lab.size * 0.5
	var tw := lab.create_tween()
	tw.tween_property(lab, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK)
	tw.tween_property(lab, "scale", Vector2.ONE, 0.22)


func _strip_label_center(idx: int) -> Vector2:
	var lab := _strip_label(idx)
	return lab.get_global_rect().get_center() - game.get_global_rect().position


## 浮动文字：+N 之类，挂在根控件上，用完自己销毁
func _float_text(txt: String, at: Vector2, color: Color, size := 30) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.z_index = 120
	l.modulate.a = 0.0
	game.add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = at - l.size * 0.5
	return l


## 圆弧位移：二次贝塞尔，用于 325 的影子从一个人飞到另一个人
func _arc(node: Control, from: Vector2, to: Vector2, lift: float, dur: float) -> void:
	var mid := (from + to) * 0.5 + Vector2(0, -lift)
	var tw: Tween = game.create_tween()
	tw.tween_method(func(t: float) -> void:
		var p: Vector2 = from.lerp(mid, t).lerp(mid.lerp(to, t), t)
		node.position = p - node.size * 0.5, 0.0, 1.0, dur)
	await tw.finished


## 固定牌落位：自己金边一闪，对手只是轻微高亮一下
func anim_fix(idx: int) -> void:
	if game.SIM or game.AUTO:
		return
	var s := strip_of(idx)
	if s == null or not s.has_method("pop"):
		return
	if idx == 0:
		s.flash()
		s.pop()
	else:
		s.hint_glow()
	await game.get_tree().create_timer(0.18).timeout


## 结算：构筑组逐张亮起 → 同时点亮
func anim_settle(idx: int) -> void:
	if game.SIM or game.AUTO:
		return
	var s := strip_of(idx)
	if s == null or not s.has_method("reveal"):
		return
	await s.reveal()


## 全场一起亮：四家的构筑组同时逐张亮起，别一家一家等着播
func anim_settle_all(idxs: Array) -> void:
	if game.SIM or game.AUTO:
		return
	for idx in idxs:
		var s := strip_of(idx)
		if s != null and s.has_method("reveal"):
			s.reveal()   # 不 await：并行播放
	await game.get_tree().create_timer(0.42).timeout


## 加分：+N 从构筑框浮出，飞进自己的分板，分板数字跳一下
func anim_score_gain(idx: int, pts: int, color := C_GOLD) -> void:
	if game.SIM or game.AUTO:
		return
	var s := strip_of(idx)
	if s == null:
		return
	var at := center_of(s) + Vector2(0, -14)
	var lab := _float_text("+%d" % pts, at, color, 30)
	var up := at + Vector2(0, -52)
	var tw: Tween = game.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position", up - lab.size * 0.5, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 1.0, 0.12)
	await tw.finished
	await game.get_tree().create_timer(0.06).timeout
	var target := _strip_label_center(idx)
	var tw2: Tween = game.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(lab, "position", target - lab.size * 0.5, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw2.tween_property(lab, "scale", Vector2(0.45, 0.45), 0.26)
	tw2.tween_property(lab, "modulate:a", 0.0, 0.26)
	await tw2.finished
	lab.queue_free()
	bump_score(idx)


## 3-2-5 翻盘：把全场最高分那次 +N 复制成半透明影子，弧线飞给触发者
func anim_325(from_idx: int, to_idx: int, pts: int) -> void:
	if game.SIM or game.AUTO:
		return
	var from_c := _strip_label_center(from_idx)
	var to_c := center_of(strip_of(to_idx)) + Vector2(0, -14)
	var shadow := _float_text("+%d" % pts, from_c, Color(0.92, 0.96, 0.80), 28)
	shadow.modulate.a = 0.0
	var tw: Tween = game.create_tween()
	tw.tween_property(shadow, "modulate:a", 0.7, 0.12)
	await tw.finished
	await _arc(shadow, from_c, to_c, 110.0, 0.42)
	shadow.queue_free()
	var s := strip_of(to_idx)
	if s != null and s.has_method("flash"):
		s.flash(Color(1.0, 0.92, 0.55))
		s.pop(1.06)
	bump_score(to_idx)
	await game.get_tree().create_timer(0.22).timeout


func strip_of(idx: int) -> Control:
	for e in _strips:
		if e.idx == idx:
			return e.holder
	return table_row


# ============================== 弹窗 ==============================
func toggle_log() -> void:
	log_popup.visible = not log_popup.visible


func show_d2() -> void:
	for ch in d2_flow.get_children():
		d2_flow.remove_child(ch)
		ch.queue_free()
	d2_title.text = "弃牌堆2（始终公开，共 %d 张）" % game.discard2.size()
	for c in game.discard2:
		d2_flow.add_child(_mini_card_tex(c))
	d2_popup.show()


# ============================== 玩法说明 ==============================
## 首页「玩法说明」入口：首次点击时实例化场景，之后复用同一个页面
func show_rules() -> void:
	_rules_page().open()


func _rules_page():
	if is_instance_valid(rules_popup):
		return rules_popup
	var page = (load("res://scenes/ui/rules_page.tscn") as PackedScene).instantiate()
	game.add_child(page)
	rules_popup = page
	return page


# ============================== 动画 ==============================
func center_of(n: Control) -> Vector2:
	return n.get_global_rect().get_center() - game.get_global_rect().position


func player_center(p: PPlayer) -> Vector2:
	if p.is_human:
		return center_of(hand_fan)
	var idx: int = game.players.find(p)
	if idx >= 0:
		return center_of(strip_of(idx))
	return center_of(table_row)


## 飞牌动画：从 from 飞到 to（相对根控件坐标），缩小并消失
func fly(tex: Texture2D, from: Vector2, to: Vector2, dur := 0.35) -> void:
	if game.SIM or game.AUTO:
		return
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.texture = tex
	t.size = Vector2(76, 106)
	t.position = from - t.size / 2
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 100
	game.add_child(t)
	var tw: Tween = game.create_tween()
	tw.set_parallel(true)
	tw.tween_property(t, "position", to - t.size / 2, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "scale", Vector2(0.5, 0.5), dur)
	await tw.finished
	t.queue_free()


## 抽牌动画：牌背从抽牌堆飞到玩家
func anim_deal(p: PPlayer) -> void:
	await fly(load_tex("res://assets/ui/牌面/牌背.png"), center_of(back_icon), player_center(p), 0.3)


## 弃牌动画：牌从玩家飞到顶栏牌堆区
func anim_discard(p: PPlayer, c: PCard) -> void:
	await fly(card_tex(c), player_center(p), center_of(piles_label), 0.35)


## 技能牌结算脉冲：效果牌在桌心放大发光后消散
func anim_effect_pulse(c: PCard) -> void:
	if game.SIM or game.AUTO:
		return
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.texture = card_tex(c)
	t.size = Vector2(95, 133)
	t.position = center_of(table_row) - t.size / 2
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.z_index = 100
	t.pivot_offset = t.size / 2
	t.position = center_of(table_row) - t.pivot_offset
	game.add_child(t)
	var tw: Tween = game.create_tween()
	tw.set_parallel(true)
	tw.tween_property(t, "scale", Vector2(1.9, 1.9), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "modulate:a", 0.0, 0.6)
	await tw.finished
	t.queue_free()


# ============================== 刷新 ==============================
func set_prompt(t: String) -> void:
	if game.SIM:
		return
	prompt_label.text = t


func _card_btn(c: PCard, zone: String, enabled: bool) -> Button:
	var b := Button.new()
	b.text = ""
	b.icon = card_tex(c)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(76, 106)
	b.toggle_mode = true
	b.disabled = not enabled
	style_card_button(b)
	if not enabled:
		b.modulate = Color(0.85, 0.85, 0.85)
	if zone == "hand" and c in game._picked:
		b.button_pressed = true
	if zone == "table":
		b.pivot_offset = Vector2(38, 53)
		_add_hover(b)
	b.pressed.connect(func() -> void: card_clicked.emit(c, zone))
	return b


func refresh_hand() -> void:
	if game.SIM:
		return
	for ch in hand_fan.get_children():
		# 必须先 remove_child：queue_free 到帧尾才生效，_arrange_fan 会把待删旧牌也算进扇形
		hand_fan.remove_child(ch)
		ch.queue_free()
	if game.players.is_empty():
		return
	var me: PPlayer = game.players[0]
	var active: bool = not game._request.is_empty() and game._request.zone == "hand"
	for c in me.hand:
		hand_fan.add_child(_card_btn(c, "hand", active))
	call_deferred("_arrange_fan")


## 手牌扇形展开：居中、微微旋转、边缘上翘
func _arrange_fan() -> void:
	var n: int = hand_fan.get_child_count()
	if n == 0:
		return
	var step: float = min(4.0, 40.0 / max(n - 1, 1))
	var spacing: float = min(96.0, 860.0 / max(n - 1, 1))
	var total: float = spacing * (n - 1) + 76
	var x0: float = max((hand_fan.size.x - total) / 2.0, 4.0)
	var R := 420.0
	for i in n:
		var b: Control = hand_fan.get_child(i)
		var deg: float = (i - (n - 1) / 2.0) * step
		var a: float = deg_to_rad(deg)
		b.pivot_offset = Vector2(38, 106)
		b.rotation = a
		b.position = Vector2(x0 + spacing * i, 30 - R * (1.0 - cos(a)))
		_add_hover(b)


func refresh_table(clickable: bool) -> void:
	if game.SIM:
		return
	for ch in table_row.get_children():
		table_row.remove_child(ch)
		ch.queue_free()
	for c in game.table_cards:
		table_row.add_child(_card_btn(c, "table", clickable))


func refresh_labels() -> void:
	if game.SIM:
		return
	round_label.text = "回合 %d/4" % game.round_num
	if game.joker_card != null:
		joker_tex.texture = card_tex(game.joker_card)
		joker_label.text = "  王：%s（%s色）" % [game.joker_card.txt(), "红" if game.joker_color == 1 else "黑"]
	piles_label.text = "  抽牌堆 %d | 弃牌堆1 %d | 弃牌堆2 %d | 效果牌堆 %d" % [
		game.number_pile.size(), game.discard1.size(), game.discard2.size(), game.jqk_pile.size()]


func refresh_all() -> void:
	refresh_labels()
	refresh_hand()
	refresh_table(not game._request.is_empty() and game._request.zone == "table")
	refresh_build_strips()


# ============================== 联机界面 ==============================
func show_lobby(i_am_host: bool) -> void:
	if is_instance_valid(_menu):
		_menu.show_lobby(i_am_host)


func update_lobby(names: Array, i_am_host: bool) -> void:
	if is_instance_valid(_menu):
		_menu.update_lobby(names, i_am_host)


func get_default_name() -> String:
	return _menu.get_default_name() if is_instance_valid(_menu) else ""


func set_default_name(pname: String) -> void:
	if is_instance_valid(_menu):
		_menu.set_default_name(pname)


func show_reconnect(v: bool) -> void:
	if is_instance_valid(_reconnect_btn):
		_reconnect_btn.visible = v


func set_log_lines(lines: Array) -> void:
	if not is_instance_valid(log_view):
		return
	log_view.clear()
	for t in lines:
		log_view.append_text(str(t) + "\n")


func set_lobby_status(t: String) -> void:
	if is_instance_valid(_menu):
		_menu.set_lobby_status(t)


# ============================== 终局 ==============================
var _end_banner: PanelContainer


## 终局 ×1.5：最后一回合加完分，所有分板整体放大一次
func anim_final_boost() -> void:
	if game.SIM or game.AUTO:
		return
	for e in _strips:
		var lab := _strip_label(e.idx)
		lab.pivot_offset = lab.size * 0.5
		var tw := lab.create_tween()
		tw.tween_property(lab, "scale", Vector2(1.5, 1.5), 0.18).set_trans(Tween.TRANS_BACK)
		tw.tween_property(lab, "scale", Vector2.ONE, 0.32)
	await game.get_tree().create_timer(0.42).timeout


## 终局提示：屏幕正中一块面板，压在手牌区上方，按钮在面板里
func show_end_banner(text: String, can_restart: bool) -> void:
	if game.SIM:
		return
	if is_instance_valid(_end_banner):
		_end_banner.get_parent().remove_child(_end_banner)
		_end_banner.queue_free()
	prompt_label.visible = false
	if is_instance_valid(restart_btn):
		restart_btn.visible = false   # 面板里已经有一个重新开始，底部那个先收起来

	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrap.offset_top = 500.0   # 压在手牌区：终局手牌已清空，不挡任何人的分板
	wrap.z_index = 60
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.add_theme_stylebox_override("panel", _sb(Color(0.035, 0.07, 0.055, 0.97), Color(0.85, 0.70, 0.32, 0.55), 18))
	card.custom_minimum_size = Vector2(440, 0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_GOLD)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := Button.new()
	btn.text = "重新开始"
	btn.theme_type_variation = &"AccentButton"
	btn.custom_minimum_size = Vector2(150, 36)
	btn.add_theme_font_size_override("font_size", 15)
	btn.pressed.connect(func() -> void: restart_requested.emit())
	btn.visible = can_restart
	row.add_child(btn)
	vb.add_child(title)
	vb.add_child(row)
	margin.add_child(vb)
	card.add_child(margin)
	wrap.add_child(card)
	game.add_child(wrap)
	_end_banner = card
	card.modulate.a = 0.0
	var tw: Tween = game.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.22)


func hide_end_banner() -> void:
	if is_instance_valid(_end_banner):
		var p := _end_banner.get_parent()
		if p != null:
			p.get_parent().remove_child(p)
			p.queue_free()
		_end_banner = null
	if is_instance_valid(prompt_label):
		prompt_label.visible = true

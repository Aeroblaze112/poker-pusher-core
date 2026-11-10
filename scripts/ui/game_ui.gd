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
var selected_count := 4   # 开局界面当前选中的人数

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

var _menu_box: Control           # 开局菜单卡（单机 + 联机入口）
var _lobby_card: PanelContainer  # 联机大厅卡
var _lobby_box: VBoxContainer    # 联机大厅内容
var _lobby_list: Label
var _lobby_status: Label
var _start_net_btn: Button
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _name_edit: LineEdit
var _reconnect_btn: Button
var _acct_form: HBoxContainer    # 账户：登录/注册表单
var _acct_info: HBoxContainer    # 账户：已登录信息行
var _acct_label: Label
var _acct_status: Label
var _acct_user: LineEdit
var _acct_pwd: LineEdit

var _wrap_top: HBoxContainer   # 桌面上沿对手区
var _wrap_left: Control        # 左侧对手区
var _wrap_right: Control       # 右侧对手区
var _score_row_boxes: Array = []

var _tex_cache := {}
var _rotated: Array = []        # 旋转控件 [{c, wrap, rot, fixed}]
var _strips: Array = []         # 构筑框 [{idx, holder, scale}]
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
	# 背景绒布
	var bg := TextureRect.new()
	bg.texture = load_tex("res://assets/ui/背景.png")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game.add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	game.add_child(root)

	# 顶栏
	var top := HBoxContainer.new()
	round_label = Label.new()
	phase_label = Label.new()
	back_icon = TextureRect.new()
	back_icon.texture = load_tex("res://assets/ui/牌面/牌背.png")
	back_icon.custom_minimum_size = Vector2(24, 34)
	back_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	joker_tex = TextureRect.new()
	joker_tex.custom_minimum_size = Vector2(24, 34)
	joker_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	joker_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	joker_label = Label.new()
	piles_label = Label.new()
	var log_btn := Button.new()
	log_btn.text = "日志"
	log_btn.pressed.connect(toggle_log)
	var d2_btn := Button.new()
	d2_btn.text = "看弃牌堆2"
	d2_btn.pressed.connect(show_d2)
	for l in [round_label, phase_label, back_icon, joker_tex, joker_label, piles_label, log_btn, d2_btn]:
		if l is Label:
			l.add_theme_font_size_override("font_size", 15)
			l.add_theme_color_override("font_color", C_IVORY)
		elif l is Button:
			style_button(l)
		top.add_child(l)
	root.add_child(top)

	# 中部：四人围桌（上/左/右构筑框，下方人类），中间牌桌
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)

	# 左边玩家构筑框（旋转 90°，顶部朝向牌桌，垂直居中）
	var left := Control.new()
	left.custom_minimum_size = Vector2(150, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	_wrap_left = left

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)

	# 对家的构筑框（摆在桌上）
	var opp1_strip_box := HBoxContainer.new()
	opp1_strip_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(opp1_strip_box)
	_wrap_top = opp1_strip_box

	# 右边玩家构筑框（旋转 -90°，顶部朝向牌桌，垂直居中）
	var right := Control.new()
	right.custom_minimum_size = Vector2(150, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	_wrap_right = right

	# 桌子区域（效果牌）
	table_row = HBoxContainer.new()
	table_row.alignment = BoxContainer.ALIGNMENT_CENTER
	table_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(table_row)

	# 对手构筑框（可随人数重建）
	build_strips()

	# 你的构筑框（居中摆在牌桌下沿）
	var my_build_box := HBoxContainer.new()
	my_build_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(my_build_box)
	_make_build_strip(0, 1.0, 0.0, my_build_box)

	# 底栏：记分板（左）+ 人类玩家手牌/操作
	var bottom := PanelContainer.new()
	style_panel(bottom, 0)  # 底栏通长，不圆角
	var bottom_row := HBoxContainer.new()
	bottom.add_child(bottom_row)
	# 记分板：四家名字 + 总分，独立左对齐
	var sb := VBoxContainer.new()
	sb.custom_minimum_size = Vector2(130, 0)
	sb.add_theme_constant_override("separation", 2)
	for i in 6:  # 建满 6 行，刷新时按实际人数显隐
		var row := HBoxContainer.new()
		var name_l := Label.new()
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", C_IVORY)
		var score_l := Label.new()
		score_l.add_theme_font_size_override("font_size", 13)
		score_l.add_theme_color_override("font_color", C_GOLD)
		row.add_child(name_l)
		row.add_child(score_l)
		sb.add_child(row)
		_score_rows.append([name_l, score_l])
		_score_row_boxes.append(row)
	bottom_row.add_child(sb)
	var bvb := VBoxContainer.new()
	bvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_fan = Control.new()
	hand_fan.custom_minimum_size = Vector2(0, 150)
	hand_fan.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bvb.add_child(hand_fan)
	var brow := HBoxContainer.new()
	prompt_label = Label.new()
	prompt_label.add_theme_color_override("font_color", C_GOLD)
	prompt_label.add_theme_font_size_override("font_size", 17)
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	brow.add_child(prompt_label)
	confirm_btn = Button.new()
	confirm_btn.text = "确认"
	confirm_btn.visible = false
	style_button(confirm_btn, true)
	confirm_btn.pressed.connect(func() -> void: confirm_pressed.emit())
	brow.add_child(confirm_btn)
	restart_btn = Button.new()
	restart_btn.text = "重新开始"
	restart_btn.visible = false
	style_button(restart_btn, true)
	restart_btn.pressed.connect(func() -> void: restart_requested.emit())
	brow.add_child(restart_btn)
	_reconnect_btn = Button.new()
	_reconnect_btn.text = "重新连接"
	_reconnect_btn.visible = false
	style_button(_reconnect_btn, true)
	_reconnect_btn.pressed.connect(func() -> void: reconnect_requested.emit())
	brow.add_child(_reconnect_btn)
	bvb.add_child(brow)
	bottom_row.add_child(bvb)  # PanelContainer 只能有一个子节点，bvb 必须挂进 bottom_row
	root.add_child(bottom)

	_build_log_popup()
	_build_d2_popup()
	_build_start_overlay()


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


## 开局难度选择遮罩层：压场暗罩 + 居中鎏金菜单卡
func _build_start_overlay() -> void:
	var overlay := PanelContainer.new()
	overlay.name = "StartOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := StyleBoxFlat.new()
	scrim.bg_color = Color(0.01, 0.03, 0.02, 0.72)
	overlay.add_theme_stylebox_override("panel", scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	style_panel(card, 18)
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 46)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	card.add_child(margin)
	var ov_vb := VBoxContainer.new()
	ov_vb.add_theme_constant_override("separation", 10)
	margin.add_child(ov_vb)
	var title := Label.new()
	title.text = "我说推扑克特别有说法"
	style_title(title, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_vb.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "——四驱兄弟斗不了地主——"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", C_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_vb.add_child(subtitle)
	_build_account_section(ov_vb)
	var hint := Label.new()
	hint.text = "选择人数与对手难度，开始游戏"
	hint.add_theme_color_override("font_color", C_IVORY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_vb.add_child(hint)
	# 人数选择（默认 4 人）
	var count_row := HBoxContainer.new()
	count_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var count_btns: Array = []
	for n in [2, 4, 5, 6]:
		var cb := Button.new()
		cb.text = "%d 人" % n
		cb.toggle_mode = true
		cb.button_pressed = (n == selected_count)
		cb.custom_minimum_size = Vector2(72, 36)
		style_button(cb)
		var cnt: int = n
		cb.pressed.connect(func() -> void:
			selected_count = cnt
			for other in count_btns:
				other.button_pressed = (other == cb))
		count_btns.append(cb)
		count_row.add_child(cb)
	ov_vb.add_child(count_row)
	var btn_defs := [
		["easy", "初级"],
		["normal", "高级"],
		["hard", "智能择"],
	]
	for d in btn_defs:
		var b := Button.new()
		b.text = d[1]
		b.custom_minimum_size = Vector2(320, 42)
		b.add_theme_font_size_override("font_size", 18)
		style_button(b, d[0] == "hard")  # 智能择为主推，给主行动色
		var key: String = d[0]
		b.pressed.connect(func() -> void: difficulty_chosen.emit(key))
		ov_vb.add_child(b)
	# 玩法说明入口（只读页面，不打断开局流程）
	var rules_row := HBoxContainer.new()
	rules_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var rules_btn := Button.new()
	rules_btn.text = "玩法说明"
	rules_btn.custom_minimum_size = Vector2(150, 34)
	rules_btn.add_theme_font_size_override("font_size", 15)
	style_button(rules_btn)
	rules_btn.pressed.connect(show_rules)
	rules_row.add_child(rules_btn)
	ov_vb.add_child(rules_row)
	_menu_box = card
	_build_net_section(ov_vb)
	_build_lobby(center)
	game.add_child(overlay)


# ============================== 账户区 ==============================
func _build_account_section(ov_vb: VBoxContainer) -> void:
	# 未登录：表单（用户名 + 密码 + 登录/注册）
	_acct_form = HBoxContainer.new()
	_acct_form.alignment = BoxContainer.ALIGNMENT_CENTER
	_acct_user = LineEdit.new()
	_acct_user.placeholder_text = "用户名"
	_acct_user.custom_minimum_size = Vector2(120, 0)
	style_input(_acct_user)
	_acct_pwd = LineEdit.new()
	_acct_pwd.placeholder_text = "密码"
	_acct_pwd.secret = true
	_acct_pwd.custom_minimum_size = Vector2(120, 0)
	style_input(_acct_pwd)
	var login_btn := Button.new()
	login_btn.text = "登录"
	login_btn.custom_minimum_size = Vector2(64, 32)
	style_button(login_btn, true)
	login_btn.pressed.connect(func() -> void:
		login_requested.emit(_acct_user.text.strip_edges(), _acct_pwd.text))
	var reg_btn := Button.new()
	reg_btn.text = "注册"
	reg_btn.custom_minimum_size = Vector2(64, 32)
	style_button(reg_btn)
	reg_btn.pressed.connect(func() -> void:
		register_requested.emit(_acct_user.text.strip_edges(), _acct_pwd.text))
	_acct_form.add_child(_acct_user)
	_acct_form.add_child(_acct_pwd)
	_acct_form.add_child(login_btn)
	_acct_form.add_child(reg_btn)
	ov_vb.add_child(_acct_form)
	# 已登录：信息行（名字 + 战绩 + 登出）
	_acct_info = HBoxContainer.new()
	_acct_info.alignment = BoxContainer.ALIGNMENT_CENTER
	_acct_info.visible = false
	_acct_label = Label.new()
	_acct_label.add_theme_color_override("font_color", C_IVORY)
	_acct_info.add_child(_acct_label)
	var logout_btn := Button.new()
	logout_btn.text = "登出"
	logout_btn.custom_minimum_size = Vector2(64, 32)
	style_button(logout_btn)
	logout_btn.pressed.connect(func() -> void: logout_requested.emit())
	_acct_info.add_child(logout_btn)
	ov_vb.add_child(_acct_info)
	_acct_status = Label.new()
	_acct_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_acct_status.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4))
	ov_vb.add_child(_acct_status)


## 登录状态切换：pname 为空 = 回到游客表单；非空 = 显示战绩并把联机名锁定为账号名
func set_account(pname: String, stats: Dictionary) -> void:
	if not is_instance_valid(_acct_form):
		return
	var logged := pname != ""
	_acct_form.visible = not logged
	_acct_info.visible = logged
	if logged:
		_acct_label.text = "👤 %s ｜ %d 场 %d 胜 ｜ 最佳 %d 分" % [
			pname, int(stats.get("games", 0)), int(stats.get("wins", 0)), int(stats.get("best", 0))]
		set_default_name(pname)
		if is_instance_valid(_name_edit):
			_name_edit.editable = false
	elif is_instance_valid(_name_edit):
		_name_edit.editable = true
	set_account_status("")


func set_account_status(t: String) -> void:
	if is_instance_valid(_acct_status):
		_acct_status.text = t


# ============================== 构筑框 ==============================
## 对手构筑框：先排桌面上沿，人手多于 4 时左右两侧各加一个（旋转 90°）
func build_strips() -> void:
	# 只重建对手框：主视角框（idx 0，在 build() 里单独创建）不能一起销毁
	for i in range(_strips.size() - 1, -1, -1):
		var e: Dictionary = _strips[i]
		if e.idx == 0:
			continue
		e.holder.get_parent().remove_child(e.holder)
		e.holder.queue_free()
		_strips.remove_at(i)
	_rotated.clear()
	var opponents := player_count - 1
	# 3 人局（对手 2）没有左右余量，两个都排上沿；4 人以上才分左右两侧
	var top_n: int = opponents if opponents <= 2 else opponents - 2
	for i in top_n:
		_make_build_strip(1 + i, 0.55, 0.0, _wrap_top)
	if opponents >= 3:
		_make_build_strip(1 + top_n, 0.55, PI / 2, _wrap_left)
		_make_build_strip(2 + top_n, 0.55, -PI / 2, _wrap_right)


## 人数变化时重建对手构筑框（联机开局 / 单机选人数）
func set_player_count(n: int) -> void:
	if n == player_count and not _strips.is_empty():
		return
	player_count = n
	build_strips()
	refresh_build_strips()


## 构筑框：常态黄牌位条底图 + 牌严格落在槽内，空槽盖牌背；rot != 0 时旋转
func _make_build_strip(idx: int, scale: float, rot: float, wrapper: Control) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(402, 138) * scale
	var strip := TextureRect.new()
	strip.texture = load_tex("res://assets/ui/牌位/构筑牌位_常态黄.png")
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(strip)
	wrapper.add_child(holder)
	if rot != 0.0:
		holder.rotation = rot
		_rotated.append({c = holder, wrap = wrapper, rot = rot, fixed = Vector2(402, 138) * scale})
	_strips.append({idx = idx, holder = holder, scale = scale})
	return holder


func _strip_card(tex: Texture2D, pos: Vector2, s: float, hoverable := false) -> TextureRect:
	var t := TextureRect.new()
	# 必须先设 expand_mode 再贴纹理：否则纹理原始尺寸（200×280）会把后面设置的 size 顶回去
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.texture = tex
	t.position = pos
	t.size = Vector2(74, 103) * s
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hoverable:
		t.pivot_offset = t.size / 2
		_add_hover(t)
	return t


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
	# 实测牌位图：黄槽内框 x 13..94（间距 98）、y 12..125；74 宽牌在槽内居中应放 16.5/114.5/212.5/310.5
	const SLOT_X := [16.5, 114.5, 212.5, 310.5]
	for e in _strips:
		var holder: Control = e.holder
		holder.visible = e.idx < game.players.size()
		if not holder.visible:
			continue
		var p: PPlayer = game.players[e.idx]
		var s: float = e.scale
		var hoverable: bool = e.idx != 0  # 主视角（你的）构筑牌不放大
		# 清空底图以外的子节点
		while holder.get_child_count() > 1:
			var ch: Node = holder.get_child(1)
			holder.remove_child(ch)
			ch.queue_free()
		# 4 个黄槽：固定牌 → 临时填牌 → 空槽盖牌背
		var fixed_n: int = p.build.size()
		var on_yellow: int = mini(p.temp_fill.size(), 4 - fixed_n)
		for i in 4:
			var tex: Texture2D
			if i < fixed_n:
				tex = card_tex(p.build[i])
			elif i < fixed_n + on_yellow:
				tex = card_tex(p.temp_fill[i - fixed_n])
			else:
				tex = load_tex("res://assets/ui/牌面/牌背.png")
			holder.add_child(_strip_card(tex, Vector2(SLOT_X[i], 17) * s, s, hoverable and (i < fixed_n + on_yellow)))
		# 蓝槽 = 杠给的临时牌位，排在黄条右侧，空着不盖牌
		for bi in p.temp_slots:
			var slot := TextureRect.new()
			slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			slot.texture = load_tex("res://assets/ui/牌位/构筑牌位_临时蓝.png")
			slot.position = Vector2(410 + bi * 116, 0) * s
			slot.size = Vector2(108, 138) * s
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(slot)
			var fill_idx: int = on_yellow + bi
			if fill_idx < p.temp_fill.size():
				holder.add_child(_strip_card(card_tex(p.temp_fill[fill_idx]), Vector2(410 + bi * 116 + 17, 17) * s, s, hoverable))
		if p.dropped:  # 掉线标记：构筑框左上角
			var tag := Label.new()
			tag.text = "离线"
			tag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
			tag.add_theme_font_size_override("font_size", maxi(int(20 * s), 10))
			tag.position = Vector2(4, -4) * s
			holder.add_child(tag)
		holder.custom_minimum_size = Vector2(402, 138) * s
	_relayout_rotated()


## 旋转控件重排：尺寸变化后重新居中
func _relayout_rotated() -> void:
	for r in _rotated:
		var c: Control = r.c
		var wrap: Control = r.wrap
		var s: Vector2 = r.fixed
		if s == Vector2.ZERO:
			s = c.get_combined_minimum_size()
		c.size = s
		c.pivot_offset = s / 2
		c.position = (wrap.size - s) / 2


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
## 首页「玩法说明」入口：只读页面，首次点击时才构建
func show_rules() -> void:
	if rules_popup == null or not is_instance_valid(rules_popup):
		_build_rules_page()
	rules_popup.show()
	rules_popup.move_to_front()


func _build_rules_page() -> void:
	var overlay := PanelContainer.new()
	overlay.name = "RulesOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var scrim := StyleBoxFlat.new()
	scrim.bg_color = Color(0.01, 0.03, 0.02, 0.86)
	overlay.add_theme_stylebox_override("panel", scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	style_panel(card, 18)
	center.add_child(card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 28)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 16)
	card.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "玩法说明"
	style_title(title, 27)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "四回合，把构筑组做到最大"
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", C_MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	# 正文：两栏排布，1280×720 下整页可见，不需要滚动
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	vb.add_child(cols)
	var col_l := VBoxContainer.new()
	var col_r := VBoxContainer.new()
	for col in [col_l, col_r]:
		col.custom_minimum_size = Vector2(336, 0)
		col.add_theme_constant_override("separation", 2)
		cols.add_child(col)
	_rules_section(col_l, "目标", [
		"四回合打完，构筑组每回合结算一次、分数累计，总分最高者胜。",
	], 330)
	_rules_section(col_l, "牌具", [
		"· 数字牌 1–10，四花色各一张（2 人局只到 5）。",
		"· 功能牌：弃 / 摸 / 杠，四花色各 2 套（2 人局 1 套）。",
		"· 大小王各 1 张；开局抽出的那张决定本局「王的颜色」。",
		"· 弃牌堆 1 抽空时洗回；弃牌堆 2 永不回洗、始终公开。",
	], 330)
	_rules_section(col_l, "每回合", [
		"1. 发牌：第 1 回合每人 4 张（四花色各一）；之后每人补「当前空位数」张，其中 1 张用来固定。",
		"2. 固定：每人固定 1 张进构筑组，永久保留、公开；第 1 回合固定的牌必须与王同色。",
		"3. 效果牌：桌上摆「手牌最多者手牌数 + 人数」张；每人先弃 1 张回堆，剩下逐张结算——弃＝每人弃 1 张手牌进弃牌堆 2；摸＝每人摸 2 张；杠＝全员临时牌位 +1。",
		"4. 结算：手牌填入构筑组空位（空位 = 4 − 已固定张数 + 临时牌位），多出的进弃牌堆 1，然后计分。",
		"5. 清理：临时填入的牌进弃牌堆 1，临时牌位清零。",
	], 330)
	_rules_section(col_r, "计分", [
		"基准分取四者最大：最大单张 / 最大对子和 / 最大三张和 / 最长顺子点数和（至少 3 张连续，等长取点数和更大的那段）。",
		"之后依次相乘，每次向下取整：",
		"· 同花 ×2、同色 ×1.2（取大者；至少 2 张才算，顺子被选为基准时只看顺子那几张）",
		"· 最大牌是三张 ×3，是对子 ×2",
		"· 其余牌里还有三张 ×2，有对子 ×1.5",
		"· 与王同色 ×1.2：同花或同色命中一次，最大牌再单独命中一次",
	], 330)
	_rules_section(col_r, "3-2-5 翻盘", [
		"构筑组首次同时出现 3、2、5 各一张，且本回合得分全场最低 → 本回合得分变成全场最高。每人整局只有一次。",
	], 330)
	_rules_section(col_r, "终局", [
		"第 4 回合结束，或有人手牌被弃空、摸牌不够一圈、牌位已满 → 进入最终回合，本回合得分 ×1.5。",
	], 330)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var close_btn := Button.new()
	close_btn.text = "知道了"
	close_btn.custom_minimum_size = Vector2(200, 40)
	close_btn.add_theme_font_size_override("font_size", 17)
	style_button(close_btn, true)
	close_btn.pressed.connect(func() -> void: overlay.hide())
	close_row.add_child(close_btn)
	vb.add_child(close_row)
	game.add_child(overlay)
	game.move_child(overlay, game.get_child_count() - 1)
	rules_popup = overlay


## 玩法说明里的一节：鎏金小节标题 + 若干正文行
func _rules_section(vb: VBoxContainer, heading: String, lines: Array, width := 690) -> void:
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 17)
	h.add_theme_color_override("font_color", C_GOLD)
	vb.add_child(h)
	for t in lines:
		var b := Label.new()
		b.text = t
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", C_IVORY)
		b.custom_minimum_size = Vector2(width, 0)
		vb.add_child(b)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap)


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
	# 记分板：各家总分（按实际人数显隐）
	for i in _score_row_boxes.size():
		_score_row_boxes[i].visible = i < game.players.size()
		if i >= game.players.size():
			continue
		var p: PPlayer = game.players[i]
		_score_rows[i][0].text = "%s%s%s" % [p.pname,
			" ［离线］" if p.dropped else "",
			" ［终局×1.5］" if p.j_emptied else ""]
		_score_rows[i][1].text = "  总分 %d" % p.score
		_score_rows[i][1].add_theme_color_override("font_color",
			Color(0.95, 0.85, 0.4) if p.is_human else Color(1, 1, 1))


func refresh_all() -> void:
	refresh_labels()
	refresh_hand()
	refresh_table(not game._request.is_empty() and game._request.zone == "table")
	refresh_build_strips()


# ============================== 联机界面 ==============================
func _build_net_section(ov_vb: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", C_GOLD_DIM)
	ov_vb.add_child(sep)
	var net_lbl := Label.new()
	net_lbl.text = "联机对战（2-6 人，主机权威）"
	net_lbl.add_theme_color_override("font_color", C_GOLD)
	net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ov_vb.add_child(net_lbl)
	var name_row := HBoxContainer.new()
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "你的名字（重连凭它入座）"
	_name_edit.custom_minimum_size = Vector2(212, 0)
	style_input(_name_edit)
	name_row.add_child(_name_edit)
	ov_vb.add_child(name_row)
	var addr_row := HBoxContainer.new()
	addr_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.custom_minimum_size = Vector2(140, 0)
	style_input(_ip_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = str(NetSession.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(64, 0)
	style_input(_port_edit)
	addr_row.add_child(_ip_edit)
	addr_row.add_child(_port_edit)
	ov_vb.add_child(addr_row)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var host_btn := Button.new()
	host_btn.text = "创建主机"
	host_btn.custom_minimum_size = Vector2(140, 36)
	style_button(host_btn, true)
	host_btn.pressed.connect(func() -> void:
		host_requested.emit(int(_port_edit.text), _name_edit.text.strip_edges()))
	var join_btn := Button.new()
	join_btn.text = "加入主机"
	join_btn.custom_minimum_size = Vector2(140, 36)
	style_button(join_btn)
	join_btn.pressed.connect(func() -> void:
		join_requested.emit(_ip_edit.text, int(_port_edit.text), _name_edit.text.strip_edges()))
	btn_row.add_child(host_btn)
	btn_row.add_child(join_btn)
	ov_vb.add_child(btn_row)


func _build_lobby(parent: Control) -> void:
	_lobby_card = PanelContainer.new()
	style_panel(_lobby_card, 18)
	_lobby_card.visible = false
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 46)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 30)
	_lobby_card.add_child(margin)
	_lobby_box = VBoxContainer.new()
	_lobby_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_lobby_box.add_theme_constant_override("separation", 14)
	margin.add_child(_lobby_box)
	var title := Label.new()
	title.text = "联机大厅"
	style_title(title, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_box.add_child(title)
	_lobby_list = Label.new()
	_lobby_list.add_theme_color_override("font_color", C_IVORY)
	_lobby_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_box.add_child(_lobby_list)
	_lobby_status = Label.new()
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status.add_theme_color_override("font_color", C_GOLD)
	_lobby_box.add_child(_lobby_status)
	_start_net_btn = Button.new()
	_start_net_btn.text = "开始联机"
	_start_net_btn.custom_minimum_size = Vector2(240, 44)
	style_button(_start_net_btn, true)
	_start_net_btn.pressed.connect(func() -> void: start_net_requested.emit())
	_lobby_box.add_child(_start_net_btn)
	parent.add_child(_lobby_card)


func show_lobby(i_am_host: bool) -> void:
	_menu_box.visible = false
	_lobby_card.visible = true
	_start_net_btn.visible = i_am_host
	_lobby_status.text = "" if i_am_host else "已连接，等待主机开始……"


func update_lobby(names: Array, i_am_host: bool) -> void:
	if not is_instance_valid(_lobby_list):
		return
	_lobby_list.text = "已连接 %d 人：\n%s" % [names.size(), "\n".join(names)]
	_start_net_btn.visible = i_am_host
	_start_net_btn.disabled = names.size() < 2


func get_default_name() -> String:
	return _name_edit.text.strip_edges() if is_instance_valid(_name_edit) else ""


func set_default_name(pname: String) -> void:
	if is_instance_valid(_name_edit) and pname != "":
		_name_edit.text = pname


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
	if is_instance_valid(_lobby_status):
		_lobby_status.text = t

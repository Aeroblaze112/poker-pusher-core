extends Control

## 一个玩家的构筑组展示条。
## 4 个黄槽：已固定牌 → 本回合临时填入的牌 → 空槽盖牌背；
## 黄条右侧的蓝槽是「杠」给的临时牌位，空着不盖牌。
## 牌面贴图自己按 PCard.texture_name() 取，不依赖外层。

const UNIT_SIZE := Vector2(402, 138)
const CARD_SIZE := Vector2(74, 103)
const SLOT_X := [16.5, 114.5, 212.5, 310.5]   # 实测黄槽内框，74 宽的牌在槽内居中
const SLOT_Y := 17.0
const BLUE_X := 410.0
const BLUE_STEP := 116.0
const CARD_DIR := "res://assets/ui/牌面/"
const CARD_SQUASH := 0.84   # 纵向压一点：牌是平铺在桌面上的，底边不动、牌面往里收
const SHADOW_COLOR := Color(0, 0, 0, 0.32)

var index := 0            # 座位号，0 = 自己
var card_scale := 1.0
var _cards: Array = []    # 本帧的牌节点，结算逐张亮起用
var _last_temp := 0       # 上一帧的临时牌位数，用来判断哪几个是刚滑出来的

@onready var _background: TextureRect = $Background


## 摆位：座位号 + 缩放（上沿 0.55，主视角 1.0）
func setup(idx: int, s: float) -> void:
	index = idx
	card_scale = s
	custom_minimum_size = UNIT_SIZE * s
	pivot_offset = custom_minimum_size / 2


func refresh(p: PPlayer) -> void:
	visible = p != null
	if p == null:
		return
	_clear_cards()
	var hoverable := index != 0   # 自己的构筑牌不放大
	var fixed_n := p.build.size()
	var on_yellow := mini(p.temp_fill.size(), 4 - fixed_n)

	for i in 4:
		var tex: Texture2D
		if i < fixed_n:
			tex = _card_texture(p.build[i])
		elif i < fixed_n + on_yellow:
			tex = _card_texture(p.temp_fill[i - fixed_n])
		else:
			tex = load(CARD_DIR + "牌背.png")
		var card := _make_card(tex, Vector2(SLOT_X[i], SLOT_Y) * card_scale, hoverable and i < fixed_n + on_yellow)
		add_child(card)
		_cards.append(card)

	for bi in p.temp_slots:
		var slot := TextureRect.new()
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		slot.texture = load("res://assets/ui/牌位/构筑牌位_临时蓝.png")
		slot.position = Vector2(BLUE_X + bi * BLUE_STEP, 0) * card_scale
		slot.size = Vector2(108, 138) * card_scale
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		if bi >= _last_temp:   # 杠给的临时牌位滑出来
			slot.pivot_offset = slot.size * 0.5
			var from_x: float = slot.position.x - 46.0 * card_scale
			slot.position.x = from_x
			slot.modulate.a = 0.0
			var tw := create_tween()
			tw.set_parallel(true)
			tw.tween_property(slot, "position:x", Vector2(BLUE_X + bi * BLUE_STEP, 0).x * card_scale, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(slot, "modulate:a", 1.0, 0.18)
		var fill_idx := on_yellow + bi
		if fill_idx < p.temp_fill.size():
			var blue_card := _make_card(
				_card_texture(p.temp_fill[fill_idx]),
				Vector2(BLUE_X + bi * BLUE_STEP + 17, SLOT_Y) * card_scale,
				hoverable)
			add_child(blue_card)
			_cards.append(blue_card)

	if p.dropped:
		var tag := Label.new()
		tag.text = "离线"
		tag.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		tag.add_theme_font_size_override("font_size", maxi(int(20 * card_scale), 10))
		tag.position = Vector2(4, -4) * card_scale
		add_child(tag)

	custom_minimum_size = UNIT_SIZE * card_scale
	_last_temp = p.temp_slots


func _clear_cards() -> void:
	_cards.clear()
	while get_child_count() > 1:
		var child := get_child(1)
		remove_child(child)
		child.queue_free()


## 金边闪一下：固定牌落位、325 命中时用
func flash(color := Color(1.0, 0.86, 0.45)) -> void:
	var g := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	g.add_theme_stylebox_override("panel", sb)
	g.position = Vector2.ZERO
	g.size = custom_minimum_size
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.modulate.a = 0.0
	add_child(g)
	var tw := create_tween()
	tw.tween_property(g, "modulate:a", 1.0, 0.10)
	tw.tween_property(g, "modulate:a", 0.0, 0.35)
	tw.tween_callback(g.queue_free)


## 整体回弹一下
func pop(amount := 1.04) -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(amount, amount), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK)


## 结算：构筑组逐张亮起，最后整体闪一下
func reveal() -> void:
	for c in _cards:
		c.modulate = Color(0.52, 0.52, 0.52, 1.0)
	for c in _cards:
		var tw: Tween = c.create_tween()
		tw.tween_property(c, "modulate", Color(1, 1, 1, 1), 0.09)
		await get_tree().create_timer(0.05).timeout
	flash()
	pop(1.03)
	await get_tree().create_timer(0.16).timeout


## 对手固定牌 / 325 命中时的柔和提示
func hint_glow(color := Color(0.55, 0.85, 0.65)) -> void:
	var tw := create_tween()
	var g := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	g.add_theme_stylebox_override("panel", sb)
	g.position = Vector2.ZERO
	g.size = custom_minimum_size
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.modulate.a = 0.0
	add_child(g)
	tw.tween_property(g, "modulate:a", 0.85, 0.14)
	tw.tween_property(g, "modulate:a", 0.0, 0.30)
	tw.tween_callback(g.queue_free)


func _card_texture(c: PCard) -> Texture2D:
	return load(CARD_DIR + c.texture_name() + ".png")


## 一张牌 = 牌面 + 落在桌面上的影子；整体在底边中点压扁，读起来像平铺俯视
func _make_card(tex: Texture2D, pos: Vector2, hoverable: bool) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = CARD_SIZE * card_scale
	holder.pivot_offset = Vector2(holder.size.x / 2, holder.size.y)
	holder.scale = Vector2(1.0, CARD_SQUASH)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHADOW_COLOR
	sb.set_corner_radius_all(7)
	shadow.add_theme_stylebox_override("panel", sb)
	shadow.position = Vector2(2, 5)
	shadow.size = holder.size
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(shadow)

	var face := TextureRect.new()
	# 必须先设 expand_mode 再贴纹理：否则纹理原始尺寸会把后面设置的 size 顶回去
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	face.texture = tex
	face.size = holder.size
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(face)

	if hoverable:
		_add_hover(holder)
	return holder


func _add_hover(c: Control, max_scale := 1.18) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_entered.connect(func() -> void:
		c.z_index = 50
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(max_scale, max_scale * CARD_SQUASH), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT))
	c.mouse_exited.connect(func() -> void:
		c.z_index = 0
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(1.0, CARD_SQUASH), 0.12))


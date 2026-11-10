extends PanelContainer

## 玩法说明页：结构在 rules_page.tscn 里，条款文字在下面的常量里。
## 由 GameUI 实例化一次，之后反复开关。

signal closed

const SECTION_LEFT: Array = [
	["目标", [
		"四回合打完，构筑组每回合结算一次、分数累计，总分最高者胜。",
	]],
	["牌具", [
		"· 数字牌 1–10，四花色各一张（2 人局只到 5）。",
		"· 功能牌：弃 / 摸 / 杠，四花色各 2 套（2 人局 1 套）。",
		"· 大小王各 1 张；开局抽出的那张决定本局「王的颜色」。",
		"· 弃牌堆 1 抽空时洗回；弃牌堆 2 永不回洗、始终公开。",
	]],
	["每回合", [
		"1. 发牌：第 1 回合每人 4 张（四花色各一）；之后每人补「当前空位数」张，其中 1 张用来固定。",
		"2. 固定：每人固定 1 张进构筑组，永久保留、公开；第 1 回合固定的牌必须与王同色。",
		"3. 效果牌：桌上摆「手牌最多者手牌数 + 人数」张；每人先弃 1 张回堆，剩下逐张结算——弃＝每人弃 1 张手牌进弃牌堆 2；摸＝每人摸 2 张；杠＝全员临时牌位 +1。",
		"4. 结算：手牌填入构筑组空位（空位 = 4 − 已固定张数 + 临时牌位），多出的进弃牌堆 1，然后计分。",
		"5. 清理：临时填入的牌进弃牌堆 1，临时牌位清零。",
	]],
]

const SECTION_RIGHT: Array = [
	["计分", [
		"基准分取四者最大：最大单张 / 最大对子和 / 最大三张和 / 最长顺子点数和（至少 3 张连续，等长取点数和更大的那段）。",
		"之后依次相乘，每次向下取整：",
		"· 同花 ×2、同色 ×1.2（取大者；至少 2 张才算，顺子被选为基准时只看顺子那几张）",
		"· 最大牌是三张 ×3，是对子 ×2",
		"· 其余牌里还有三张 ×2，有对子 ×1.5",
		"· 与王同色 ×1.2：同花或同色命中一次，最大牌再单独命中一次",
	]],
	["3-2-5 翻盘", [
		"构筑组首次同时出现 3、2、5 各一张，且本回合得分全场最低 → 本回合得分变成全场最高。每人整局只有一次。",
	]],
	["终局", [
		"第 4 回合结束，或有人手牌被弃空、摸牌不够一圈、牌位已满 → 进入最终回合，本回合得分 ×1.5。",
	]],
]

const LINE_WIDTH := 330
const GOLD := Color(0.85, 0.70, 0.32)
const IVORY := Color(0.95, 0.93, 0.86)

@onready var _col_left: VBoxContainer = $Center/Card/Margin/VBox/Cols/ColLeft
@onready var _col_right: VBoxContainer = $Center/Card/Margin/VBox/Cols/ColRight
@onready var _close_btn: Button = $Center/Card/Margin/VBox/CloseRow/CloseBtn


func _ready() -> void:
	_fill(_col_left, SECTION_LEFT)
	_fill(_col_right, SECTION_RIGHT)
	_close_btn.pressed.connect(_on_close_pressed)


func open() -> void:
	show()
	move_to_front()


func _on_close_pressed() -> void:
	hide()
	closed.emit()


func _fill(column: VBoxContainer, sections: Array) -> void:
	for section in sections:
		var heading := Label.new()
		heading.text = section[0]
		heading.add_theme_font_size_override("font_size", 17)
		heading.add_theme_color_override("font_color", GOLD)
		column.add_child(heading)
		for line in section[1]:
			var body := Label.new()
			body.text = line
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("font_size", 13)
			body.add_theme_color_override("font_color", IVORY)
			body.custom_minimum_size = Vector2(LINE_WIDTH, 0)
			column.add_child(body)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		column.add_child(gap)

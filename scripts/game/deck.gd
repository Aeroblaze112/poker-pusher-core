extends RefCounted

## 一副牌怎么凑：数字牌、效果牌、大小王，按人数模式决定规模。
## 只负责造牌，不碰局内状态——洗牌和发牌由主控做。

## 各人数模式的牌具构成
const MODE_DECK := {
	2: {"max_rank": 5, "effect_copies": 1},   # 2 人：数字牌只取 1-5，功能牌减半
	4: {"max_rank": 10, "effect_copies": 2},
	5: {"max_rank": 10, "effect_copies": 2},
	6: {"max_rank": 10, "effect_copies": 2},
}

const DIGIT_MIN := 1
const EFFECT_MIN := 11
const EFFECT_MAX := 13


## 造一副牌：返回 {number, effects, jokers, cfg}，各堆都没洗。
static func build(player_count: int) -> Dictionary:
	var cfg: Dictionary = MODE_DECK.get(player_count, MODE_DECK[4])
	var number: Array = []
	var effects: Array = []
	var jokers: Array = []

	for suit in 4:
		for rank in range(DIGIT_MIN, int(cfg.max_rank) + 1):
			number.append(PCard.new(rank, suit))

	# 4/5/6 人每种 8 张共 24 张；2 人减半共 12 张
	for copy in int(cfg.effect_copies):
		for suit in 4:
			for rank in range(EFFECT_MIN, EFFECT_MAX + 1):
				var card := PCard.new(rank, suit)
				card.copy = copy
				effects.append(card)

	jokers.append(PCard.new(14, -1))   # 小王 → 黑色
	jokers.append(PCard.new(15, -1))   # 大王 → 红色
	return {"number": number, "effects": effects, "jokers": jokers, "cfg": cfg}

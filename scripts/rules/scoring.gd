class_name Scoring
extends RefCounted

## 构筑组计分规则（纯函数，无副作用）
## 基准 = 在 {最大单张, 最大对子和, 最大三张和, 顺子和} 中取最大；
## 顺子被选为基准时，同花/同色改判顺子内部；
## 之后逐级叠乘并向下取整。

static func score_build(cards: Array, joker_color: int) -> Dictionary:
	if cards.is_empty():
		return {"pts": 0, "text": "无牌"}

	var ranks: Array = []
	var suits: Array = []
	for c in cards:
		ranks.append(c.rank)
		suits.append(c.suit)
	var notes: Array = []

	var uniq := ranks.duplicate()
	uniq.sort()
	var freq := {}
	for r in ranks:
		freq[r] = freq.get(r, 0) + 1

	# 顺子检测（去重后最长连续序列；等长时取点数和更大的那段）
	var best: Array = []
	var cur: Array = []
	for i in uniq.size():
		if i > 0 and uniq[i] == uniq[i - 1] + 1:
			cur.append(uniq[i])
		else:
			if _run_better(cur, best):
				best = cur.duplicate()
			cur = [uniq[i]]
	if _run_better(cur, best):
		best = cur.duplicate()
	var straight_sum := 0
	if best.size() >= 3:
		for r in best:
			straight_sum += r

	# 对子 / 三张的和
	var max_pair_sum := 0
	var max_triple_sum := 0
	for r in freq:
		if freq[r] >= 2:
			max_pair_sum = maxi(max_pair_sum, r * 2)
		if freq[r] >= 3:
			max_triple_sum = maxi(max_triple_sum, r * 3)

	# 基准四选一取最大
	var pts: int = uniq[-1]
	var base_kind := "最大牌%d" % pts
	if max_pair_sum > pts:
		pts = max_pair_sum
		base_kind = "对子%d" % max_pair_sum
	if max_triple_sum > pts:
		pts = max_triple_sum
		base_kind = "三张%d" % max_triple_sum
	var scope: Array = cards
	if best.size() >= 3 and straight_sum > pts:
		pts = straight_sum
		base_kind = "顺子%s" % str(best)
		scope = []
		for r in best:
			for c in cards:
				if c.rank == r:
					scope.append(c)
					break
	notes.append("基准%s＝%d" % [base_kind, pts])

	# 同花 / 同色（只取大者；顺子时仅判顺子内部）
	var same_suit := true
	var same_color := true
	var col0: int = scope[0].color()
	for c in scope:
		if c.suit != scope[0].suit:
			same_suit = false
		if c.color() != col0:
			same_color = false
	# 单张不构成同花/同色（同花至少两张），否则任何单张都会被白送 ×2
	if scope.size() < 2:
		same_suit = false
		same_color = false
	if same_suit:
		pts = floori(pts * 2.0)
		notes.append("同花×2")
	elif same_color:
		pts = floori(pts * 1.2)
		notes.append("同色×1.2")

	# 对子 / 三张倍数（最大牌与其余）
	var top_rank: int = uniq[-1]
	var top_card: PCard = null
	for c in cards:
		if c.rank == top_rank:
			top_card = c
			break
	if freq[top_rank] >= 3:
		pts = floori(pts * 3.0)
		notes.append("最大牌三张×3")
	elif freq[top_rank] == 2:
		pts = floori(pts * 2.0)
		notes.append("最大牌对子×2")
	var other_pair := false
	var other_triple := false
	for r in freq:
		if r == top_rank:
			continue
		if freq[r] >= 3:
			other_triple = true
		elif freq[r] == 2:
			other_pair = true
	if other_triple:
		pts = floori(pts * 2.0)
		notes.append("其余三张×2")
	elif other_pair:
		pts = floori(pts * 1.5)
		notes.append("其余对子×1.5")

	# 与王同色（同花/同色只取大者叠一次，避免同一属性乘两遍）
	if same_suit and col0 == joker_color:
		pts = floori(pts * 1.2)
		notes.append("同花与王同色×1.2")
	elif same_color and col0 == joker_color:
		pts = floori(pts * 1.2)
		notes.append("同色与王同色×1.2")
	if top_card != null and top_card.color() == joker_color:
		pts = floori(pts * 1.2)
		notes.append("最大牌与王同色×1.2")

	return {"pts": pts, "text": " × ".join(notes)}


## 顺子候选比较：先比长度，等长时比点数和（取更大的那段）
static func _run_better(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return a.size() > b.size()
	var sa := 0
	for r in a:
		sa += r
	var sb := 0
	for r in b:
		sb += r
	return sa > sb


## 构筑组是否包含点数 3、2、5 各至少一张
static func has_325(deck: Array) -> bool:
	var has2 := false
	var has3 := false
	var has5 := false
	for c in deck:
		if c.rank == 2:
			has2 = true
		elif c.rank == 3:
			has3 = true
		elif c.rank == 5:
			has5 = true
	return has2 and has3 and has5

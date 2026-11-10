class_name CardAI
extends RefCounted

## AI 决策（纯函数，无副作用）
## 策略：random 纯随机 / high 留大牌 / high2 高牌+智能效果牌取舍 / greedy 枚举组合最优
## kind: fix（固定 1 张）/ eff（弃桌上效果牌 1 张）/ jdrop（被「弃」效果弃 1 张手牌）/ fill（结算填牌）

static func pick_one(p: PPlayer, kind: String, legal: Array, joker_color: int) -> PCard:
	match p.strat:
		"greedy":
			match kind:
				"fix":
					var best_c: PCard = legal[0]
					var best_v := -1e9
					for c in legal:
						var v := float(_deck_score(p.build + [c], joker_color)) + _fix_potential(p, c, joker_color)
						if v > best_v:
							best_v = v
							best_c = c
					return best_c
				"eff":
					return _smart_eff(p, legal)
				"jdrop":
					return _lowest_card(legal)
		"high":
			match kind:
				"eff":
					return _random_card(legal)
				"jdrop":
					return _lowest_card(legal)
				_:
					return _highest_card(legal)
		"high2":  # 高牌 + 智能效果牌取舍
			match kind:
				"eff":
					return _smart_eff(p, legal)
				"jdrop":
					return _lowest_card(legal)
				_:
					return _highest_card(legal)
	return _random_card(legal)


## kind: fill（结算时从手牌选 n 张填入构筑组）
static func pick_many(p: PPlayer, kind: String, legal: Array, n: int, joker_color: int) -> Array:
	match p.strat:
		"greedy":
			# 枚举所有 n 张组合（组合数可控时），取构筑组得分最高
			# 注意：lambda 对外部标量是按值捕获，回写不生效，所以用数组当累加器
			if legal.size() <= 9 and n <= 5:
				var acc: Array = [[], -1]
				_enum_combos(legal, n, 0, [], func(combo: Array) -> void:
					var v := _deck_score(p.build + combo, joker_color)
					if v > int(acc[1]):
						acc[0] = combo.duplicate()
						acc[1] = v)
				var best_combo: Array = acc[0]
				return best_combo.duplicate()
			# 退化：按点数贪心
			return _top_n_by_rank(legal, n)
		"high", "high2":
			return _top_n_by_rank(legal, n)
		_:
			var pool: Array = legal.duplicate()
			pool.shuffle()
			return pool.slice(0, n)


static func _enum_combos(cards: Array, n: int, start: int, cur: Array, cb: Callable) -> void:
	if cur.size() == n:
		cb.call(cur)
		return
	for i in range(start, cards.size()):
		cur.append(cards[i])
		_enum_combos(cards, n, i + 1, cur, cb)
		cur.pop_back()


static func _deck_score(cards: Array, joker_color: int) -> int:
	return Scoring.score_build(cards, joker_color).pts


## 固定牌时的未来潜力加分：与王同色 + 手牌协同（顺子/同花/同色潜力）
static func _fix_potential(p: PPlayer, c: PCard, joker_color: int) -> float:
	var bonus := 0.0
	if c.color() == joker_color:
		bonus += 3.0
	for h in p.hand:
		if h == c:
			continue
		if absi(h.rank - c.rank) == 1:
			bonus += 2.0   # 顺子潜力
		if h.suit == c.suit:
			bonus += 1.0   # 同花潜力
		elif h.color() == c.color():
			bonus += 0.5   # 同色潜力
	return bonus


## 效果牌取舍：手牌少先弃「弃」自保；手牌不多时弃「杠」（用不上额外牌位）
static func _smart_eff(p: PPlayer, legal: Array) -> PCard:
	var js: Array = legal.filter(func(c: PCard) -> bool: return c.rank == 11)
	var ks: Array = legal.filter(func(c: PCard) -> bool: return c.rank == 13)
	if p.hand.size() <= 2 and not js.is_empty():
		return js[0]
	if p.hand.size() <= p.perm_slots() + p.temp_slots and not ks.is_empty():
		return ks[0]
	if not js.is_empty() and p.hand.size() <= 4:
		return js[randi_range(0, js.size() - 1)]
	return _random_card(legal)


static func _top_n_by_rank(legal: Array, n: int) -> Array:
	var pool := legal.duplicate()
	pool.sort_custom(func(a: PCard, b: PCard) -> bool: return a.rank > b.rank)
	return pool.slice(0, n)


static func _lowest_card(cards: Array) -> PCard:
	var best: PCard = cards[0]
	for c in cards:
		if c.rank < best.rank:
			best = c
	return best


static func _highest_card(cards: Array) -> PCard:
	var best: PCard = cards[0]
	for c in cards:
		if c.rank > best.rank:
			best = c
	return best


static func _random_card(cards: Array) -> PCard:
	return cards[randi_range(0, cards.size() - 1)]

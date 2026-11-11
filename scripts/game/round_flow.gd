extends RefCounted

## 一回合的五个阶段：发牌 → 固定 → 效果牌 → 结算 → 清理。
## 这里只写流程，牌堆、玩家、UI 都是主控的（game 上）。

const Audio := preload("res://scripts/game/audio.gd")

var game   # 主控 DemoGame，取 players / 牌堆 / ui / 日志用


func _init(owner_game) -> void:
	game = owner_game


## 本回合是否为最终回合：第 4 回合 / 弃空手牌 / 摸牌不够 / 构筑牌组满员（临时牌位不计）
func is_final_round() -> bool:
	if game.final_triggered or game.round_num >= 4:
		return true
	for p in game.players:
		if p.perm_slots() <= 0:
			return true
	return false


func deal() -> void:
	game.glog("\n===== 回合 %d · 开始 =====" % game.round_num)
	if game.round_num == 1:
		await _deal_first_round()
	else:
		await _deal_refill()
	game.glog("发牌完成")


func deal_first_round() -> void:
	# 抽王定本局颜色
	var idx := randi_range(0, game.jokers.size() - 1)
	game.joker_card = game.jokers[idx]
	game.jokers.remove_at(idx)
	game.joker_color = 1 if game.joker_card.rank == 15 else 0
	game.glog("抽出【%s】→ 第 1 回合固定牌必须为%s色" % [game.joker_card.txt(), "红" if game.joker_color == 1 else "黑"])
	game._refresh_labels()
	await game._pause(0.8)
	# 每人 4 张数字牌（4 花色各一，转圈发，同花色弃堆1重抽）
	if _pool_size() < game.players.size() * 4:
		game.glog("剩余牌不足发一圈（需 %d 张）→ 本回合所有人不发牌" % (game.players.size() * 4))
		return
	for pass_i in 4:
		for p in game.players:
			await _deal_one_restricted(p)
			await game._pause(0.06)
		game._refresh_all()
		await game._pause(0.22)


func _deal_first_round() -> void:
	await deal_first_round()


func _deal_refill() -> void:
	# 每人按各自空位补牌（空位 + 1 张留给固定），无花色限制；
	# 最终回合至少 2 张：即使牌位已满，也能靠「杠」给的临时牌位用上第二张
	var is_final := is_final_round()
	var needs: Array = []
	var total := 0
	for p in game.players:
		var n: int = maxi(p.perm_slots(), 2 if is_final else 0)
		needs.append(n)
		total += n
	if _pool_size() < total:
		game.glog("剩余牌不足补牌（需 %d 张）→ 本回合所有人不发牌" % total)
		return
	if is_final:
		game.glog("最终回合：每人按空位补牌、至少 2 张（无花色限制）")
	else:
		game.glog("每人按空位补牌（无花色限制）")
	var max_n: int = needs.max()
	for i in max_n:
		for pi in game.players.size():
			if i < needs[pi]:
				await _deal_one_free(game.players[pi])
				await game._pause(0.06)
		game._refresh_all()
		await game._pause(0.2)


## 可用总牌数 = 抽牌堆 + 弃牌堆1
func _pool_size() -> int:
	return game.number_pile.size() + game.discard1.size()


## 牌池中是否还有玩家手里没有的花色（防同花色重抽死循环）
func _pool_has_new_suit(p: PPlayer) -> bool:
	var held := {}
	for h in p.hand:
		held[h.suit] = true
	for c in game.number_pile + game.discard1:
		if not held.has(c.suit):
			return true
	return false


func _deal_one_restricted(p: PPlayer) -> void:
	if not _pool_has_new_suit(p):
		# 极端情况：整池牌都与手牌同花色，继续重抽会死循环 → 放弃花色限制
		game.glog("★ 牌池中已无新花色可发给 %s → 放弃花色限制直接发牌" % p.pname)
		await _deal_one_free(p)
		return
	while true:
		var c: PCard = _draw_number()
		if c == null:
			return  # 兜底：发牌前已检查够发一圈，正常到不了这里
		var has_suit := false
		for h in p.hand:
			if h.suit == c.suit:
				has_suit = true
				break
		if has_suit:
			game.discard1.append(c)
			if p.is_human:
				game.glog("你抽到 %s，与手中同花色 → 弃入弃牌堆1，重抽" % c.txt())
			game._refresh_labels()
			await game._pause(0.25)
		else:
			p.hand.append(c)
			game._anim_deal(p)   # 不 await：一圈人错峰发牌，别让每个人轮流等一次飞牌
			return


func _deal_one_free(p: PPlayer) -> void:
	var c: PCard = _draw_number()
	if c == null:
		return
	p.hand.append(c)
	game._anim_deal(p)   # 同上：错峰飞牌，不阻塞流程


## 从数字堆抽 1 张；抽空则洗牌弃牌堆1；都空返回 null
func _draw_number() -> PCard:
	if game.number_pile.is_empty():
		if game.discard1.is_empty():
			return null
		game.number_pile = game.discard1
		game.discard1 = []
		game.number_pile.shuffle()
		game.glog("抽牌堆抽空 → 弃牌堆1洗回抽牌堆")
	if game.number_pile.is_empty():
		return null
	return game.number_pile.pop_back()


func fix() -> void:
	var restricted: bool = (game.round_num == 1)
	if restricted:
		game.glog("固定构筑牌：必须%s色" % ("红" if game.joker_color == 1 else "黑"))
	else:
		game.glog("固定构筑牌：无颜色限制")
	for p in game.players:
		var legal: Array = []
		for c in p.hand:
			if not restricted or c.color() == game.joker_color:
				legal.append(c)
		if legal.is_empty():
			game.glog("%s 无合法牌可固定！" % p.pname)
			continue
		var chosen: PCard = null
		if game._needs_pick(p):
			var res: Array = await game._request_pick("hand", p, 1, func(c: PCard) -> bool: return c in legal)
			chosen = res[0]
		else:
			chosen = CardAI.pick_one(p, "fix", legal, game.joker_color)
		p.hand.erase(chosen)
		p.build.append(chosen)
		game.glog("%s 固定了 1 张牌（已公开）" % p.pname)
		game._refresh_all()
		if not (game.SIM or game.AUTO):
			await game.ui.fly(game.ui.card_tex(chosen), game.ui.player_center(p), game.ui.center_of(game.ui.strip_of(game.players.find(p))), 0.4)
			Audio.play("fix")
			await game.ui.anim_fix(game.players.find(p))
		await game._pause(0.45)


func play_effects() -> void:
	# 桌上摆出效果牌
	var max_hand := 0
	for p in game.players:
		max_hand = maxi(max_hand, p.hand.size())
	var n: int = max_hand + game.players.size()
	n = mini(n, game.jqk_pile.size())
	game.table_cards.clear()
	var placed: Array = []
	for i in n:
		placed.append(game.jqk_pile.pop_back())
	game.table_cards.append_array(placed)
	game.glog("桌上放置 %d 张效果牌：%s" % [game.table_cards.size(), game._cards_txt(game.table_cards)])
	if not (game.SIM or game.AUTO):
		var tc: Vector2 = game.ui.center_of(game.ui.table_row)
		for i in placed.size():
			var off := Vector2((i - (placed.size() - 1) / 2.0) * 60, 0)
			game.ui.fly(game.ui.card_tex(placed[i]), game.ui.center_of(game.ui.piles_label), tc + off, 0.32)
		await game.get_tree().create_timer(0.38).timeout
	game._refresh_table(true)
	await game._pause(0.8)

	# 每人选 1 张弃回效果牌堆
	for p in game.players:
		if game.table_cards.is_empty():
			break
		var chosen: PCard = null
		if game._needs_pick(p):
			var res2: Array = await game._request_pick("table", p, 1, func(_c: PCard) -> bool: return true)
			chosen = res2[0]
		else:
			chosen = CardAI.pick_one(p, "eff", game.table_cards, game.joker_color)
		game.table_cards.erase(chosen)
		game.jqk_pile.append(chosen)
		game.glog("%s 弃掉 1 张效果牌回牌堆" % p.pname)
		game._refresh_table(true)
		if not (game.SIM or game.AUTO):
			await game.ui.fly(game.ui.card_tex(chosen), game.ui.center_of(game.ui.table_row), game.ui.center_of(game.ui.piles_label), 0.3)
		await game._pause(0.4)

	# 剩余为场地效果，逐张结算
	game.jqk_pile.shuffle()
	game._refresh_labels()
	var field: Array = game.table_cards.duplicate()
	for fc in field:
		game._set_phase("效果：" + fc.txt())
		await game._anim_effect_pulse(fc)
		await _apply_effect(fc.rank)
		game.table_cards.erase(fc)
		game._refresh_table(false)
		await game._pause(0.6)
	# 结算过的效果牌洗回牌堆
	for fc in field:
		game.jqk_pile.append(fc)
	game.jqk_pile.shuffle()
	game.table_cards.clear()
	game._refresh_table(false)
	game._refresh_labels()
	game.glog("效果牌结算完毕，洗回效果牌堆")

	# 效果牌全部结算完后统一检查：有人空手 → 触发最终回合结算
	for p in game.players:
		if p.hand.is_empty():
			p.j_emptied = true
			game.final_triggered = true
			game.glog("★ %s 手牌已空 → 触发最终回合结算（得分×1.5）" % p.pname)


func _apply_effect(rank: int) -> void:
	if rank == 11:  # 弃
		game.glog("【弃】每人弃 1 张手牌入弃牌堆2")
		for p in game.players:
			if p.hand.is_empty():
				continue
			var chosen: PCard = null
			if game._needs_pick(p):
				var res3: Array = await game._request_pick("hand", p, 1, func(_c: PCard) -> bool: return true)
				chosen = res3[0]
			else:
				chosen = CardAI.pick_one(p, "jdrop", p.hand, game.joker_color)
			p.hand.erase(chosen)
			game.discard2.append(chosen)
			game.glog("%s 弃 %s 入弃牌堆2" % [p.pname, chosen.txt()])
			game._refresh_all()
			if not (game.SIM or game.AUTO):
				await game.ui.anim_effect_discard(p, chosen)
			await game._pause(0.25)
	elif rank == 12:  # 摸：每人 2 张，转圈发（每圈每人 1 张），防牌不均；不够一圈 → 全不发并终局
		for pass_i in 2:
			if _pool_size() < game.players.size():
				game.glog("★ 第 %d 圈牌不够发一圈 → 触发最终回合结算" % (pass_i + 1))
				game.final_triggered = true
				break
			game.glog("【摸】第 %d 圈：给所有人发 1 张" % (pass_i + 1))
			for p in game.players:
				if not (game.SIM or game.AUTO):
					await game.ui.anim_effect_draw(p)
				await _deal_one_free(p)
			game._refresh_all()
			await game._pause(0.3)
	elif rank == 13:  # 杠
		game.glog("【杠】本回合构筑牌组临时 +1 牌位")
		for p in game.players:
			p.temp_slots += 1
		game._refresh_all()


func settle() -> void:
	var is_final := is_final_round()
	if is_final:
		game.glog("★★ 最终回合结算，得分 ×1.5 ★★")
	# 第一段：各自填牌并计算本回合原始得分（暂不计入总分）
	var results: Array = []
	for p in game.players:
		var slots: int = p.perm_slots() + p.temp_slots
		var fill: Array = []
		if p.hand.size() <= slots:
			fill = p.hand.duplicate()
			p.hand.clear()
			if not fill.is_empty():
				game.glog("%s 将 %d 张手牌全部填入构筑组" % [p.pname, fill.size()])
		else:
			var picked: Array = []
			if game._needs_pick(p):
				picked = await game._request_pick("hand", p, slots, func(_c: PCard) -> bool: return true)
			else:
				picked = CardAI.pick_many(p, "fill", p.hand, slots, game.joker_color)
			for c in picked:
				p.hand.erase(c)
				fill.append(c)
			if not (game.SIM or game.AUTO) and not p.hand.is_empty():
				await game._anim_discard(p, p.hand[0])
			for c in p.hand:
				game.discard1.append(c)
			game.glog("%s 填 %d 张入构筑组，弃 %d 张入弃牌堆1" % [p.pname, fill.size(), p.hand.size()])
			p.hand.clear()
		p.temp_fill = fill
		# 原始得分（构筑组 = 固定牌 + 临时填入，内部已逐级取整）
		var all: Array = p.build + p.temp_fill
		var res := Scoring.score_build(all, game.joker_color)
		var pts: int = floori(res.pts * (1.5 if is_final else 1.0))
		results.append({"p": p, "pts": pts, "text": res.text, "deck": all})
	game._refresh_all()   # 先把填好的构筑组摆上台，再开始亮牌

	# 3-2-5 翻盘规则：构筑组首次出现 3/2/5 且本场得分全场最低 → 变为全场最高
	var round_min: int = 1 << 60
	var round_max: int = -(1 << 60)
	var top_i := 0
	for i in results.size():
		var r0: Dictionary = results[i]
		if r0.pts > round_max:
			round_max = r0.pts
			top_i = i
		round_min = mini(round_min, r0.pts)
	var steals: Array = []   # [最高分那家, 触发者, 分数]
	for i in results.size():
		var r: Dictionary = results[i]
		var p: PPlayer = r.p
		if p.had_325 or not Scoring.has_325(r.deck):
			continue
		p.had_325 = true
		if r.pts <= round_min and round_max > r.pts:
			game.glog("★【3-2-5】%s 构筑组首次出现 3-2-5，且本场结算最低（%d）→ 本回合得分变为全场最高 %d！" % [p.pname, r.pts, round_max])
			r.pts = round_max
			steals.append([top_i, i, round_max])

	# 结算动画：全场一起亮牌 → 325 的影子飞过去 → 再逐家加分
	if not (game.SIM or game.AUTO):
		var idxs: Array = []
		for r2 in results:
			idxs.append(game.players.find(r2.p))
		await game.ui.anim_settle_all(idxs)
		for st in steals:
			await game.ui.anim_325(game.players.find(results[st[0]].p), game.players.find(results[st[1]].p), st[2])

	# 第二段：统一计入总分
	for i in results.size():
		var r: Dictionary = results[i]
		var p: PPlayer = r.p
		p.score += r.pts
		game.glog("%s 本回合得分 %d（%s）→ 总分 %d" % [p.pname, r.pts, r.text, p.score])
		game._refresh_all()
		if not (game.SIM or game.AUTO) and r.pts > 0:
			Audio.play("gain", -2.0)
			await game.ui.anim_score_gain(game.players.find(p), r.pts, game.ui.C_GOLD if r.pts == round_max else game.ui.C_IVORY)
		await game._pause(0.2)

	if is_final and not (game.SIM or game.AUTO):
		await game.ui.anim_final_boost()


func cleanup() -> void:
	for p in game.players:
		if not (game.SIM or game.AUTO) and not p.temp_fill.is_empty():
			game.ui.fly(game.ui.card_tex(p.temp_fill[0]), game.ui.center_of(game.ui.strip_of(game.players.find(p))), game.ui.center_of(game.ui.piles_label), 0.35)
		for c in p.temp_fill:
			game.discard1.append(c)
		p.temp_fill.clear()
		p.temp_slots = 0
	game.glog("临时构筑牌已弃入弃牌堆1，进入下一回合")
	game._refresh_all()

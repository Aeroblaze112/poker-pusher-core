extends Control

## 《我说推扑克特别有说法》主控制器
## 职责：游戏状态 + 回合流程编排 + 人类输入协调
##   数据类：PCard / PPlayer（scripts/data/）
##   计分规则：Scoring（scripts/rules/scoring.gd）
##   AI 决策：CardAI（scripts/ai/card_ai.gd）
##   界面动画：GameUI（scripts/ui/game_ui.gd）
## 命令行：--autoplay 自动跑一局；--sim --games N --players M --s0..s5 策略 [--seed N] 批量模拟
## 联机：--net host|join [--ip A] [--port P]；--autonet 联机自动应答（无头测试），--expect N 主机人齐自动开局

const DIFFICULTIES := {
	"easy": "random",     # 初级：纯随机
	"normal": "high",     # 高级：高牌流
	"hard": "high2",      # 智能择（效果牌智能取舍）
}

## 各人数模式的牌具构成（5/6 人与 4 人共用 66 张牌，冗余规则为多人多模态预留）
const MODE_DECK := {
	2: {"max_rank": 5, "effect_copies": 1},   # 2 人：数字牌只取 1-5，功能牌减半
	3: {"max_rank": 10, "effect_copies": 2},  # 3 人：联机兜底，牌具同 4 人
	4: {"max_rank": 10, "effect_copies": 2},
	5: {"max_rank": 10, "effect_copies": 2},
	6: {"max_rank": 10, "effect_copies": 2},
}
const PLAYER_COUNTS := [2, 4, 5, 6]
const MAX_PLAYERS := 6

# ============================== 游戏状态 ==============================
var players: Array = []          # Array[PPlayer]
var number_pile: Array = []      # 数字抽牌堆
var discard1: Array = []         # 弃牌堆 1（可洗回）
var discard2: Array = []         # 弃牌堆 2（永不回洗）
var jqk_pile: Array = []         # 效果牌堆（弃/摸/杠）
var jokers: Array = []           # 大小王
var joker_card: PCard = null     # 抽出的王
var joker_color := 0             # 王指定颜色 0黑 1红
var table_cards: Array = []      # 桌上效果牌
var round_num := 1
var final_triggered := false     # 是否因「弃」效果弃空手牌而进入最终结算（牌堆抽空不再触发，改为跳过）
var game_over := false
var AUTO := false                # 自动模式（人类座位也随机决策）
var SIM := false                 # 批量模拟模式（无 UI、无日志、策略跑多局）
var ai_strat := "hard"           # 本局难度键（对应 DIFFICULTIES）
var player_count := 4            # 本局人数（2/4/5/6）
var seat_strats: Array = ["random", "random", "random", "random", "random", "random"]
var _sim_games := 1              # SIM：批量对局数
var _last_winners: Array = []    # SIM：上一局的获胜者（可能并列）

var ui: GameUI
var net: NetSession

# 联机
const NET_OFF := 0
const NET_HOST := 1
const NET_CLIENT := 2
var net_role := NET_OFF
var AUTONET := false          # 联机自动应答（无头测试用）
var _net_seat := 0            # 本端座位号
var _net_expect := 2          # AUTONET 主机等人齐自动开局的人数
var _net_arg := ""
var _net_ip := "127.0.0.1"
var _net_port := NetSession.DEFAULT_PORT
var _net_name := ""
var _net_started := false      # 主机：本局是否已开打（区分大厅/对局中的 hello）
var _log_history: Array = []   # 主机：日志 backlog，重连续传用
var _log_file := ""            # 测试用：日志直写文件（进程被杀也不丢）

# 用户系统
var user_db: UserDB
var current_user := ""         # 已登录用户名（空 = 游客）
var _cli_user := ""
var _cli_pwd := ""
var _stats_recorded := false   # 每局只记一次战绩

# 选择请求
signal sig_pick_done(picked: Array)
var _request: Dictionary = {}
var _picked: Array = []


func _ready() -> void:
	randomize()
	# Godot 4 中引擎参数与用户参数（-- 之后）分开返回，两处都要读
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	AUTO = args.has("--autoplay") or args.has("--autonet")
	SIM = args.has("--sim")
	AUTONET = args.has("--autonet")
	for i in args.size():
		if args[i] == "--games" and i + 1 < args.size():
			_sim_games = int(args[i + 1])
		if args[i] == "--seed" and i + 1 < args.size():
			seed(int(args[i + 1]))
		if args[i] == "--players" and i + 1 < args.size():
			var n := int(args[i + 1])
			if n in PLAYER_COUNTS:
				player_count = n
		if args[i] == "--net" and i + 1 < args.size():
			_net_arg = args[i + 1]
		if args[i] == "--ip" and i + 1 < args.size():
			_net_ip = args[i + 1]
		if args[i] == "--port" and i + 1 < args.size():
			_net_port = int(args[i + 1])
		if args[i] == "--expect" and i + 1 < args.size():
			_net_expect = int(args[i + 1])
		if args[i] == "--name" and i + 1 < args.size():
			_net_name = args[i + 1]
		if args[i] == "--logfile" and i + 1 < args.size():
			_log_file = args[i + 1]
		if args[i] == "--user" and i + 1 < args.size():
			_cli_user = args[i + 1]
		if args[i] == "--pwd" and i + 1 < args.size():
			_cli_pwd = args[i + 1]
		for s in MAX_PLAYERS:
			if args[i] == "--s%d" % s and i + 1 < args.size():
				seat_strats[s] = args[i + 1]
	if args.has("--usertest"):  # 用户系统单元测试（独立测试库，不碰真实存档）
		_run_usertest()
		return
	if SIM:
		Engine.max_fps = 1000  # 模拟模式每个 await 消耗一帧，放开帧率上限加速批量对局
		_sim_run()
		return
	net = NetSession.new()
	net.game = self
	add_child(net)
	net.lobby_changed.connect(_on_lobby_changed)
	net.game_started.connect(_on_net_started)
	net.state_received.connect(apply_net_state)
	net.hand_received.connect(_on_net_hand)
	net.pick_requested.connect(_on_net_pick_req)
	net.log_received.connect(_on_net_log)
	net.connection_failed.connect(_on_net_failed)
	net.peer_dropped.connect(_on_peer_dropped)
	net.hello_received.connect(_on_hello)
	net.rejoined.connect(_on_net_rejoined)
	net.rejected.connect(_on_net_rejected)
	net.log_backlog_received.connect(_on_log_backlog)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	ui = GameUI.new()
	ui.game = self
	ui.player_count = player_count
	ui.build()
	ui.card_clicked.connect(_on_card_clicked)
	ui.confirm_pressed.connect(_on_confirm)
	ui.difficulty_chosen.connect(_start_game)
	ui.host_requested.connect(net_host)
	ui.join_requested.connect(net_join)
	ui.start_net_requested.connect(net_start)
	ui.restart_requested.connect(_on_restart_requested)
	ui.reconnect_requested.connect(_on_reconnect)
	user_db = UserDB.new()
	ui.login_requested.connect(_on_login)
	ui.register_requested.connect(_on_register)
	ui.logout_requested.connect(_on_logout)
	if _cli_user != "":  # 命令行直接登录（测试用）：不存在则顺手注册
		var err := user_db.login(_cli_user, _cli_pwd)
		if err == "用户不存在":
			err = user_db.register(_cli_user, _cli_pwd)
			if err == "":
				err = user_db.login(_cli_user, _cli_pwd)
		if err == "":
			_apply_login(_cli_user)
		_tlog("CLI LOGIN user=%s err=%s" % [_cli_user, err if err != "" else "OK"])
	elif user_db.load_session() != "":  # 上次登录过的账号，本机免密自动登录
		_apply_login(user_db.load_session())
	if _net_name == "":  # 命令行未指定名字时，读取上次用过的联机名字（重连凭名字入座）
		var nf := FileAccess.open("user://poker_net.cfg", FileAccess.READ)
		if nf:
			_net_name = nf.get_as_text().strip_edges()
			ui.set_default_name(_net_name)
	if _net_arg == "host":
		net_host(_net_port, _default_name("主机"))
	elif _net_arg == "join":
		net_join(_net_ip, _net_port, _default_name("玩家"))
	if AUTO and net_role == NET_OFF:  # 自动验证模式直接以高级开局，跳过难度界面
		ai_strat = "hard"
		var overlay := get_node_or_null("StartOverlay")
		if overlay:
			overlay.queue_free()
		_reset_game()
		_run()
		if args.has("--shot"):  # 调试：跑若干帧后截屏
			for i in 90:
				await get_tree().process_frame
			if args.has("--uitest"):
				ui.show_d2()
				ui.log_popup.show()
				await get_tree().process_frame
			var tex := get_viewport().get_texture()
			if tex == null:
				print("SHOT skipped: 无渲染目标（headless 模式下无法截屏）")
			else:
				var img := tex.get_image()
				var p := ProjectSettings.globalize_path("res://_debug_shot.png")
				img.save_png(p)
				print("SHOT saved: " + p)
			get_tree().quit()
	# 正常模式：显示难度选择界面，选定后开局
	if args.has("--shotmenu"):  # 调试：给开局菜单截屏（需窗口模式）
		for i in 30:
			await get_tree().process_frame
		var tex2 := get_viewport().get_texture()
		if tex2 != null:
			var p2 := ProjectSettings.globalize_path("res://_debug_menu.png")
			tex2.get_image().save_png(p2)
			print("SHOT saved: " + p2)
		get_tree().quit()


func _start_game(key: String) -> void:
	ai_strat = key
	player_count = ui.selected_count
	ui.set_player_count(player_count)
	var overlay := get_node_or_null("StartOverlay")
	if overlay:
		overlay.queue_free()
	_reset_game()
	_run()


# ============================== 初始化 ==============================
func _reset_game() -> void:
	players.clear()
	number_pile.clear()
	discard1.clear()
	discard2.clear()
	jqk_pile.clear()
	jokers.clear()
	joker_card = null
	table_cards.clear()
	_stats_recorded = false
	round_num = 1
	final_triggered = false
	game_over = false
	_last_winners.clear()
	for i in player_count:
		var p := PPlayer.new()
		if net_role == NET_HOST:  # 联机：座位名册固定，远端真人走 RPC
			p.pname = net.seat_names[i]
			p.net_name = net.seat_names[i]
			p.peer_id = net.seat_peers[i]
			p.is_human = true
			p.strat = "human"
			if not net.is_peer_alive(p.peer_id):  # 掉线未归的座位直接以 AI 开局
				p.dropped = true
				p.is_human = false
				p.strat = "high2"
		else:
			p.pname = "你" if i == 0 else "对手%d" % i
			p.is_human = (i == 0)
			p.strat = seat_strats[i] if SIM else ("human" if i == 0 else DIFFICULTIES[ai_strat])
		players.append(p)
	var deck_cfg: Dictionary = MODE_DECK[player_count]
	for s in 4:
		for r in range(1, int(deck_cfg.max_rank) + 1):
			number_pile.append(PCard.new(r, s))
	for copy in int(deck_cfg.effect_copies):  # 4/5/6 人每种 8 张共 24 张；2 人减半共 12 张
		for s in 4:
			for r in range(11, 14):
				var ec := PCard.new(r, s)
				ec.copy = copy
				jqk_pile.append(ec)
	jokers.append(PCard.new(14, -1))  # 小王 → 黑色
	jokers.append(PCard.new(15, -1))  # 大王 → 红色
	number_pile.shuffle()
	jqk_pile.shuffle()


# ============================== 主流程 ==============================
func _run() -> void:
	await _pause(0.5)
	await _play_game()


## 完整打一局（SIM 模式下可被反复调用）
func _play_game() -> void:
	while not game_over:
		_set_phase("发牌")
		await _phase_deal()
		if game_over:
			break
		_set_phase("固定构筑牌")
		await _phase_fix()
		_set_phase("效果牌阶段")
		await _phase_jqk()
		_set_phase("结算")
		await _phase_settlement()
		await _phase_cleanup()
		if _is_final_round():
			game_over = true
		else:
			round_num += 1
			await _pause(0.8)
	_show_end()


## 批量模拟：跑 _sim_games 局，统计各策略胜率
func _sim_run() -> void:
	var wins := {}
	var score_sum := {}
	var seat_win: Array = []
	seat_win.resize(player_count)
	seat_win.fill(0)
	for g in _sim_games:
		_reset_game()
		await _play_game()
		for w in _last_winners:
			wins[w.strat] = wins.get(w.strat, 0) + 1
		for i in player_count:
			var p: PPlayer = players[i]
			if p in _last_winners:
				seat_win[i] += 1
			score_sum[p.strat] = score_sum.get(p.strat, 0.0) + p.score
	print("SIMSUM games=%d" % _sim_games)
	var strats := wins.keys()
	strats.sort()
	for k in strats:
		print("SIMSUM strat=%s wins=%d avg_score=%.1f" % [k, wins[k], score_sum[k] / _sim_games])
	print("SIMSUM seat_wins=%s" % str(seat_win))
	get_tree().quit()


## 本回合是否为最终回合：第 4 回合 / 弃空手牌 / 摸牌不够 / 构筑牌组满员（临时牌位不计）
func _is_final_round() -> bool:
	if final_triggered or round_num >= 4:
		return true
	for p in players:
		if p.perm_slots() <= 0:
			return true
	return false


func _phase_deal() -> void:
	glog("\n===== 回合 %d · 开始 =====" % round_num)
	if round_num == 1:
		# 抽王
		var idx := randi_range(0, jokers.size() - 1)
		joker_card = jokers[idx]
		jokers.remove_at(idx)
		joker_color = 1 if joker_card.rank == 15 else 0
		glog("抽出【%s】→ 第 1 回合固定牌必须为%s色" % [joker_card.txt(), "红" if joker_color == 1 else "黑"])
		_refresh_labels()
		await _pause(0.8)
		# 每人 4 张数字牌（4 花色各一，转圈发，同花色弃堆1重抽）
		if _pool_size() < players.size() * 4:
			glog("剩余牌不足发一圈（需 %d 张）→ 本回合所有人不发牌" % (players.size() * 4))
			return
		for pass_i in 4:
			for p in players:
				await _deal_one_restricted(p)
			_refresh_all()
			await _pause(0.4)
	else:
		# 每人按各自空位补牌（空位 + 1 张留给固定），无花色限制；
		# 最终回合至少 2 张：即使牌位已满，也能靠「杠」给的临时牌位用上第二张
		var is_final := _is_final_round()
		var needs: Array = []
		var total := 0
		for p in players:
			var n: int = maxi(p.perm_slots(), 2 if is_final else 0)
			needs.append(n)
			total += n
		if _pool_size() < total:
			glog("剩余牌不足补牌（需 %d 张）→ 本回合所有人不发牌" % total)
			return
		if is_final:
			glog("最终回合：每人按空位补牌、至少 2 张（无花色限制）")
		else:
			glog("每人按空位补牌（无花色限制）")
		var max_n: int = needs.max()
		for i in max_n:
			for pi in players.size():
				if i < needs[pi]:
					await _deal_one_free(players[pi])
			_refresh_all()
			await _pause(0.3)
	glog("发牌完成")


## 可用总牌数 = 抽牌堆 + 弃牌堆1
func _pool_size() -> int:
	return number_pile.size() + discard1.size()


## 牌池中是否还有玩家手里没有的花色（防同花色重抽死循环）
func _pool_has_new_suit(p: PPlayer) -> bool:
	var held := {}
	for h in p.hand:
		held[h.suit] = true
	for c in number_pile + discard1:
		if not held.has(c.suit):
			return true
	return false


func _deal_one_restricted(p: PPlayer) -> void:
	if not _pool_has_new_suit(p):
		# 极端情况：整池牌都与手牌同花色，继续重抽会死循环 → 放弃花色限制
		glog("★ 牌池中已无新花色可发给 %s → 放弃花色限制直接发牌" % p.pname)
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
			discard1.append(c)
			if p.is_human:
				glog("你抽到 %s，与手中同花色 → 弃入弃牌堆1，重抽" % c.txt())
			_refresh_labels()
			await _pause(0.25)
		else:
			p.hand.append(c)
			await _anim_deal(p)
			return


func _deal_one_free(p: PPlayer) -> void:
	var c: PCard = _draw_number()
	if c == null:
		return
	p.hand.append(c)
	await _anim_deal(p)


## 从数字堆抽 1 张；抽空则洗牌弃牌堆1；都空返回 null
func _draw_number() -> PCard:
	if number_pile.is_empty():
		if discard1.is_empty():
			return null
		number_pile = discard1
		discard1 = []
		number_pile.shuffle()
		glog("抽牌堆抽空 → 弃牌堆1洗回抽牌堆")
	if number_pile.is_empty():
		return null
	return number_pile.pop_back()


func _phase_fix() -> void:
	var restricted := (round_num == 1)
	if restricted:
		glog("固定构筑牌：必须%s色" % ("红" if joker_color == 1 else "黑"))
	else:
		glog("固定构筑牌：无颜色限制")
	for p in players:
		var legal: Array = []
		for c in p.hand:
			if not restricted or c.color() == joker_color:
				legal.append(c)
		if legal.is_empty():
			glog("%s 无合法牌可固定！" % p.pname)
			continue
		var chosen: PCard = null
		if _needs_pick(p):
			var res: Array = await _request_pick("hand", p, 1, func(c: PCard) -> bool: return c in legal)
			chosen = res[0]
		else:
			chosen = CardAI.pick_one(p, "fix", legal, joker_color)
		p.hand.erase(chosen)
		p.build.append(chosen)
		glog("%s 固定了 1 张牌（已公开）" % p.pname)
		_refresh_all()
		if not (SIM or AUTO):
			await ui.fly(ui.card_tex(chosen), ui.player_center(p), ui.center_of(ui.strip_of(players.find(p))), 0.4)
		await _pause(0.5)


func _phase_jqk() -> void:
	var max_hand := 0
	for p in players:
		max_hand = maxi(max_hand, p.hand.size())
	var n: int = max_hand + players.size()
	n = mini(n, jqk_pile.size())
	table_cards.clear()
	var placed: Array = []
	for i in n:
		placed.append(jqk_pile.pop_back())
	table_cards.append_array(placed)
	glog("桌上放置 %d 张效果牌：%s" % [table_cards.size(), _cards_txt(table_cards)])
	if not (SIM or AUTO):
		var tc := ui.center_of(ui.table_row)
		for i in placed.size():
			var off := Vector2((i - (placed.size() - 1) / 2.0) * 60, 0)
			ui.fly(ui.card_tex(placed[i]), ui.center_of(ui.piles_label), tc + off, 0.32)
		await get_tree().create_timer(0.38).timeout
	_refresh_table(true)
	await _pause(0.8)

	# 每人选 1 张弃回效果牌堆
	for p in players:
		if table_cards.is_empty():
			break
		var chosen: PCard = null
		if _needs_pick(p):
			var res2: Array = await _request_pick("table", p, 1, func(_c: PCard) -> bool: return true)
			chosen = res2[0]
		else:
			chosen = CardAI.pick_one(p, "eff", table_cards, joker_color)
		table_cards.erase(chosen)
		jqk_pile.append(chosen)
		glog("%s 弃掉 1 张效果牌回牌堆" % p.pname)
		_refresh_table(true)
		if not (SIM or AUTO):
			await ui.fly(ui.card_tex(chosen), ui.center_of(ui.table_row), ui.center_of(ui.piles_label), 0.3)
		await _pause(0.4)

	# 剩余为场地效果，逐张结算
	jqk_pile.shuffle()
	_refresh_labels()
	var field := table_cards.duplicate()
	for fc in field:
		_set_phase("效果：" + fc.txt())
		await _anim_effect_pulse(fc)
		await _apply_effect(fc.rank)
		table_cards.erase(fc)
		_refresh_table(false)
		await _pause(0.6)
	# 结算过的效果牌洗回牌堆
	for fc in field:
		jqk_pile.append(fc)
	jqk_pile.shuffle()
	table_cards.clear()
	_refresh_table(false)
	_refresh_labels()
	glog("效果牌结算完毕，洗回效果牌堆")

	# 效果牌全部结算完后统一检查：有人空手 → 触发最终回合结算
	for p in players:
		if p.hand.is_empty():
			p.j_emptied = true
			final_triggered = true
			glog("★ %s 手牌已空 → 触发最终回合结算（得分×1.5）" % p.pname)


func _apply_effect(rank: int) -> void:
	if rank == 11:  # 弃
		glog("【弃】每人弃 1 张手牌入弃牌堆2")
		for p in players:
			if p.hand.is_empty():
				continue
			var chosen: PCard = null
			if _needs_pick(p):
				var res3: Array = await _request_pick("hand", p, 1, func(_c: PCard) -> bool: return true)
				chosen = res3[0]
			else:
				chosen = CardAI.pick_one(p, "jdrop", p.hand, joker_color)
			p.hand.erase(chosen)
			discard2.append(chosen)
			glog("%s 弃 %s 入弃牌堆2" % [p.pname, chosen.txt()])
			_refresh_all()
			await _anim_discard(p, chosen)
			await _pause(0.4)
	elif rank == 12:  # 摸：每人 2 张，转圈发（每圈每人 1 张），防牌不均；不够一圈 → 全不发并终局
		for pass_i in 2:
			if _pool_size() < players.size():
				glog("★ 第 %d 圈牌不够发一圈 → 触发最终回合结算" % (pass_i + 1))
				final_triggered = true
				break
			glog("【摸】第 %d 圈：给所有人发 1 张" % (pass_i + 1))
			for p in players:
				await _deal_one_free(p)
			_refresh_all()
			await _pause(0.3)
	elif rank == 13:  # 杠
		glog("【杠】本回合构筑牌组临时 +1 牌位")
		for p in players:
			p.temp_slots += 1
		_refresh_all()


func _phase_settlement() -> void:
	var is_final := _is_final_round()
	if is_final:
		glog("★★ 最终回合结算，得分 ×1.5 ★★")
	# 第一段：各自填牌并计算本回合原始得分（暂不计入总分）
	var results: Array = []
	for p in players:
		var slots: int = p.perm_slots() + p.temp_slots
		var fill: Array = []
		if p.hand.size() <= slots:
			fill = p.hand.duplicate()
			p.hand.clear()
			if not fill.is_empty():
				glog("%s 将 %d 张手牌全部填入构筑组" % [p.pname, fill.size()])
		else:
			var picked: Array = []
			if _needs_pick(p):
				picked = await _request_pick("hand", p, slots, func(_c: PCard) -> bool: return true)
			else:
				picked = CardAI.pick_many(p, "fill", p.hand, slots, joker_color)
			for c in picked:
				p.hand.erase(c)
				fill.append(c)
			if not (SIM or AUTO) and not p.hand.is_empty():
				await _anim_discard(p, p.hand[0])
			for c in p.hand:
				discard1.append(c)
			glog("%s 填 %d 张入构筑组，弃 %d 张入弃牌堆1" % [p.pname, fill.size(), p.hand.size()])
			p.hand.clear()
		p.temp_fill = fill
		# 原始得分（构筑组 = 固定牌 + 临时填入，内部已逐级取整）
		var all: Array = p.build + p.temp_fill
		var res := Scoring.score_build(all, joker_color)
		var pts: int = floori(res.pts * (1.5 if is_final else 1.0))
		results.append({"p": p, "pts": pts, "text": res.text, "deck": all})

	# 3-2-5 翻盘规则：构筑组首次出现 3/2/5 且本场得分全场最低 → 变为全场最高
	var round_min: int = 1 << 60
	var round_max: int = -(1 << 60)
	for r in results:
		round_min = mini(round_min, r.pts)
		round_max = maxi(round_max, r.pts)
	for r in results:
		var p: PPlayer = r.p
		if p.had_325 or not Scoring.has_325(r.deck):
			continue
		p.had_325 = true
		if r.pts <= round_min and round_max > r.pts:
			glog("★【3-2-5】%s 构筑组首次出现 3-2-5，且本场结算最低（%d）→ 本回合得分变为全场最高 %d！" % [p.pname, r.pts, round_max])
			r.pts = round_max

	# 第二段：统一计入总分
	for r in results:
		var p: PPlayer = r.p
		p.score += r.pts
		glog("%s 本回合得分 %d（%s）→ 总分 %d" % [p.pname, r.pts, r.text, p.score])
		_refresh_all()
		await _pause(0.7)


func _phase_cleanup() -> void:
	for p in players:
		if not (SIM or AUTO) and not p.temp_fill.is_empty():
			ui.fly(ui.card_tex(p.temp_fill[0]), ui.center_of(ui.strip_of(players.find(p))), ui.center_of(ui.piles_label), 0.35)
		for c in p.temp_fill:
			discard1.append(c)
		p.temp_fill.clear()
		p.temp_slots = 0
	glog("临时构筑牌已弃入弃牌堆1，进入下一回合")
	_refresh_all()


# ============================== 选择与输入 ==============================
## 该玩家是否需要"真人选牌"（本机 UI 或远端 RPC），否则交给 AI
func _needs_pick(p: PPlayer) -> bool:
	if SIM:
		return false
	if _is_remote_human(p):
		return true
	return p.is_human and not AUTO


func _is_remote_human(p: PPlayer) -> bool:
	return net_role == NET_HOST and p.peer_id > 0 and p.peer_id != multiplayer.get_unique_id()


func _request_pick(zone: String, p: PPlayer, n: int, filter: Callable) -> Array:
	if _is_remote_human(p):  # 远端真人：发 RPC 请求，挂起等待回传
		var pool: Array = p.hand if zone == "hand" else table_cards
		var legal_ids: Array = []
		for c in pool:
			if filter.call(c):
				legal_ids.append(c.to_net())
		var ids: Array = await net.request_remote_pick(p.peer_id, zone, n, legal_ids)
		if ids.is_empty():  # 对端已掉线（_on_peer_dropped 已将其转为 AI），本地代选
			var legal: Array = []
			for c in pool:
				if filter.call(c):
					legal.append(c)
			if legal.is_empty():
				return []
			if n <= 1:
				# 桌上效果牌按「弃效果牌」选，手牌单张按「固定」选
				return [CardAI.pick_one(p, "eff" if zone == "table" else "fix", legal, joker_color)]
			return CardAI.pick_many(p, "fill", legal, n, joker_color)
		var picked: Array = []
		for id in ids:
			for c in pool:
				if c.to_net() == id:
					picked.append(c)
					break
		return picked
	_request = {"zone": zone, "n": n, "filter": filter}
	_picked.clear()
	if p.is_human:
		set_prompt("请选择 %d 张%s" % [n, "手牌" if zone == "hand" else "桌上的牌"])
	ui.confirm_btn.visible = (p.is_human and n > 1)
	_refresh_table(zone == "table")
	_refresh_hand()
	var res: Array = await sig_pick_done
	_request = {}
	_picked.clear()
	ui.confirm_btn.visible = false
	set_prompt("")
	_refresh_table(false)
	_refresh_hand()
	return res


func _on_card_clicked(card: PCard, zone: String) -> void:
	if _request.is_empty():
		return
	if zone != _request.zone:
		return
	if _request.filter.is_valid() and not _request.filter.call(card):
		set_prompt("这张牌不符合当前要求，请重新选择")
		return
	var n: int = _request.n
	if n <= 1:
		sig_pick_done.emit([card])
	else:
		if card in _picked:
			_picked.erase(card)
		elif _picked.size() < n:
			_picked.append(card)
		set_prompt("已选 %d/%d 张，选好后点「确认」" % [_picked.size(), n])
		_refresh_hand()


func _on_confirm() -> void:
	if _request.is_empty():
		return
	if _picked.size() != _request.n:
		set_prompt("需要选满 %d 张（已选 %d 张）" % [_request.n, _picked.size()])
		return
	sig_pick_done.emit(_picked.duplicate())


# ============================== 联机：主机侧 ==============================
## 公开状态快照（不含任何玩家的手牌）
func _snapshot() -> Dictionary:
	var ps: Array = []
	for i in players.size():
		var p: PPlayer = players[i]
		ps.append({
			"seat": i, "name": p.pname, "score": p.score, "j_emptied": p.j_emptied,
			"build": p.build.map(func(c: PCard) -> int: return c.to_net()),
			"temp": p.temp_fill.map(func(c: PCard) -> int: return c.to_net()),
			"temp_slots": p.temp_slots, "hand_n": p.hand.size(),
			"dropped": p.dropped,
		})
	return {
		"round": round_num, "phase": ui.phase_label.text,
		"joker": joker_card.to_net() if joker_card != null else -1,
		"joker_color": joker_color,
		"piles": [number_pile.size(), discard1.size(), discard2.size(), jqk_pile.size()],
		"table": table_cards.map(func(c: PCard) -> int: return c.to_net()),
		"players": ps,
		"over": game_over,
		"prompt": ui.prompt_label.text,
	}


## 广播公开快照 + 向各远端玩家单独下发其手牌
func _net_broadcast() -> void:
	net.broadcast_state(_snapshot())
	for p in players:
		if _is_remote_human(p):
			net.send_hand(p.peer_id, p.hand.map(func(c: PCard) -> int: return c.to_net()))


func net_host(port: int, pname: String) -> void:
	if pname == "":
		pname = _default_name("主机")
	var err := net.host_game(port, pname)
	if err != OK:
		ui.set_lobby_status("创建主机失败：%s" % error_string(err))
		return
	_save_net_name(pname)
	net_role = NET_HOST
	ui.show_lobby(true)
	_tlog("HOST UP port=%d name=%s" % [port, pname])


func net_join(ip: String, port: int, pname: String) -> void:
	if pname == "":
		pname = _default_name("玩家")
	_net_ip = ip
	_net_port = port
	var err := net.join_game(ip, port, pname)
	if err != OK:
		ui.set_lobby_status("连接失败：%s" % error_string(err))
		return
	_save_net_name(pname)
	net_role = NET_CLIENT
	ui.show_lobby(false)
	_tlog("JOINING %s:%d name=%s" % [ip, port, pname])


func _default_name(prefix: String) -> String:
	if _net_name != "":
		return _net_name
	return "%s%d" % [prefix, randi_range(100, 999)]


func _save_net_name(pname: String) -> void:
	_net_name = pname
	var f := FileAccess.open("user://poker_net.cfg", FileAccess.WRITE)
	if f:
		f.store_string(pname)


# ============================== 用户系统 ==============================
func _on_login(pname: String, pwd: String) -> void:
	var err := user_db.login(pname, pwd)
	if err != "":
		ui.set_account_status(err)
		return
	_apply_login(pname.strip_edges())


func _on_register(pname: String, pwd: String) -> void:
	var err := user_db.register(pname, pwd)
	if err != "":
		ui.set_account_status(err)
		return
	_apply_login(pname.strip_edges())  # 注册成功即登录


func _on_logout() -> void:
	current_user = ""
	user_db.clear_session()
	ui.set_account("", {})


## 登录生效：记会话、锁联机名（联机座位身份 = 账号名）、刷新账户面板
func _apply_login(pname: String) -> void:
	current_user = pname
	user_db.save_session(pname)
	_net_name = pname
	_save_net_name(pname)
	ui.set_account(pname, user_db.stats_of(pname))


## 本端玩家战绩入账（主机/单机在终局结算后调；客户端在收到终局快照后调）
func _record_my_stats() -> void:
	if _stats_recorded or current_user == "" or players.is_empty():
		return
	var me: PPlayer = players[0]  # 本端玩家恒被旋到 0 号位
	if not me.is_human:
		return
	var best := 0
	for p in players:
		best = maxi(best, p.score)
	_stats_recorded = true
	user_db.record_game(current_user, me.score, me.score == best)
	ui.set_account(current_user, user_db.stats_of(current_user))
	_tlog("STATS user=%s score=%d won=%s" % [current_user, me.score, str(me.score == best)])


## --usertest：UserDB 单元测试（独立测试库，跑完即删，不碰真实存档）
func _run_usertest() -> void:
	var db_path := "user://test_users.json"
	var ss_path := "user://test_session.cfg"
	for p in [db_path, ss_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var fails: Array = []
	var ck := func(cond: bool, tag: String) -> void:
		if not cond:
			fails.append(tag)
	var db := UserDB.new(db_path, ss_path)
	# 注册与输入校验
	ck.call(db.register("测试甲", "1234") == "", "register ok")
	ck.call(db.register("测试甲", "9999") == "该名字已被注册", "dup rejected")
	ck.call(db.register("x", "1234") != "", "short name rejected")
	ck.call(db.register("a b", "1234") != "", "space name rejected")
	ck.call(db.register("测试乙", "12") != "", "short pwd rejected")
	# 登录
	ck.call(db.login("测试甲", "0000") == "密码错误", "wrong pwd")
	ck.call(db.login("没人", "1234") == "用户不存在", "no user")
	ck.call(db.login("测试甲", "1234") == "", "login ok")
	# 战绩统计
	db.record_game("测试甲", 100, true)
	db.record_game("测试甲", 130, false)
	var st := db.stats_of("测试甲")
	ck.call(int(st.get("games", 0)) == 2 and int(st.get("wins", 0)) == 1 and int(st.get("best", 0)) == 130 and int(st.get("last", 0)) == 130, "stats")
	# 落盘持久化：换实例重读
	var db2 := UserDB.new(db_path, ss_path)
	ck.call(db2.login("测试甲", "1234") == "", "reload login")
	ck.call(int(db2.stats_of("测试甲").get("games", 0)) == 2, "reload stats")
	# 密码不明文落盘
	var raw := FileAccess.open(db_path, FileAccess.READ).get_as_text()
	ck.call(raw.find("1234") < 0, "no plaintext pwd")
	# 会话：保存 / 读取 / 清除
	db2.save_session("测试甲")
	ck.call(db2.load_session() == "测试甲", "session save/load")
	db2.clear_session()
	ck.call(db2.load_session() == "", "session clear")
	for p in [db_path, ss_path]:  # 清理测试库
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	if fails.is_empty():
		print("USERTEST PASS")
	else:
		print("USERTEST FAIL: ", fails)
	get_tree().quit()


## 对端报到：大厅阶段登记入座；对局中按名字匹配重连座位
func _on_hello(peer_id: int, pname: String) -> void:
	if net_role != NET_HOST:
		return
	_tlog("HELLO peer=%d name=%s started=%s" % [peer_id, pname, str(_net_started)])
	if not _net_started:
		if pname in net.lobby_names:
			net.reject_client(peer_id, "名字已被占用，请换一个")
			return
		net.register_lobby_peer(peer_id, pname)
		return
	for i in players.size():
		var p: PPlayer = players[i]
		if p.net_name == pname:
			p.peer_id = peer_id
			p.is_human = true
			p.strat = "human"
			p.dropped = false
			net.seat_peers[i] = peer_id
			net.accept_rejoin(peer_id, i, _log_history)
			glog("★ %s 重连归来，继续本局" % pname)
			_net_broadcast()  # 立即补发快照 + 手牌
			return
	net.reject_client(peer_id, "对局进行中，且没有与「%s」匹配的座位" % pname)


## 对局中掉线：该座位转 AI 接管，对局继续
func _on_peer_dropped(peer_id: int) -> void:
	if net_role != NET_HOST or players.is_empty() or game_over:
		return  # 终局后玩家正常退出不算掉线
	for p in players:
		if p.peer_id == peer_id:
			p.peer_id = 0
			p.is_human = false
			p.strat = "high2"
			p.dropped = true
			glog("★ %s 掉线，本局由 AI 接管" % p.pname)
			_refresh_all()
			return


func _on_net_failed(reason: String) -> void:
	_tlog("NET FAILED %s" % reason)
	if get_node_or_null("StartOverlay") != null:
		ui.set_lobby_status(reason)
	elif net_role == NET_CLIENT:
		set_prompt(reason + "，可点右下角「重新连接」")
		ui.show_reconnect(true)


func _on_lobby_changed(names: Array, i_am_host: bool) -> void:
	_tlog("LOBBY %s host=%s" % [str(names), str(i_am_host)])
	if get_node_or_null("StartOverlay") == null:
		return  # 已开赛，大厅变动不再刷 UI
	ui.update_lobby(names, i_am_host)
	if AUTONET and net_role == NET_HOST and names.size() == _net_expect:
		call_deferred("_net_begin")


func net_start() -> void:
	if net_role == NET_HOST:
		_net_begin()


func _net_begin() -> void:
	if net.seat_peers.is_empty():  # 首局：按大厅报到顺序固定名册；重开沿用旧名册
		net.seat_peers = net.lobby_peers.duplicate()
		net.seat_names = net.lobby_names.duplicate()
	player_count = net.seat_names.size()
	_net_started = true
	_tlog("BEGIN players=%d names=%s" % [player_count, str(net.seat_names)])
	net.start_game(player_count)


func _on_net_started(seat: int, count: int, _names: Array) -> void:
	_net_seat = seat
	player_count = count
	_tlog("GAME START seat=%d count=%d role=%d" % [seat, count, net_role])
	ui.set_player_count(player_count)
	ui.show_reconnect(false)
	var overlay := get_node_or_null("StartOverlay")
	if overlay:
		overlay.queue_free()
	if net_role == NET_HOST:
		_reset_game()
		_run()
	else:
		_client_reset_local()


# ============================== 联机：客户端侧 ==============================
func apply_net_state(d: Dictionary) -> void:
	round_num = int(d.round)
	joker_color = int(d.joker_color)
	joker_card = PCard.from_net(int(d.joker)) if int(d.joker) >= 0 else null
	table_cards.clear()
	for id in d.table:
		table_cards.append(PCard.from_net(id))
	# 按座位重建玩家列表，并把本端座位旋到 0 号位（UI 恒以 0 号为"你"）
	var my_hand: Array = players[0].hand if not players.is_empty() else []
	var seats: Array = d.players
	players.clear()
	for k in seats.size():
		var sd: Dictionary = seats[(int(_net_seat) + k) % seats.size()]
		var p := PPlayer.new()
		p.pname = sd.name
		p.is_human = (k == 0)
		p.score = int(sd.score)
		p.j_emptied = sd.j_emptied
		for id in sd.build:
			p.build.append(PCard.from_net(id))
		for id in sd.temp:
			p.temp_fill.append(PCard.from_net(id))
		p.temp_slots = int(sd.temp_slots)
		p.dropped = sd.get("dropped", false)
		players.append(p)
	players[0].hand = my_hand
	ui.phase_label.text = str(d.phase)
	if _request.is_empty():
		set_prompt(str(d.prompt))
	game_over = d.over
	_refresh_all()
	if game_over:
		_record_my_stats()
		ui.restart_btn.visible = false
		if AUTONET:
			print("NETTEST CLIENT DONE")
			_tlog("NETTEST CLIENT DONE")
			get_tree().quit()


func _on_net_rejoined(seat: int, names: Array) -> void:
	_net_seat = seat
	player_count = names.size()
	ui.set_player_count(player_count)
	ui.show_reconnect(false)
	var overlay := get_node_or_null("StartOverlay")
	if overlay:
		overlay.queue_free()
	_client_reset_local()
	set_prompt("已重新连接，回到本局")
	_tlog("REJOINED seat=%d" % seat)


func _on_net_rejected(msg: String) -> void:
	_tlog("REJECTED %s" % msg)
	net_role = NET_OFF
	if get_node_or_null("StartOverlay") != null:
		ui.set_lobby_status("被主机拒绝：" + msg)
	else:
		set_prompt("被主机拒绝：" + msg)


func _on_log_backlog(lines: Array) -> void:
	ui.set_log_lines(lines)


func _client_reset_local() -> void:
	players.clear()
	table_cards.clear()
	joker_card = null
	game_over = false
	_request = {}
	_picked.clear()
	_stats_recorded = false
	ui.restart_btn.visible = false
	set_prompt("")
	_refresh_all()


func _on_restart_requested() -> void:
	if net_role == NET_HOST:
		_net_begin()  # 联机重开：沿用名册，全员重新开局
	elif net_role == NET_OFF:
		get_tree().reload_current_scene()


func _on_reconnect() -> void:
	ui.show_reconnect(false)
	net_join(_net_ip, _net_port, _default_name("玩家"))


func _on_net_hand(ids: Array) -> void:
	if players.is_empty() or not _request.is_empty():
		return  # 选牌进行中不覆盖手牌对象，避免破坏已选引用
	players[0].hand = ids.map(func(id: int) -> PCard: return PCard.from_net(id))
	_refresh_hand()


func _on_net_pick_req(req_id: int, zone: String, n: int, legal_ids: Array) -> void:
	if AUTONET:  # 无头测试：直接取前 n 张合法牌
		net.send_pick(req_id, legal_ids.slice(0, n))
		return
	_request = {"zone": zone, "n": n, "filter": func(c: PCard) -> bool: return c.to_net() in legal_ids}
	_picked.clear()
	set_prompt("请选择 %d 张%s" % [n, "手牌" if zone == "hand" else "桌上的牌"])
	ui.confirm_btn.visible = (n > 1)
	_refresh_table(zone == "table")
	_refresh_hand()
	var res: Array = await sig_pick_done
	_request = {}
	_picked.clear()
	ui.confirm_btn.visible = false
	set_prompt("")
	_refresh_table(false)
	_refresh_hand()
	net.send_pick(req_id, res.map(func(c: PCard) -> int: return c.to_net()))


func _on_net_log(t: String) -> void:
	ui.log_view.append_text(t + "\n")
	print(t)


# ============================== 终局 ==============================
func _show_end() -> void:
	var ranking := players.duplicate()
	ranking.sort_custom(func(a: PPlayer, b: PPlayer) -> bool: return a.score > b.score)
	var best: float = ranking[0].score
	_last_winners.clear()
	for p in ranking:
		if p.score == best:
			_last_winners.append(p)
	if SIM:
		return
	_set_phase("游戏结束")
	glog("\n===== 最终结算 =====")
	for i in ranking.size():
		var mark := "🏆" if ranking[i].score == best else "  "
		glog("%s 第%d名：%s  总分 %d" % [mark, i + 1, ranking[i].pname, ranking[i].score])
	var winners: Array = []
	for p in ranking:
		if p.score == best:
			winners.append(p.pname)
	glog("获胜者：%s" % "、".join(winners))
	set_prompt("游戏结束！获胜者：%s" % "、".join(winners))
	_record_my_stats()
	ui.restart_btn.visible = (net_role != NET_CLIENT)  # 联机由主机一键重开（沿用名册）
	_refresh_all()  # 广播终局快照，让客户端拿到 game_over
	if AUTONET and net_role == NET_HOST:
		print("NETTEST HOST DONE")
		_tlog("NETTEST HOST DONE")
		await get_tree().create_timer(1.0).timeout  # 等终局快照投递到客户端
		get_tree().quit()


# ============================== 日志 / 节奏 ==============================
func _set_phase(t: String) -> void:
	if SIM:
		return
	ui.phase_label.text = "阶段：" + t
	ui.refresh_labels()


func set_prompt(t: String) -> void:
	if SIM:
		return
	ui.set_prompt(t)


func glog(t: String) -> void:
	if SIM:
		return
	ui.log_view.append_text(t + "\n")
	print(t)
	_tlog(t)
	if net_role == NET_HOST:
		_log_history.append(t)
		if _log_history.size() > 500:
			_log_history.pop_front()
		net.broadcast_log(t)


func _pause(t: float) -> void:
	if SIM:
		return
	if AUTO:
		t = 0.01
	await get_tree().create_timer(t).timeout


## 测试日志：直写文件（每行开关一次，进程被杀也不丢缓冲）
func _tlog(t: String) -> void:
	if _log_file == "":
		return
	var f: FileAccess
	if FileAccess.file_exists(_log_file):
		f = FileAccess.open(_log_file, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(_log_file, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(t)
	f.close()


func _cards_txt(cards: Array) -> String:
	var parts: Array = []
	for c in cards:
		parts.append(c.txt())
	return " ".join(parts) if not parts.is_empty() else "（空）"


# ============================== UI 代理（带模式守卫） ==============================
func _refresh_all() -> void:
	if SIM:
		return
	ui.refresh_all()
	if net_role == NET_HOST:
		_net_broadcast()


func _refresh_labels() -> void:
	if SIM:
		return
	ui.refresh_labels()


func _refresh_table(clickable: bool) -> void:
	if SIM:
		return
	ui.refresh_table(clickable)


func _refresh_hand() -> void:
	if SIM:
		return
	ui.refresh_hand()


func _anim_deal(p: PPlayer) -> void:
	if SIM or AUTO:
		return
	await ui.anim_deal(p)


func _anim_discard(p: PPlayer, c: PCard) -> void:
	if SIM or AUTO:
		return
	await ui.anim_discard(p, c)


func _anim_effect_pulse(c: PCard) -> void:
	if SIM or AUTO:
		return
	await ui.anim_effect_pulse(c)

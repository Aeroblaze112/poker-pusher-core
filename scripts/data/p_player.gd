class_name PPlayer
extends RefCounted

## 一位玩家的全部状态（数据载体，无逻辑）

var pname := ""
var is_human := false
var hand: Array = []        # Array[PCard] 手牌
var build: Array = []       # 固定牌（永久保留）
var temp_fill: Array = []   # 结算时临时填入构筑组的牌（回合末弃）
var temp_slots := 0         # 「杠」增加的临时牌位
var score := 0              # 累计总分（整型，每回合结算向下取整）
var j_emptied := false      # 被「弃」效果弃空手牌 → 终局 ×1.5
var had_325 := false        # 构筑组是否已出现过 3-2-5（翻盘规则只触发一次）
var strat := "random"       # 决策策略：random / high / high2 / greedy
var peer_id := 0            # 联机：座位对应的 peer_id（0=AI/单机，主机恒为 1）
var dropped := false        # 联机掉线（本局由 AI 接管）
var net_name := ""          # 联机：座位身份（重连凭名字入座，peer_id 掉线会变）


## 构筑组中固定牌之外的永久空位数
func perm_slots() -> int:
	return 4 - build.size()

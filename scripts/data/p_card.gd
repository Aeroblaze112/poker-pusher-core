class_name PCard
extends RefCounted

## 一张牌：1-10 数字牌；11 弃 / 12 摸 / 13 杠 为功能牌；14 小王 / 15 大王

const SUITS := ["♠", "♥", "♣", "♦"]
const SUIT_NAMES := ["黑桃", "红桃", "梅花", "方块"]

var rank: int   # 1-10 数字, 11 弃, 12 摸, 13 杠, 14 小王, 15 大王
var suit: int   # 0♠ 1♥ 2♣ 3♦, 王为 -1
var copy := 0   # 功能牌复本序号（联机编码时区分同名牌）


func _init(r: int, s: int) -> void:
	rank = r
	suit = s


func is_joker() -> bool:
	return suit < 0


func color() -> int:  # 0 黑 1 红
	return suit % 2


func txt() -> String:
	if is_joker():
		return "大王" if rank == 15 else "小王"
	if rank == 11:
		return "弃" + SUITS[suit]
	if rank == 12:
		return "摸" + SUITS[suit]
	if rank == 13:
		return "杠" + SUITS[suit]
	var r := "A" if rank == 1 else str(rank)
	return r + SUITS[suit]


## 牌面贴图文件名（不含目录与扩展名）
func texture_name() -> String:
	if rank <= 10:
		return SUIT_NAMES[suit] + ("A" if rank == 1 else str(rank))
	match rank:
		11:
			return "弃"
		12:
			return "摸"
		13:
			return "杠"
		14:
			return "小王"
		_:
			return "大王"


# ============================== 联机编码 ==============================
## 编为确定性整数 ID（无需注册表，双端可独立编解码）：
## 低 8 位 = rank * 8 + (suit + 1)，高段 = 复本序号 × 256
func to_net() -> int:
	return rank * 8 + (suit + 1) + copy * 256


static func from_net(id: int) -> PCard:
	var base := id % 256
	var c := PCard.new(base / 8, base % 8 - 1)
	c.copy = id / 256
	return c

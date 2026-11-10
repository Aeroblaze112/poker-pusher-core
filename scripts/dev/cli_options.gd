extends RefCounted

## 命令行开关解析。
## 只返回「命令行里真的出现了」的键，默认值仍由主控持有，避免两处各写一份。
## 引擎参数（--path 等）和 `--` 之后的用户参数都要传进来，顺序不影响结果。

const VALUE_KEYS := {
	"--games": "games",
	"--seed": "seed",
	"--players": "players",
	"--net": "net",
	"--ip": "ip",
	"--port": "port",
	"--expect": "expect",
	"--name": "name",
	"--logfile": "logfile",
	"--user": "user",
	"--pwd": "pwd",
}


static func parse(args: Array) -> Dictionary:
	var o := {}
	var i := 0
	while i < args.size():
		var a: String = args[i]
		match a:
			"--sim":
				o.sim = true
				i += 1
				continue
			"--autoplay":
				o.auto = true
				i += 1
				continue
			"--autonet":
				o.autonet = true
				i += 1
				continue
			"--usertest":
				o.usertest = true
				i += 1
				continue
			"--shot":
				o.shot = true
				i += 1
				continue
			"--uitest":
				o.uitest = true
				i += 1
				continue
			"--shotmenu":
				o.shotmenu = true
				i += 1
				continue

		if VALUE_KEYS.has(a) and i + 1 < args.size():
			o[VALUE_KEYS[a]] = args[i + 1]
			i += 2
			continue

		# 按座位指定策略：--s0 greedy … --s5 random
		var seat := _seat_index(a)
		if seat >= 0 and i + 1 < args.size():
			if not o.has("strats"):
				o.strats = {}
			o.strats[seat] = args[i + 1]
			i += 2
			continue

		i += 1
	return o


## "--s3" → 3，其它 → -1
static func _seat_index(a: String) -> int:
	if not a.begins_with("--s"):
		return -1
	var tail := a.substr(3)
	return int(tail) if tail.is_valid_int() else -1

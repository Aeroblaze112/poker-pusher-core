class_name UserDB
extends RefCounted

## 本地用户系统：注册 / 登录 / 战绩统计
## 存储：user://users.json（名字 → 盐、密码哈希、战绩），会话 user://session.cfg
## 密码不明文落盘：随机盐 + SHA-256。会话只记名字，本机免密自动登录。

const DEFAULT_DB := "user://users.json"
const DEFAULT_SESSION := "user://session.cfg"

var db_path := DEFAULT_DB
var session_path := DEFAULT_SESSION
var users := {}  # name -> {salt, hash, games, wins, best, last}


func _init(db := DEFAULT_DB, session := DEFAULT_SESSION) -> void:
	db_path = db
	session_path = session
	load_db()


func load_db() -> void:
	users = {}
	var f := FileAccess.open(db_path, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			users = d


func _save() -> void:
	var f := FileAccess.open(db_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(users, "\t"))


## 名字合法性：2-12 字符，不含分隔/引号类字符（兼作联机座位身份，须干净）
static func valid_name(n: String) -> String:
	if n.length() < 2 or n.length() > 12:
		return "名字需 2-12 个字符"
	for ch in n:
		if ch in " /\\:;\"'":
			return "名字不能含空格或 / \\ : ; \" '"
	return ""


## 注册。返回 "" 表示成功，否则为错误原因
func register(pname: String, pwd: String) -> String:
	pname = pname.strip_edges()
	var err := valid_name(pname)
	if err != "":
		return err
	if pwd.length() < 4:
		return "密码至少 4 位"
	load_db()  # 多实例共享同一存档：先读最新再改，避免覆盖其他进程的写入
	if users.has(pname):
		return "该名字已被注册"
	var salt := "%08x%08x" % [randi(), randi()]
	users[pname] = {
		"salt": salt, "hash": _hash(salt, pwd),
		"games": 0, "wins": 0, "best": 0, "last": 0,
	}
	_save()
	return ""


## 登录。返回 "" 表示成功，否则为错误原因
func login(pname: String, pwd: String) -> String:
	pname = pname.strip_edges()
	if not users.has(pname):
		return "用户不存在"
	var u: Dictionary = users[pname]
	if str(u.hash) != _hash(str(u.salt), pwd):
		return "密码错误"
	return ""


static func _hash(salt: String, pwd: String) -> String:
	return (salt + "|" + pwd).sha256_text()


## 记一局：累计场次/胜场，维护最佳与最近得分
func record_game(pname: String, score: int, won: bool) -> void:
	load_db()  # 先合并磁盘最新数据，再改再存
	if not users.has(pname):
		return
	var u: Dictionary = users[pname]
	u.games = int(u.games) + 1
	u.wins = int(u.wins) + int(won)
	u.best = maxi(int(u.best), score)
	u.last = score
	_save()


func stats_of(pname: String) -> Dictionary:
	return users.get(pname, {})


# ============================== 会话（自动登录） ==============================
func save_session(pname: String) -> void:
	var f := FileAccess.open(session_path, FileAccess.WRITE)
	if f:
		f.store_string(pname)


func load_session() -> String:
	var f := FileAccess.open(session_path, FileAccess.READ)
	if f:
		return f.get_as_text().strip_edges()
	return ""


func clear_session() -> void:
	if FileAccess.file_exists(session_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(session_path))

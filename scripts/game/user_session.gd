extends RefCounted

## 账号会话：登录、注册、登出、战绩入账。
## 只碰 UserDB 和用户名，不碰 UI——界面刷新由主控转手。

var db: UserDB
var name := ""     # 已登录用户名（空 = 游客）


func _init() -> void:
	db = UserDB.new()


## 口令登录。返回空串表示成功，否则是给用户看的错误文案。
func login(pname: String, pwd: String) -> String:
	var err := db.login(pname, pwd)
	if err == "":
		_remember(pname.strip_edges())
	return err


func register(pname: String, pwd: String) -> String:
	var err := db.register(pname, pwd)
	if err == "":
		_remember(pname.strip_edges())   # 注册成功即登录
	return err


## 命令行免密登录：账号不存在就顺手注册一个。
func login_cli(pname: String, pwd: String) -> String:
	var err := db.login(pname, pwd)
	if err == "用户不存在":
		err = db.register(pname, pwd)
		if err == "":
			err = db.login(pname, pwd)
	if err == "":
		_remember(pname)
	return err


## 上次登录过的账号，本机免密自动登录。返回用户名（没有则空串）。
func resume() -> String:
	var last := db.load_session()
	if last != "":
		_remember(last)
	return last


func logout() -> void:
	name = ""
	db.clear_session()


func stats() -> Dictionary:
	return db.stats_of(name) if name != "" else {}


## 战绩入账。游客不计。
func record(score: int, won: bool) -> void:
	if name == "":
		return
	db.record_game(name, score, won)


func _remember(pname: String) -> void:
	name = pname
	db.save_session(pname)

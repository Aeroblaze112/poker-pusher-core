extends RefCounted

## --usertest 的用例：用独立测试库（跑完即删），不碰真实存档。
## 只测 UserDB 本身，不依赖界面和牌局。

const UserDB := preload("res://scripts/data/user_db.gd")

const DB_PATH := "user://test_users.json"
const SESSION_PATH := "user://test_session.cfg"


static func run() -> void:
	for p in [DB_PATH, SESSION_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	var fails: Array = []
	var ck := func(cond: bool, tag: String) -> void:
		if not cond:
			fails.append(tag)

	var db := UserDB.new(DB_PATH, SESSION_PATH)
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
	ck.call(int(st.get("games", 0)) == 2 and int(st.get("wins", 0)) == 1
			and int(st.get("best", 0)) == 130 and int(st.get("last", 0)) == 130, "stats")
	# 落盘持久化：换实例重读
	var db2 := UserDB.new(DB_PATH, SESSION_PATH)
	ck.call(db2.login("测试甲", "1234") == "", "reload login")
	ck.call(int(db2.stats_of("测试甲").get("games", 0)) == 2, "reload stats")
	# 密码不明文落盘
	var raw := FileAccess.open(DB_PATH, FileAccess.READ).get_as_text()
	ck.call(raw.find("1234") < 0, "no plaintext pwd")
	# 会话：保存 / 读取 / 清除
	db2.save_session("测试甲")
	ck.call(db2.load_session() == "测试甲", "session save/load")
	db2.clear_session()
	ck.call(db2.load_session() == "", "session clear")

	for p in [DB_PATH, SESSION_PATH]:  # 清理测试库
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	if fails.is_empty():
		print("USERTEST PASS")
	else:
		print("USERTEST FAIL: ", fails)

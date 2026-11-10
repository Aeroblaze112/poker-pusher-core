extends PanelContainer

## 开局菜单：人数 / 难度 / 账户 / 联机入口 / 联机大厅。
## 结构在 start_menu.tscn 里；本脚本只负责把按钮接到信号上，以及刷新状态文字。

signal difficulty_chosen(key: String)
signal login_requested(pname: String, pwd: String)
signal register_requested(pname: String, pwd: String)
signal logout_requested
signal host_requested(port: int, pname: String)
signal join_requested(ip: String, port: int, pname: String)
signal start_net_requested
signal rules_requested
signal stats_requested
signal settings_requested

const DIFFICULTY_KEYS := ["easy", "normal", "hard"]

var selected_count := 4

@onready var _menu_card: PanelContainer = $Center/MenuCard
@onready var _account_form: HBoxContainer = $Center/MenuCard/Margin/VBox/AccountForm
@onready var _account_info: HBoxContainer = $Center/MenuCard/Margin/VBox/AccountInfo
@onready var _account_label: Label = $Center/MenuCard/Margin/VBox/AccountInfo/AccountLabel
@onready var _account_status: Label = $Center/MenuCard/Margin/VBox/AccountStatus
@onready var _user_edit: LineEdit = $Center/MenuCard/Margin/VBox/AccountForm/UserEdit
@onready var _pwd_edit: LineEdit = $Center/MenuCard/Margin/VBox/AccountForm/PwdEdit
@onready var _count_row: HBoxContainer = $Center/MenuCard/Margin/VBox/CountRow
@onready var _name_edit: LineEdit = $Center/MenuCard/Margin/VBox/NameRow/NameEdit
@onready var _ip_edit: LineEdit = $Center/MenuCard/Margin/VBox/AddrRow/IpEdit
@onready var _port_edit: LineEdit = $Center/MenuCard/Margin/VBox/AddrRow/PortEdit
@onready var _lobby_card: PanelContainer = $Center/LobbyCard
@onready var _lobby_list: Label = $Center/LobbyCard/Margin/VBox/PlayerList
@onready var _lobby_status: Label = $Center/LobbyCard/Margin/VBox/LobbyStatus
@onready var _start_net_btn: Button = $Center/LobbyCard/Margin/VBox/StartNetBtn


func _ready() -> void:
	const DIFFICULTY_BUTTONS := ["EasyBtn", "NormalBtn", "HardBtn"]
	var vbox := $Center/MenuCard/Margin/VBox
	for i in DIFFICULTY_KEYS.size():
		var btn: Button = vbox.get_node(DIFFICULTY_BUTTONS[i])
		var key: String = DIFFICULTY_KEYS[i]
		btn.pressed.connect(func() -> void: difficulty_chosen.emit(key))

	for btn in _count_row.get_children():
		btn.pressed.connect(_on_count_pressed.bind(btn))

	$Center/MenuCard/Margin/VBox/AccountForm/LoginBtn.pressed.connect(_on_login_pressed)
	$Center/MenuCard/Margin/VBox/AccountForm/RegisterBtn.pressed.connect(_on_register_pressed)
	$Center/MenuCard/Margin/VBox/AccountInfo/LogoutBtn.pressed.connect(func() -> void: logout_requested.emit())
	$Center/MenuCard/Margin/VBox/RulesRow/RulesBtn.pressed.connect(func() -> void: rules_requested.emit())
	$Center/MenuCard/Margin/VBox/RulesRow/StatsBtn.pressed.connect(func() -> void: stats_requested.emit())
	$Center/MenuCard/Margin/VBox/RulesRow/SettingsBtn.pressed.connect(func() -> void: settings_requested.emit())
	$Center/MenuCard/Margin/VBox/ButtonRow/HostBtn.pressed.connect(_on_host_pressed)
	$Center/MenuCard/Margin/VBox/ButtonRow/JoinBtn.pressed.connect(_on_join_pressed)
	_start_net_btn.pressed.connect(func() -> void: start_net_requested.emit())


func _on_count_pressed(btn: Button) -> void:
	selected_count = int(btn.name.trim_prefix("Count"))


func _on_login_pressed() -> void:
	login_requested.emit(_user_edit.text.strip_edges(), _pwd_edit.text)


func _on_register_pressed() -> void:
	register_requested.emit(_user_edit.text.strip_edges(), _pwd_edit.text)


func _on_host_pressed() -> void:
	host_requested.emit(int(_port_edit.text), _name_edit.text.strip_edges())


func _on_join_pressed() -> void:
	join_requested.emit(_ip_edit.text, int(_port_edit.text), _name_edit.text.strip_edges())


## 登录状态切换：pname 为空 = 回到游客表单；非空 = 显示战绩并把联机名锁定为账号名
func set_account(pname: String, stats: Dictionary) -> void:
	var logged := pname != ""
	_account_form.visible = not logged
	_account_info.visible = logged
	if logged:
		_account_label.text = "👤 %s ｜ %d 场 %d 胜 ｜ 最佳 %d 分" % [
			pname, int(stats.get("games", 0)), int(stats.get("wins", 0)), int(stats.get("best", 0))]
		set_default_name(pname)
		_name_edit.editable = false
	else:
		_name_edit.editable = true
	set_account_status("")


func set_account_status(t: String) -> void:
	_account_status.text = t


func get_default_name() -> String:
	return _name_edit.text.strip_edges()


func set_default_name(pname: String) -> void:
	if pname != "":
		_name_edit.text = pname


func show_lobby(i_am_host: bool) -> void:
	_menu_card.visible = false
	_lobby_card.visible = true
	_start_net_btn.visible = i_am_host
	_lobby_status.text = "" if i_am_host else "已连接，等待主机开始……"


const SEAT_COUNTS := [2, 4, 5, 6]   # 3 人模式已移除：只认这几个座位数


func update_lobby(names: Array, i_am_host: bool) -> void:
	_lobby_list.text = "已连接 %d 人：\n%s" % [names.size(), "\n".join(names)]
	_start_net_btn.visible = i_am_host
	var ok := names.size() in SEAT_COUNTS
	_start_net_btn.disabled = not ok
	_start_net_btn.tooltip_text = "" if ok else "只支持 2 / 4 / 5 / 6 人开局"


func set_lobby_status(t: String) -> void:
	_lobby_status.text = t

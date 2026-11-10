extends Control

## 牌桌主体：顶栏、环形对手区、你的构筑框、底部手牌区。
## 场景只管摆放，刷新逻辑仍在 GameUI 里；这里只把按钮点击转成信号。

signal log_pressed
signal d2_pressed
signal confirm_pressed
signal restart_pressed
signal reconnect_pressed

@onready var round_label: Label = $Root/TopBar/RoundLabel
@onready var phase_label: Label = $Root/TopBar/PhaseLabel
@onready var back_icon: TextureRect = $Root/TopBar/BackIcon
@onready var joker_tex: TextureRect = $Root/TopBar/JokerTex
@onready var joker_label: Label = $Root/TopBar/JokerLabel
@onready var piles_label: Label = $Root/TopBar/PilesLabel
@onready var d2_btn: Button = $Root/TopBar/D2Btn
@onready var table_row: HBoxContainer = $Root/Mid/TableHolder/TableRow
@onready var hand_fan: Control = $Root/Bottom/BottomRow/Bvb/HandFan
@onready var prompt_label: Label = $Root/Bottom/BottomRow/Bvb/PromptRow/PromptLabel
@onready var confirm_btn: Button = $Root/Bottom/BottomRow/Bvb/PromptRow/ConfirmBtn
@onready var restart_btn: Button = $Root/Bottom/BottomRow/Bvb/PromptRow/RestartBtn
@onready var reconnect_btn: Button = $Root/Bottom/BottomRow/Bvb/PromptRow/ReconnectBtn
@onready var opp_ring: Control = $Root/Mid/OppRing
@onready var mid: Control = $Root/Mid
@onready var my_build_box: HBoxContainer = $Root/Mid/MyBuildBox
@onready var bottom_panel: PanelContainer = $Root/Bottom


func _ready() -> void:
	$Root/TopBar/LogBtn.pressed.connect(func() -> void: log_pressed.emit())
	$Root/TopBar/D2Btn.pressed.connect(func() -> void: d2_pressed.emit())
	confirm_btn.pressed.connect(func() -> void: confirm_pressed.emit())
	restart_btn.pressed.connect(func() -> void: restart_pressed.emit())
	reconnect_btn.pressed.connect(func() -> void: reconnect_pressed.emit())

class_name NetSession
extends Node

## 联机传输层：ENet 连接、名字制大厅、断线重连、RPC 管道
## 架构：主机权威——对局逻辑只在主机运行；
## 客户端渲染主机广播的状态快照，通过 RPC 回传选牌结果。
## 重连：座位身份 = 玩家名字（而非 peer_id），掉线后同名重连即可入座续局。
## 状态快照与选牌的编解码在控制器侧，本类只负责连接、大厅与路由。

signal lobby_changed(names: Array, i_am_host: bool)
signal game_started(seat: int, count: int, names: Array)
signal rejoined(seat: int, names: Array)           # 客户端：掉线重连成功
signal rejected(msg: String)                       # 客户端：被主机拒绝
signal hello_received(peer_id: int, name: String)  # 主机：对端报到（控制器决定入座/拒绝）
signal peer_dropped(peer_id: int)
signal state_received(d: Dictionary)
signal hand_received(ids: Array)
signal pick_requested(req_id: int, zone: String, n: int, legal_ids: Array)
signal pick_fulfilled(req_id: int, ids: Array)     # 主机侧：远端选牌结果
signal log_received(t: String)
signal log_backlog_received(lines: Array)
signal connection_failed(reason: String)

const DEFAULT_PORT := 8910
const MAX_CLIENTS := 5   # 主机 + 最多 5 名客户端 = 6 人

var game  # 主控制器
var is_host := false
var my_name := ""
var lobby_peers: Array = []   # 大厅：peer_id 按报到顺序
var lobby_names: Array = []   # 大厅：与 lobby_peers 对齐
var seat_peers: Array = []    # 对局：seat -> peer_id（掉线保留，重连替换）
var seat_names: Array = []    # 对局：seat -> name（座位身份）
var _pending := {}            # req_id -> peer_id（主机侧等待中的选牌请求）
var _req_seq := 0


# ============================== 连接 ==============================
func host_game(port: int, host_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_name = host_name
	lobby_peers = [multiplayer.get_unique_id()]
	lobby_names = [host_name]
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_lobby_sync()
	return OK


func join_game(ip: String, port: int, name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	my_name = name
	multiplayer.connected_to_server.connect(
		func() -> void: rpc_id(1, "_sv_hello", my_name))
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit("无法连接到主机"))
	multiplayer.server_disconnected.connect(func() -> void: connection_failed.emit("与主机断开连接"))
	return OK


func close() -> void:
	multiplayer.multiplayer_peer = null
	lobby_peers.clear()
	lobby_names.clear()
	seat_peers.clear()
	seat_names.clear()
	_pending.clear()


func is_peer_alive(peer: int) -> bool:
	return peer == multiplayer.get_unique_id() or peer in multiplayer.get_peers()


func _on_peer_connected(_id: int) -> void:
	pass  # 等对方 _sv_hello 报到后再登记大厅


func _on_peer_disconnected(id: int) -> void:
	var i := lobby_peers.find(id)
	if i >= 0:
		lobby_peers.remove_at(i)
		lobby_names.remove_at(i)
		_lobby_sync()
	# 该对端若有等待中的选牌请求，以空结果放行（控制器转 AI 代选）
	for req_id in _pending.keys():
		if _pending[req_id] == id:
			_pending.erase(req_id)
			pick_fulfilled.emit(req_id, [])
	peer_dropped.emit(id)


# ============================== 大厅（名字制） ==============================
func _lobby_sync() -> void:
	lobby_changed.emit(lobby_names, true)
	rpc("_cl_lobby", lobby_names)


## 主机：大厅阶段登记新玩家（重名由控制器先行校验）
func register_lobby_peer(peer: int, name: String) -> void:
	lobby_peers.append(peer)
	lobby_names.append(name)
	_lobby_sync()


## 主机：拒绝并踢出（重名 / 对局中无座位）
func reject_client(peer: int, msg: String) -> void:
	rpc_id(peer, "_cl_reject", msg)
	# 稍等拒绝信投递到位再断开，避免对端只收到"连接断开"
	await get_tree().create_timer(0.3).timeout
	if is_peer_alive(peer):
		multiplayer.multiplayer_peer.disconnect_peer(peer)


## 主机：允许掉线玩家重连入座，并续传日志
func accept_rejoin(peer: int, seat: int, backlog: Array) -> void:
	rpc_id(peer, "_cl_rejoin", seat, seat_names)
	rpc_id(peer, "_cl_log_backlog", backlog)


@rpc("any_peer", "call_remote", "reliable")
func _sv_hello(name: String) -> void:
	hello_received.emit(multiplayer.get_remote_sender_id(), name)


@rpc("authority", "call_remote", "reliable")
func _cl_lobby(names: Array) -> void:
	lobby_names = names
	lobby_changed.emit(names, false)


@rpc("authority", "call_remote", "reliable")
func _cl_reject(msg: String) -> void:
	rejected.emit(msg)


# ============================== 开局 / 重开 ==============================
## 主机开局（或重开）：座位名册固定，按 seat_peers 通知各端座位
func start_game(count: int) -> void:
	var seats := {}
	for i in count:
		seats[seat_peers[i]] = i
	rpc("_cl_start", count, seats, seat_names)
	game_started.emit(0, count, seat_names)


@rpc("authority", "call_remote", "reliable")
func _cl_start(count: int, seats: Dictionary, names: Array) -> void:
	seat_names = names
	game_started.emit(int(seats.get(multiplayer.get_unique_id(), 0)), count, names)


@rpc("authority", "call_remote", "reliable")
func _cl_rejoin(seat: int, names: Array) -> void:
	seat_names = names
	rejoined.emit(seat, names)


# ============================== 状态广播（主机 → 客户端） ==============================
func broadcast_state(d: Dictionary) -> void:
	rpc("_cl_state", d)


func send_hand(peer: int, ids: Array) -> void:
	rpc_id(peer, "_cl_hand", ids)


func broadcast_log(t: String) -> void:
	rpc("_cl_log", t)


@rpc("authority", "call_remote", "reliable")
func _cl_state(d: Dictionary) -> void:
	state_received.emit(d)


@rpc("authority", "call_remote", "reliable")
func _cl_hand(ids: Array) -> void:
	hand_received.emit(ids)


@rpc("authority", "call_remote", "reliable")
func _cl_log(t: String) -> void:
	log_received.emit(t)


@rpc("authority", "call_remote", "reliable")
func _cl_log_backlog(lines: Array) -> void:
	log_backlog_received.emit(lines)


# ============================== 选牌路由 ==============================
## 主机侧：向远端玩家发选牌请求，挂起等待其 RPC 回传
func request_remote_pick(peer: int, zone: String, n: int, legal_ids: Array) -> Array:
	_req_seq += 1
	var req_id := _req_seq
	_pending[req_id] = peer
	rpc_id(peer, "_cl_pick_req", req_id, zone, n, legal_ids)
	while true:
		var r: Array = await pick_fulfilled
		if r[0] == req_id:
			_pending.erase(req_id)
			return r[1]
	return []  # 不可达，满足返回类型


## 客户端侧：回传选牌结果
func send_pick(req_id: int, ids: Array) -> void:
	rpc_id(1, "_sv_pick", req_id, ids)


@rpc("authority", "call_remote", "reliable")
func _cl_pick_req(req_id: int, zone: String, n: int, legal_ids: Array) -> void:
	pick_requested.emit(req_id, zone, n, legal_ids)


@rpc("any_peer", "call_remote", "reliable")
func _sv_pick(req_id: int, ids: Array) -> void:
	if _pending.get(req_id) == multiplayer.get_remote_sender_id():
		pick_fulfilled.emit(req_id, ids)

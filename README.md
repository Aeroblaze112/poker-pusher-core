# 我说推扑克特别有说法

Godot 4.7 做的推牌构筑卡牌游戏。2 / 4 / 5 / 6 人，单机对 AI，或局域网联机（主机权威）。四回合内靠构筑组拼分，最终回合得分 ×1.5。

## 跑起来

1. 装 Godot 4.7（纯 GDScript，不需要 .NET 版）
2. 用编辑器打开 `project.godot`，F5
3. 或者命令行：`godot --path .`

Windows 下渲染后端在 `project.godot` 里固定为 D3D12，要换 Vulkan 改 `rendering/renderer/rendering_method` 即可。

## 玩法

每回合按五步走：**发牌 → 固定 → 效果牌 → 结算 → 清理**。

- 构筑组上限 4 张，每回合结算一次，分数累加
- 每回合固定 1 张进构筑组，永久保留、对所有玩家公开
- 效果牌三种：弃（每人弃 1 张手牌）、摸（每人摸 2 张）、杠（全员本回合临时牌位 +1）
- 计分：基准分取「最大单张 / 最大对子和 / 最大三张和 / 最长顺子」四者最大，再乘同花 ×2 或同色 ×1.2、最大牌三张 ×3 或对子 ×2、王同色 ×1.2
- 3-2-5 翻盘：构筑组首次凑出 3、2、5 且本回合得分全场最低 → 本回合得分变全场最高，每人整局只有一次
- 最终回合（第 4 回合结束，或有人手牌被弃空 / 摸牌不够一圈）得分 ×1.5

游戏内首页有「玩法说明」按钮，规则细节都在那一页。

桌面按人数各排各的：2 人对坐，4 人三面，5 人 U 形（对面空着），6 人六边形。每个人的构筑组和总分贴在自己那块框旁边，底下没有大记分板。

## 联机

- 同一局域网，一方点「创建主机」，其他人填主机 IP 加入，默认端口 8910
- 玩家名就是座位凭据，掉线后用同一个名字重连回到原位
- 支持 2 / 4 / 5 / 6 人（3 人模式已移除）

## 代码结构

完整说明见 [ARCHITECTURE.md](ARCHITECTURE.md)，这里是速查：

```
scenes/demo.tscn            唯一启动场景，根节点挂 scripts/demo_game.gd
scenes/ui/                  board（牌桌）/ start_menu（开局菜单）/ rules_page（玩法说明）/ build_strip（构筑框）
scripts/demo_game.gd        编排：开局、主循环、联机协调、UI 代理
scripts/game/deck.gd        按人数造牌（纯静态）
scripts/game/round_flow.gd  回合五阶段
scripts/game/user_session.gd 本地账号会话
scripts/ui/game_ui.gd       UI 门面：持场景实例、刷数据、播动效
scripts/rules/scoring.gd    计分（全静态函数，可单独调用测试）
scripts/ai/card_ai.gd       AI 选牌：random / high / high2 / greedy
scripts/net/net_session.gd  ENet 传输层
scripts/data/               牌、玩家、本地账号库（存 user:// 下的 JSON，不入库）
themes/casino_theme.tres    按钮四态、面板变体、输入框、分隔线
assets/ui/                  牌面、牌位、背景贴图
```

样式统一在 `themes/casino_theme.tres` 里改，代码里不再手写按钮描边；需要变体就加 `theme_type_variation`（`AccentButton`、`Card`、`Scrim` 等）。

难度到策略的映射在 `scripts/demo_game.gd:18-22`：初级 → random，高级 → high，智能择 → high2。

## 命令行开关

调试和批量模拟用，参数放在 `--` 之后：

```bash
# 自动打一局（AI 代替人类，打完停在结算界面）
godot --path . -- --autoplay --players 4 --seed 7

# 批量模拟，统计各策略胜率和均分
godot --path . -- --sim --games 300 --players 4 --seed 7 \
      --s0 greedy --s1 high --s2 random --s3 high2

# 本地账号库自检（跑完自己退出）
godot --path . -- --usertest

# 直接以某个账号登录（不存在会顺手注册）
godot --path . -- --user 名字 --pwd 密码
```

常用参数：`--players`（2/4/5/6）、`--seed`、`--games`、`--s0`…`--s5`（按座位指定策略）、`--logfile`、`--net host|join`、`--ip`、`--port`、`--name`、`--expect`、`--shot`、`--shotmenu`。

`--shot` / `--shotmenu` 是调试截屏，需要窗口模式，不能配 `--headless`。

## 打包

```bash
# 需要先装 4.7.2 的导出模板
build.cmd
```

产物是 `build\poker-pusher-<tag>-windows-x86_64.exe`，单文件内嵌 PCK，不依赖资源目录。`GODOT` 环境变量可以指到别的引擎路径。

## 目前版本使用须知

- 联机只在本机的 `127.0.0.1` 上验证过，跨机器（防火墙、局域网）还没实测，不保证一定能用
- 5 / 6 人的桌面布局只做过自动对局和截图检查，没经过真人长时间对局
- 存档和战绩写在 `user://` 下，重装或换机会丢

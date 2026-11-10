# 项目结构

Godot 4.7 的推牌构筑卡牌游戏。UI 走场景 + Theme，逻辑按「牌具 / 回合流程 / 账号」分文件，`demo_game.gd` 只做编排和联机协调。

```
project.godot            主场景 = scenes/demo.tscn，全局 Theme = themes/casino_theme.tres
scenes/
  demo.tscn              唯一启动场景，根节点挂 scripts/demo_game.gd
  ui/
    board.tscn           牌桌：顶栏 / 牌桌区 / 手牌区，只负责摆放
    start_menu.tscn      开局菜单：账号、人数、难度、联机
    rules_page.tscn      玩法说明页
    build_strip.tscn     单人构筑组（4 个黄槽 + N 个临时蓝槽）
scripts/
  demo_game.gd           编排：开局、主循环、联机协调、UI 代理
  game/
    deck.gd              按人数造牌（纯静态，不洗牌）
    round_flow.gd        回合五阶段：发牌 / 固定 / 效果牌 / 结算 / 清理
    user_session.gd      本地账号会话（登录、注册、战绩）
  ui/
    game_ui.gd           UI 门面：持场景实例、刷数据、播动效
    board.gd             牌桌控件引用 + 信号转发
    start_menu.gd        菜单信号与控件状态
    rules_page.gd        规则文案
    build_strip.gd       构筑组渲染 + 亮牌 / 描边 / 弹跳
  net/net_session.gd     ENet 传输层（发消息、收消息、座位名册）
  rules/scoring.gd       计分（全静态，可单独调用）
  ai/card_ai.gd          AI 选牌：random / high / high2 / greedy
  data/                 牌、玩家、账号库
  dev/
    cli_options.gd       命令行参数解析
    user_selftest.gd     账号系统自检（--usertest）
themes/casino_theme.tres 按钮四态、面板变体（Card / Scrim / ScrimDark / Bare）、输入框、分隔线
assets/ui/               牌面、牌位、背景贴图
```

## 几条约定

- **样式只在 Theme 里改**。代码里不再手写 `StyleBoxFlat` 描边按钮；需要变体就加 `theme_type_variation`（`AccentButton`、`Card`、`Scrim` 等）。
- **场景负责摆放，脚本负责数据**。位置、锚点、字号在 `.tscn` 里；`refresh()` 只填内容。
- **每个模式单独摆座位**。`game_ui.gd` 的 `_seats_for_two/four/five/six` 各自手写坐标，不共用公式。
- **动效不拖节奏**。发牌错峰并行；`--autoplay` / `--sim` 下动画整组跳过。
- **`--autoplay` 不会自动退出**，跑完停在结算界面；`--usertest` 会自己退。

## 不放进仓库的东西

`dspr/`（临时脚本、截图、日志、模板与 APPDATA 重定向）和 `build/`（导出产物）都在 `.gitignore` 里。本地 `HANDOFF.md` 走 `.git/info/exclude`。

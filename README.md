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

## 联机

- 同一局域网，一方点「创建主机」，其他人填主机 IP 加入，默认端口 8910
- 玩家名就是座位凭据，掉线后用同一个名字重连回到原位
- 2–6 人

## 代码结构

```
scripts/
  demo_game.gd        主控：回合流程、发牌、效果牌、结算、联机同步
  ui/game_ui.gd       纯代码搭 UI：牌桌、手牌、对手构筑框、菜单、玩法说明页
  rules/scoring.gd    计分（全静态函数，可单独调用测试）
  ai/card_ai.gd       AI 选牌：random / high / high2 / greedy 四套策略
  net/net_session.gd  ENet 传输层
  data/               牌、玩家、本地账号库（存 user:// 下的 JSON，不入库）
scenes/demo.tscn      唯一场景，根节点挂 demo_game.gd
assets/ui/            牌面、牌位、背景贴图
```

难度到策略的映射在 `scripts/demo_game.gd:13-15`：初级 → random，高级 → high，智能择 → high2。

## 命令行开关

调试和批量模拟用，参数放在 `--` 之后：

```bash
# 自动打一局（AI 代替人类，打完停在结算界面）
godot --path . -- --autoplay --players 4 --seed 7

# 批量模拟，统计各策略胜率和均分
godot --path . -- --sim --games 300 --players 4 --seed 7 \
      --s0 greedy --s1 high --s2 random --s3 high2

# 本地账号库自检
godot --path . -- --usertest

# 直接以某个账号登录（不存在会顺手注册）
godot --path . -- --user 名字 --pwd 密码
```

常用参数：`--players`（2/4/5/6，3 人只在联机可达）、`--seed`、`--games`、`--s0`…`--s5`（按座位指定策略）、`--logfile`、`--net host|join`、`--ip`、`--port`、`--name`、`--expect`、`--shot`、`--shotmenu`。

`--shot` / `--shotmenu` 是调试截屏，需要窗口模式，不能配 `--headless`。

## 工作约定

- 临时产物（截图、日志、一次性脚本、下载物）一律放 `dspr/`，已在 `.gitignore` 里
- `.godot/` 是编辑器缓存，不入库

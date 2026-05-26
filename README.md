# PokerTerminalPS v0.4

PowerShell 终端版德州扑克本地演示。

当前版本：v0.4「本地策略机器人可验收」。本版本聚焦本地真人 + 策略机器人 Demo、核心规则验收、机器人风格区分、可选决策日志和稳定性验证；不包含局域网联机、Host/Client、GUI 或网页。

## 运行

首次在当前 PowerShell 进程中运行脚本时，可以先放开本进程执行策略：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

运行快速自动化测试，适合日常小改后验证：

```powershell
.\tests\Run-Tests.ps1
```

运行全部自动化测试，适合阶段验收：

```powershell
.\tests\Run-Tests.ps1 -Full
```

只运行压力测试：

```powershell
.\tests\Run-Tests.ps1 -Stress
```

按测试文件名筛选，例如只跑界面渲染测试：

```powershell
.\tests\Run-Tests.ps1 -Name Render
```

单机 1 个真人 + 5 个机器人：

```powershell
.\Start-Poker.ps1 -Mode Local -Bots 5
```

自动跑 50 手牌，用于本地压力测试和稳定性验证：

```powershell
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50
```

`-AutoPlay` 会把真人座位也交给机器人自动行动，适合快速验证流程是否崩溃、是否能连续进入下一手牌。`-Hands` 当前支持 1 到 1000 手牌。

## v0.3 已完成

- all-in 规则验证。
- 主池 / 边池构建与派奖验证。
- 弃牌玩家已投入筹码进入奖池，但不能参与领奖。
- 平分奖池和零头固定分配验证。
- 单挑 PreFlop / Postflop 行动顺序验证。
- 最小加注规则验证。
- 短筹码 call 自动 all-in 验证。
- all-in 不足完整加注时不会错误重开行动权。
- A2345 顺子、两对踢脚等关键牌型比较验证。
- 50 手牌 AutoPlay 稳定性验证。

## 当前功能

- 终端文字界面。
- 本地单桌德州扑克流程。
- 1 个本地真人可以和最多 5 个机器人连续玩牌。
- 机器人只会从合法动作中选择，并通过统一下注入口执行。
- 支持摊牌、全下、主池、边池和多人派奖。
- 回合结束公布所有玩家手牌和最终最大牌型。
- 下注前显示你的当前最大牌型。
- 下注前显示你最可能形成的前三种最终牌型概率。
- 人类玩家可用编号选择动作。
- 支持 RandomBot、TightBot、LooseBot、RuleBot 四类机器人。
- 支持可选 `-Debug` Bot 决策日志。
- 测试入口已拆分为快测、全量验收、压力测试和按名称筛选。

## 常用命令

游戏中会把当前可用动作显示为编号，例如：

```text
命令: 1.弃牌  2.跟注  3.加注40-1000  4.全下
```

直接输入编号即可执行对应动作。下注或加注编号如果不带金额，会使用最小合法金额；也可以输入 `3 160` 这类形式指定金额。

仍保留中文和英文命令别名：

```text
弃牌 / fold
过牌 / check
跟注 / call
下注 80 / bet 80
加注 160 / raise 160
全下 / allin
状态 / status
帮助 / help
退出 / quit
```

## 当前不包含

- 局域网联机。
- Host / Client 模式。
- GUI。
- 网页版本。
- 玩家历史建模和自适应对手策略。
- 持久化存档或完整回放系统。

## 测试

```powershell
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Full
.\tests\Run-Tests.ps1 -Stress
.\tests\Run-Tests.ps1 -Name Render
```

默认不再跑耗时较长的 Bot 千次决策、50 手牌稳定性、200 手牌调参统计；这些重测试保留在 `-Full` 和 `-Stress` 中。测试脚本会输出 `[PASS]` / `[FAIL]`，失败时返回非零退出码。

## v0.4 已完成

v0.4 聚焦本地机器人体验，不包含局域网联机、GUI、网页、玩家历史建模或回放系统。

- 新增 TightBot、LooseBot、RuleBot 三类策略机器人。
- 机器人决策继续只使用合法动作，并统一通过 `Apply-PlayerAction` 执行。
- RuleBot 综合考虑翻牌前牌力、摊牌牌力、听牌、位置、底池赔率和多人底池压力。
- 可选 `-Debug` 会输出 Bot 决策 JSONL 日志，默认关闭，不影响普通运行。
- 新增 200 手牌 Bot 策略统计验收，覆盖 VPIP、弃牌率、跟注率、下注/加注率、全下率。
- 当前调参目标：TightBot VPIP 15%-25%，LooseBot VPIP 35%-55%，RuleBot VPIP 25%-40%，LooseBot 下注/加注率高于 TightBot，弱牌全下率保持较低。

常用 v0.4 验收命令：

```powershell
.\tests\Run-Tests.ps1 -Full
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 200
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50 -Debug
```

`-Hands` 表示最多运行手数；如果只剩 1 名玩家还有筹码，牌局会提前正常结束。

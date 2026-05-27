# PokerTerminalPS v0.5

PowerShell 终端版德州扑克演示项目。

当前版本：v0.5「局域网 Host / Client 可人工验收」。本版本在 v0.4 本地策略机器人基础上，加入局域网 Host / Client 模式、HTTP 轮询联机通道、客户端私有视图、真人重连、离线暂停和真人出局重开保护。项目仍然是纯终端文字界面，不包含 GUI、网页、公网匹配或账号系统。

## 运行准备

首次在当前 PowerShell 进程中运行脚本时，可以先放开本进程执行策略：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## 本地模式

单机 1 个真人 + 5 个机器人：

```powershell
.\Start-Poker.ps1 -Mode Local -Bots 5
```

自动跑 50 手牌，用于本地流程稳定性验证：

```powershell
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50
```

`-AutoPlay` 会把真人座位也交给机器人自动行动，适合快速验证流程是否崩溃、是否能连续进入下一手牌。`-Hands` 当前支持 1 到 1000 手牌。

## 局域网模式

默认联机传输为 `Http`，Host 开房：

```powershell
.\Start-Poker.ps1 -Mode Host -Port 7777 -Bots 4
```

Client 加入：

```powershell
.\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Alice
.\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Bob
```

同一局域网内，把 `127.0.0.1` 换成 Host 电脑的局域网 IP，例如：

```powershell
.\Start-Poker.ps1 -Mode Client -Host 192.168.1.14 -Port 7777 -Name Alice
```

Host 的 `-Bots` 表示自动补入的机器人数量。当前自动补入的机器人默认都是 `LooseBot`。例如 `-Bots 4` 表示最多 2 个真人 + 4 个机器人。

仍保留实验性的 TCP 传输入口：

```powershell
.\Start-Poker.ps1 -Mode Host -Port 7777 -Transport Tcp
.\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Alice -Transport Tcp
```

当前推荐使用默认 HTTP 模式。

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

## 当前功能

- 终端文字界面。
- 本地单桌德州扑克流程。
- 局域网 Host / Client 联机流程。
- HTTP 轮询联机通道，客户端只显示自己允许看到的信息。
- 1 个本地真人可以和最多 5 个机器人连续玩牌。
- Host 模式支持真人玩家加入、等待、行动、离开和同名重连。
- 多真人联机时，未轮到行动的客户端显示等待提示，不显示可执行命令。
- 有真人离线时牌局暂停，等待离线玩家重新连接。
- 真人都在线但全部出局时，Host 会重置整桌筹码，让真人重新开局，避免机器人自娱自乐。
- 机器人只会从合法动作中选择，并通过统一下注入口执行。
- 当前 Host 自动补位机器人默认使用 `LooseBot`。
- 支持摊牌、全下、主池、边池和多人派奖。
- 回合结束公布所有玩家手牌和最终最大牌型。
- 下注前显示你的当前最大牌型。
- 下注前显示你最可能形成的前三种最终牌型概率。
- 人类玩家可用编号选择动作。
- 支持 RandomBot、TightBot、LooseBot、RuleBot 四类机器人。
- 支持可选 `-Debug` Bot 决策日志。
- 测试入口已拆分为快测、全量验收、压力测试和按名称筛选。

## 测试

快速自动化测试，适合日常小改后验证：

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

按测试文件名筛选，例如只跑 HTTP 联机测试：

```powershell
.\tests\Run-Tests.ps1 -Name HttpNetwork
```

默认快测包含核心规则、渲染、命令解析、网络协议、网络流程和 HTTP Host / Client 测试。耗时较长的 Bot 千次决策、50 手牌稳定性、200 手牌调参统计保留在 `-Full` 和 `-Stress` 中。测试脚本会输出 `[PASS]` / `[FAIL]`，失败时返回非零退出码。

## v0.5 已完成

- Host / Client 启动入口。
- HTTP 轮询 Host / Client 联机流程。
- Client 私有 StateSnapshot 渲染，隐藏其他玩家手牌和未来牌堆。
- Client 中文紧凑表格，与本地终端 UI 尽量对齐。
- Client 编号命令转换和中文错误提示。
- Host 只接受当前行动真人的合法动作。
- Host 拒绝过期手牌、非当前行动玩家和非法动作。
- 真人离开或超时离线时暂停牌局。
- 同名玩家可重新连接原座位，不会把桌子占满。
- 真人全部出局但仍在线时，重置整桌筹码，避免机器人继续单独跑牌。
- 当前 Host 自动补位机器人默认使用 `LooseBot`。

## 当前不包含

- GUI。
- 网页版本。
- 公网匹配、账号和房间大厅。
- 玩家历史建模和自适应对手策略。
- 持久化存档或完整回放系统。
- 联机断线后的复杂托管策略。

## 阶段验收命令

```powershell
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Full
.\Start-Poker.ps1 -Mode Host -Port 7777 -Bots 4
.\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Alice
.\Start-Poker.ps1 -Mode Client -Host 127.0.0.1 -Port 7777 -Name Bob
```

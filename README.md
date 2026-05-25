# PokerTerminalPS v0.2

PowerShell 终端版德州扑克本地演示。

当前版本：v0.2「真人 + 机器人 Demo」。本版本不包含局域网联机、Host 模式、Client 模式、GUI 或网页。

## 运行

单机 1 个真人 + 5 个机器人：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Start-Poker.ps1 -Mode Local -Bots 5
```

自动验证几手牌：

```powershell
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 3
```

## 当前功能

- 终端文字界面
- 本地单桌德州扑克流程
- 1 个本地真人可以和最多 5 个机器人连续玩牌
- 机器人只会选择合法动作
- 支持摊牌、全下、边池基础结算
- 回合结束公布所有玩家手牌和最大牌型
- 下注前显示你的当前最大牌型
- 下注前显示你最可能形成的前三种最终牌型概率

## 常用命令

游戏中会把当前可用动作显示为编号，例如：

```text
可用命令: 1. 弃牌, 2. 跟注, 3. 加注 40-1000, 4. 全下
```

直接输入编号即可执行对应动作。下注或加注编号如果不带金额，会使用最小合法金额；也可以输入 `3 160` 这类形式指定金额。

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

## 测试

```powershell
.\tests\Run-Tests.ps1
```

测试脚本会输出 `[PASS]` / `[FAIL]`，失败时返回非零退出码。

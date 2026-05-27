# Development Log

## 2026-05-27 - v0.5 Final Close-out

### Summary

v0.5 is documented as complete for LAN Host / Client manual acceptance. The milestone adds HTTP polling Host / Client play, private Client state rendering, multi-human waiting synchronization, reconnect handling, pause behavior for offline real players, and table reset when connected real players are eliminated so Bots do not continue playing alone.

### Modified Files

- `README.md`
  - Updated the visible project version to v0.5.
  - Added Host / Client HTTP run commands.
  - Documented LAN manual testing commands for Host, Alice, and Bob.
  - Documented that Host auto-fill Bots currently default to `LooseBot`.
  - Documented remote numbered commands, private Client views, reconnect behavior, pause behavior, and real-player-eliminated table reset.
  - Removed stale v0.4 wording that said LAN Host / Client was not included.
- `DEVELOPMENT_PLAN.md`
  - Marked v0.5 as complete for LAN Host / Client manual acceptance.
  - Moved LAN Host / Client from next milestone into implemented scope.
  - Added v0.6 as LAN polish / reliability.
- `DEVELOPMENT_LOG.md`
  - Added this v0.5 close-out entry.

### Added / Updated Tests

- `tests/Test-HttpNetwork.ps1`
  - Covers HTTP join/reconnect without filling the table.
  - Covers automatic Host Bots using `LooseBot`.
  - Covers private StateSnapshot behavior for each Client.
  - Covers non-acting players seeing wait state without legal commands.
  - Covers legal remote action queuing and clearing.
  - Covers current decision timeout not falsely pausing the game.
  - Covers non-acting player timeout and explicit leave pause behavior.
  - Covers same-name reconnect resume behavior.
  - Covers insufficient connected real players between hands.
  - Covers connected real players being eliminated and the table resetting instead of Bots playing alone.
- Existing network tests also cover protocol validation, Client display formatting, Chinese remote action errors, stale hand rejection, and remote action routing through the normal betting rules.

### Verification Notes

Fresh verification for this close-out:

```powershell
.\tests\Run-Tests.ps1 -Name HttpNetwork
.\tests\Run-Tests.ps1
```

Result:

- HTTP network tests pass.
- Quick test suite passes.

### Known Issues

- HTTP Host / Client is suitable for local manual acceptance, not yet a polished lobby system.
- TCP transport remains experimental; the default and recommended transport is HTTP.
- No GUI, web UI, public matchmaking, account system, persistent save, or full replay system.
- Bot strategy is rule/profile driven and does not adapt to individual player history.
- Debug logs are decision logs only, not full replay files.

### Next Plan

Move to v0.6 only for LAN polish and reliability work: clearer Host status output, better manual test notes, and optional restart/ready flow if automatic table reset feels too abrupt in manual play.

## 2026-05-26 - v0.4 Final Close-out

### Summary

v0.4 is now documented as complete for local strategy Bot play. The milestone includes local human-vs-bot play, differentiated Bot styles, RuleBot integrated strategy, optional Bot decision debug logs, compact Chinese terminal output, and split test runner modes for day-to-day development versus full acceptance.

### Modified Files

- `README.md`
  - Updated the current version description to v0.4「本地策略机器人可验收」.
  - Documented RandomBot, TightBot, LooseBot, and RuleBot as current local Bot types.
  - Documented quick, full, stress, and name-filtered test commands.
  - Clarified that v0.4 still excludes LAN Host / Client, GUI, web UI, player-history modeling, adaptive opponent strategy, and full replay.
- `DEVELOPMENT_PLAN.md`
  - Marked v0.4 as complete and local Bot strategy acceptable.
  - Removed v0.4 close-out from next milestones.
  - Kept v0.5 as the first LAN Host / Client milestone.
- `DEVELOPMENT_LOG.md`
  - Added this final v0.4 close-out entry.

### Verification Notes

Recent v0.4 verification before this close-out:

```powershell
.\tests\Run-Tests.ps1
.\tests\Run-Tests.ps1 -Name Render
.\tests\Run-Tests.ps1 -Stress -Name Stability
.\tests\Run-Tests.ps1 -Full -Name TestRunner
```

Result:

- Quick tests pass.
- Render-only filtered tests pass.
- Stability stress filtered tests pass.
- Test runner manifest tests pass.

Full acceptance remains available through:

```powershell
.\tests\Run-Tests.ps1 -Full
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 200
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50 -Debug
```

### Known Issues

- Bot strategy is rule/profile driven and does not adapt to individual player history.
- Debug logs are decision logs only, not full replay files.
- No LAN Host / Client, GUI, or web UI is included in v0.4.

### Next Plan

Enter v0.5 only when ready to start LAN Host / Client work. Keep networking isolated from the existing core rule, pot, showdown, Bot, and terminal UI modules.

## 2026-05-25 - v0.4 Bot Strategy Statistics and Tuning

### Summary

v0.4 adds local strategy Bot validation without changing the core poker rule contract. This step finishes the v0.4-6 acceptance loop: collect Bot style metrics over 200 hands, tune preflop entry behavior, and verify that TightBot, LooseBot, and RuleBot have visibly different local play styles.

### Modified Files

- `src/Bot/BotDecision.ps1`
  - Added a profile-driven preflop entry threshold based on `vpip`, so tight profiles fold more weak hands before the flop.
- `src/Bot/BotProfiles.ps1`
  - Cached profile-file loading by path and last-write time to keep repeated Bot decisions fast.
- `tests/Run-Tests.ps1`
  - Added the Bot tuning acceptance test.
- `tests/Test-BotTuning.ps1`
  - Added a 200-hand local Bot simulation with in-memory action statistics.
  - Tracks VPIP, fold rate, call rate, bet/raise rate, and all-in rate for TightBot, LooseBot, and RuleBot.
- `README.md`
  - Updated the visible project version to v0.4 and added v0.4 acceptance commands.
- `DEVELOPMENT_PLAN.md`
  - Marked v0.4 as local Bot strategy acceptable and kept LAN Host / Client deferred to v0.5.

### Added Tests

- `tests/Test-BotTuning.ps1`
  - Simulates 200 hands with two TightBot, two LooseBot, and two RuleBot seats.
  - Verifies total chips remain constant, no player has negative chips, and every simulated hand finishes.
  - Verifies TightBot VPIP stays in 15%-25%.
  - Verifies LooseBot VPIP stays in 35%-55%.
  - Verifies RuleBot VPIP stays in 25%-40%.
  - Verifies LooseBot bet/raise rate is higher than TightBot.
  - Verifies all-in rate stays low for all three strategy Bot types.

### Latest Tuning Sample

From the 200-hand tuning test:

- TightBot: VPIP 19.5%, fold 37.4%, call 28.3%, bet/raise 5.1%, all-in 0%.
- LooseBot: VPIP 43.6%, fold 21.3%, call 33.0%, bet/raise 39.7%, all-in 0%.
- RuleBot: VPIP 33.8%, fold 25.4%, call 25.7%, bet/raise 26.7%, all-in 0%.

### Known Issues

- Bot strategy is still rule/profile driven, not adaptive to individual player history.
- Debug logs are decision logs only, not a replay system.
- No LAN Host / Client, GUI, or web UI is included in v0.4.

### Next Plan

Finish v0.4 documentation/manual acceptance if needed, then enter v0.5 only when ready to begin LAN Host / Client work.

## 2026-05-25 - v0.3 Core Rule Acceptance

### Summary

v0.3 focuses on making the local PowerShell Texas Hold'em rule core testable and acceptable. This milestone adds stronger unit coverage and real game-flow integration coverage for all-in, side pots, folded contributions, split pots, minimum raises, heads-up action order, and multi-hand stability.

### Modified Files

- `README.md`
  - Updated the visible version to v0.3.
  - Added v0.3 completed scope and run commands.
  - Documented 50-hand AutoPlay as a local stress test.
  - Clarified that the current version has no LAN, GUI, web UI, or advanced Bot strategy.
- `DEVELOPMENT_PLAN.md`
  - Marked v0.3 as core-acceptable.
  - Added v0.4 target: Bot strategy, logs, and replay.
  - Clarified that v0.5 is the first LAN Host / Client milestone.
- `Start-Poker.ps1`
  - Raised `-Hands` validation from 20 to 1000 so `-AutoPlay -Hands 50` can be used for stability verification.
- `tests/Run-Tests.ps1`
  - Added the v0.3 integration test file to the test runner.
- `tests/Test-IntegrationAllInFlow.ps1`
  - Added real flow integration tests for all-in, side pots, folded contributions, incomplete all-in raises, and heads-up action order.
- `tests/Test-Pot.ps1`
  - Strengthened assertions for pot amounts and eligible players.
- `tests/Test-Betting.ps1`
  - Strengthened assertions for short calls, all-in status, negative chip prevention, minimum raise rejection, and incomplete all-in behavior.
- `tests/Test-Stability.ps1`
  - Strengthened multi-hand stability checks.
- `tests/Test-HandEvaluator.ps1`
  - Strengthened A2345 straight and two-pair kicker comparison checks.

### Added Tests

- `tests/Test-IntegrationAllInFlow.ps1`
  - Three-player real betting flow creates a 300 main pot and 400 side pot.
  - A short stack can win the main pot while another player wins the side pot.
  - Folded player contributions remain in the pot but the folded player cannot win.
  - Short-stack call automatically becomes all-in.
  - Incomplete all-in raise does not incorrectly reopen action or increase minimum raise.
  - Heads-up full hand uses dealer / small blind first preflop and big blind first postflop.

### Verification Results

2026-05-25 v0.3 close-out verification:

```powershell
.\tests\Run-Tests.ps1
.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50
```

Result:

- `.\tests\Run-Tests.ps1`: passed.
- `.\Start-Poker.ps1 -Mode Local -Bots 5 -AutoPlay -Hands 50`: passed, completed 50 hands without crashing.

### Known Issues

- Bot behavior is still intentionally simple and random.
- There is no LAN Host / Client mode in v0.3.
- There is no GUI or web UI.
- There is no structured replay file yet.
- Poker rule coverage is strong for the current milestone, but future log/replay work should add regression fixtures from real hand histories.

### Next Plan

v0.4 should start with structured action logging, because logs will make both Bot strategy debugging and replay easier to verify without touching the core betting and pot logic.

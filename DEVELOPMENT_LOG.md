# Development Log

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

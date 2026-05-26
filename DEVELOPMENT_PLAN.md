# Development Plan

This project follows the Markdown development document in the repository root.

## Current Version

v0.4 is complete and local Bot strategy acceptable.

The local terminal game now has focused rule tests, integration tests, strategy Bot tests, optional Bot decision debug logs, split quick/full/stress test runners, and a 200-hand Bot tuning acceptance test. The current milestone is acceptable for local Bot play and strategy validation, while still intentionally excluding networking, GUI, web UI, player-history modeling, and replay.

## Implemented Scope

- v0.0 project skeleton and startup script.
- v0.1 core modules for deck, hand evaluation, betting, pots, and street flow.
- v0.2 local human plus bot demo with Chinese command aliases.
- RandomBot legality test and multi-hand stability simulation.
- Numbered legal-action menu for local human input.
- Current-hand strength display before human actions.
- Top-three final hand type probability hints.
- End-of-hand reveal with every player's hole cards and final best hand type.
- Invalid human input is handled without exiting the game.
- v0.3 all-in rule verification.
- v0.3 main pot and side pot construction and award verification.
- v0.3 folded contribution handling: folded chips stay in the pot, folded players cannot win.
- v0.3 split pot and odd-chip distribution verification.
- v0.3 heads-up PreFlop and Postflop action order verification.
- v0.3 minimum raise and incomplete all-in raise verification.
- v0.3 50-hand AutoPlay stability verification.
- v0.4 TightBot, LooseBot, and RuleBot strategy profiles.
- v0.4 RuleBot integrated scoring for hand strength, draws, position, pot odds, and opponent count.
- v0.4 optional Debug Bot decision JSONL logs.
- v0.4 200-hand Bot tuning statistics for VPIP, fold, call, bet/raise, and all-in rates.
- v0.4 split test runner modes: quick, full, stress, and name-filtered test runs.

## Next Milestones

### v0.5: LAN Host / Client

- Start LAN networking only in v0.5.
- Add Host / Client flow after the local rule core and logging foundation are stable.
- Keep networking separate from core betting, pot, and showdown rules.

## Deferred Scope

- Player-history adaptive Bot strategy.
- Replay implementation.
- Persistence beyond optional Debug decision logs.
- LAN Host / Client networking before v0.5.
- Disconnect handling and reconnect logic.
- GUI.
- Web UI.

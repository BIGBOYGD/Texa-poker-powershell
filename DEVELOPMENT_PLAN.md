# Development Plan

This project follows the Markdown development document in the repository root.

## Current Version

v0.5 is complete for LAN Host / Client manual acceptance.

The terminal game now has focused rule tests, integration tests, strategy Bot tests, optional Bot decision debug logs, split quick/full/stress test runners, local play, and LAN Host / Client play over the default HTTP polling transport. The current milestone is acceptable for local network manual testing with multiple human clients plus automatic Bot seats.

## Implemented Scope

- v0.0 project skeleton and startup script.
- v0.1 core modules for deck, hand evaluation, betting, pots, and street flow.
- v0.2 local human plus bot demo with Chinese command aliases.
- RandomBot legality test and multi-hand stability simulation.
- Numbered legal-action menu for local and remote human input.
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
- v0.5 Host / Client startup modes.
- v0.5 HTTP polling Host / Client transport.
- v0.5 private StateSnapshot rendering for Client sessions.
- v0.5 remote numbered command conversion and Chinese validation errors.
- v0.5 Host-side validation for current-player-only, current-hand-only, legal remote actions.
- v0.5 multi-human waiting state synchronization.
- v0.5 disconnect, leave, timeout pause, and same-name reconnect handling.
- v0.5 connected-but-eliminated human table reset, preventing Bot-only continuation.
- v0.5 default Host auto-fill bots use LooseBot.

## Next Milestones

### v0.6: LAN Polish / Reliability

- Improve manual Host / Client acceptance scripts and troubleshooting notes.
- Add clearer Host-side status output for connected clients and pause reasons.
- Consider a simple ready/restart prompt for eliminated real players if manual testing shows automatic reset is too abrupt.
- Continue keeping networking separate from core betting, pot, and showdown rules.

## Deferred Scope

- GUI.
- Web UI.
- Public matchmaking, accounts, or lobby system.
- Player-history adaptive Bot strategy.
- Full replay implementation.
- Persistence beyond optional Debug decision logs.
- Advanced reconnect handoff or action timer policy.

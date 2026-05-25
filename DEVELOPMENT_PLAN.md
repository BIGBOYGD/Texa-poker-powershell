# Development Plan

This project follows the Markdown development document in the repository root.

## Current Version

v0.3 is core-acceptable.

The local terminal game now has focused unit tests and integration tests for the core Texas Hold'em rule surface. The current milestone is considered acceptable for local rule verification, while still intentionally excluding networking, GUI, web UI, and advanced bot strategy.

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

## Next Milestones

### v0.4: Bot Strategy, Logs, and Replay

- Improve robot strategy without changing the core rules contract.
- Add structured game logs for hands, actions, pots, and showdown results.
- Add replay support based on recorded hand logs.
- Keep local terminal mode as the primary target.

### v0.5: LAN Host / Client

- Start LAN networking only in v0.5.
- Add Host / Client flow after the local rule core and logging foundation are stable.
- Keep networking separate from core betting, pot, and showdown rules.

## Deferred Scope

- Advanced strategy bots beyond v0.4 planning.
- Persistence beyond logs and replay planning.
- LAN Host / Client networking before v0.5.
- Disconnect handling and reconnect logic.
- GUI.
- Web UI.

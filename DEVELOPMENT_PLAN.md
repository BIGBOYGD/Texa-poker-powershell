# Development Plan

This project follows the Markdown development document in the repository root.

## Implemented Scope

- v0.0 project skeleton and startup script
- v0.1 core modules for deck, hand evaluation, betting, pots, and street flow
- local one-hand loop with legal bot actions and showdown resolution
- v0.2 local human plus bot demo with Chinese command aliases
- RandomBot legality test and 20-hand stability simulation
- PowerShell test runner with focused rule tests
- numbered legal-action menu for local human input
- current-hand strength display before human actions
- top-three final hand type probability hints
- end-of-hand reveal with every player's hole cards and final best hand type
- invalid human input is handled without exiting the game

## Deferred Scope

- advanced strategy bots
- persistence
- LAN Host/Client networking
- disconnect handling and reconnect logic

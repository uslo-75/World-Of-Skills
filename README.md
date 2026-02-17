# World Of Skills (WoS)
Roblox project structured with Rojo.

## Overview
World Of Skills is an action/combat-focused project with an advanced movement system, combat interactions (down/carry/grip), and a dedicated VFX/ambience layer.

## Included Mechanics
- Movement: run/sprint, dash (with cancel), slide, slide push, crouch, vault, climb, wallrun, wall hop.
- Falling and landing: fall tracking, landing animations, fall damage.
- Character states: shared client/server `StateManager` for gameplay states (`Running`, `Sliding`, `Climbing`, `WallRunning`, etc.).
- Downed combat flow: enter `Downed` state, contextual prompts, ragdoll handling.
- Carry/Grip: carry a downed target, execute grip, target locking, and state cleanup.
- Interaction: `PromptManager` controls prompt behavior (lock, toggle, hide/show).
- Inventory and stats: inventory sync, drop service, regen manager.
- VFX and ambience: movement/combat visual handlers, body trails, slide/wallrun/fall effects, dynamic ambience (rain/snow).
- Networking: centralized remotes, payload validation, allowlists, rate limiting.

## Getting Started
To build the place from scratch, use:

```bash
rojo build -o "WoS.rbxlx"
```

Next, open `WoS.rbxlx` in Roblox Studio and start the Rojo server:

```bash
rojo serve
```

For more help, check out [the Rojo documentation](https://rojo.space/docs).

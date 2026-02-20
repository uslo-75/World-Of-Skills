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

## Combat Specials (CriticalService)
`CriticalService` now uses a modular structure under:

- `src/ServerScriptService/Server/Handler/Combat/WeaponSpecials/CriticalService/init.lua`
- `src/ServerScriptService/Server/Handler/Combat/WeaponSpecials/CriticalService/CriticalActionRegistry.lua`
- `src/ServerScriptService/Server/Handler/Combat/WeaponSpecials/CriticalService/CriticalMotion.lua`
- `src/ServerScriptService/Server/Handler/Combat/WeaponSpecials/CriticalService/CriticalPrewarm.lua`

### Supported action names
- `Critical`
- `Aerial`
- `Running`
- `Strikefall`
- `RendStep`
- `AnchoringStrike`

### Runtime flow
- Requests are validated through `CriticalRequestValidator` (delegates to shared M1 validation).
- Action names and cooldown attributes are centralized in `CriticalActionRegistry`.
- Handlers are resolved from `Skills/<Action>` first, then weapon-specific modules, then default weapon folder fallback.
- Motion impulses are handled by `CriticalMotion` (managed `LinearVelocity` lifecycle).
- Animation tracks are prewarmed by `CriticalPrewarm` when tools are equipped to reduce first-use hitching.

### Skill key payloads
- Skill requests accept `skillKey` (or `key` / `k`) mapped to weapon stat slots: `Z`, `X`, `C`, `V`.
- The selected slot value resolves to the canonical action handler above.

### Handler contract
- Each action module exposes `Execute(service, context)`.
- `Execute` should return `true` on success or `false, "Reason"` on failure.
- `service:StartAttack(...)` / `service:FinishAttack(...)` should be used to keep attack state and cooldown cleanup consistent.

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

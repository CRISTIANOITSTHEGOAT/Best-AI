# 🛸 Orbit Grab

**Pick up any part in your Roblox place and have it float around you — then fling it, stack it, spin it, or send it home.**

Click a brick and it un-sticks from the world, glides into orbit around your character and stays there while you walk around. Grab ten more and they arrange themselves into a ring, a sphere, a galaxy, an atom, a conga line that retraces your footsteps… Hold right mouse and they launch like a trebuchet.

Built for Studio: drop it in, press Play, done.

---

## Install

### A. Fastest (no Rojo)

1. **StarterPlayer ▸ StarterPlayerScripts** → Insert Object ▸ **LocalScript**, name it `OrbitGrab`, paste in [`dist/OrbitGrab_AllInOne.client.lua`](dist/OrbitGrab_AllInOne.client.lua).
2. *(multiplayer only)* **ServerScriptService** → Insert Object ▸ **Script**, paste in [`dist/OrbitGrabServer.server.lua`](dist/OrbitGrabServer.server.lua).
3. Press **Play**.

### B. Rojo

```bash
rojo serve default.project.json     # syncs src/ into your place
```

```
ReplicatedStorage/OrbitGrab/        (ModuleScript)  Config · Orbit · FX · UI · Carrier
StarterPlayerScripts/OrbitGrabClient (LocalScript)   input, chat commands, render loop
ServerScriptService/OrbitGrabServer  (Script)        network ownership + cleanup
```

Editing `src/ReplicatedStorage/OrbitGrab/Config.lua` hot-reloads into a live Rojo session — that's the intended way to tune it.

---

## Controls

| Input | Action |
| --- | --- |
| **Left Mouse / E / Q** | Grab the part you're looking at (whole Model if it has a PrimaryPart) |
| **Hold Right Mouse / R** | Charge a throw — release to launch |
| **T** | Burst: throw everything forward in a spread |
| **V** | Explode: throw everything radially outward |
| **Z** | Drop everything gently where it floats |
| **Backspace** | Undo: every part teleports back to exactly where you found it |
| **X** | Park: freeze the selected part in mid-air (stays anchored) |
| **Hold G** | Vacuum: inhale every loose part within 25 studs |
| **C** | Next formation (⇧C = previous) |
| **F** | Pause orbital motion (parts still follow you) |
| **M** | Glow — attach a light to everything you're carrying |
| **Mouse Wheel** | Orbit radius |
| **⇧ + Wheel** | Orbit height |
| **⌃ + Wheel** | Orbit speed |
| **`[` `]`** | Radius · **`−` `=`** Height · **`;` `'`** Speed · **`,` `.`** Spin · **`O` `P`** Tilt |
| **Hold Alt** | Slow motion orbits (bullet time) |
| **H** / **J** | Hide the HUD / hide the control hints |
| **`\`** (backtick) | Reset all tuning to defaults |

Touch devices get on-screen **GRAB / THROW / MODE / DROP** buttons automatically.

> Right-click is bound at high priority so Roblox's context menu stays out of the way. If it still pops up on your setup, use **R** to charge a throw instead.

### Chat commands

| Command | Command |
| --- | --- |
| `/orb help` | list everything |
| `/orb mode sphere` | jump to a formation (`next`, `prev`, or a name) |
| `/orb radius 12` | set orbit radius (`height`, `speed`, `spin`, `tilt`, `reach` too) |
| `/orb throw 250` | throw the selected part with a specific power |
| `/orb burst` `/orb explode` `/orb drop` `/orb undo` `/orb park` | the actions |
| `/orb max 120` | raise the carry cap |
| `/orb pause` `/orb glow` `/orb reset` `/orb toggle` `/orb ui` `/orb hints` `/orb count` | state |

Also works with `!orb` and `;orb`.

---

## Formations

| | | |
| --- | --- | --- |
| **Ring** – flat circle | **Helix** – stacked rings, slower as they go up | **Sphere** – even Fibonacci shell |
| **Vortex** – rising spiral column | **Figure8** – Lissajous ribbon | **Tower** – a stack above your head |
| **Galaxy** – spiral disk, outer parts orbit slower | **Wave** – a snake line in front of you | **Crown** – tilted halo |
| **Atom** – three crossing rings | **Follow** – conga line that retraces your footsteps | **Freeze** – locked in place relative to you |

Parts **glide** between formations instead of teleporting, so switching mid-orbit looks like a dance.

---

## Why it feels good (and doesn't fight the physics engine)

* **Kinematic carrying.** While a part is yours it's `Anchored` and driven purely by `CFrame` on the client. No `BodyPosition` jitter, no flinging, no fighting the server, no parts shoving you around (`CanCollide = false`), no re-grabbing your own cargo (`CanQuery = false`).
* **Exponential smoothing.** Every part chases its slot with `1 - e^(-k·dt)` — frame-rate independent, and it means grabbing, formation changes and removals all morph smoothly instead of snapping.
* **Perfect restoration.** The original `CFrame`, `Anchored`, `CanCollide` and `CanQuery` of every part are stored on grab and put back on release. Grab a load-bearing wall, orbit it, drop it — it behaves exactly as it did before, **Backspace** puts it back brick-perfect.
* **Whole models.** Click one brick of a Model with a `PrimaryPart` and the entire thing comes along, rigid, using per-part offsets. Welded assemblies get one impulse on throw; loose bags of parts each get their own so they fly together.
* **Real throws.** `ApplyImpulse` scaled by assembly mass, so a couch and a pebble both feel right, plus tumble spin, a short trail and a particle puff.
* **One render step.** A single `BindToRenderStep` drives everything; cost scales with parts carried (tested at 60), not with parts in the place.
* **Bulletproof UI.** The HUD is generated in code — no `.rbxmx` to import, no plugin, `ResetOnSpawn = false`, and it hides itself on `H`.

---

## Configuration

Everything lives in **`src/ReplicatedStorage/OrbitGrab/Config.lua`** (top of the all-in-one file for the paste-in build). A few favourites:

```lua
Config.General.MaxCarried   = 60     -- carry cap
Config.General.Reach        = 150    -- how far you can grab
Config.General.OnlyInFolder = "Grabbables"  -- restrict to one folder
Config.Orbit.Formation      = "Ring"
Config.Orbit.Radius         = 7
Config.Orbit.FaceMode       = "Spin" -- Spin | Outward | Player | Forward | Velocity | Keep
Config.Throw.MaxPower       = 320
Config.Sounds.Enabled       = true   -- drop in your own asset ids
```

Want a part to be untouchable? Set the attribute `OrbitGrabIgnore = true` on it, or set `Part.Locked`.

---

## Multiplayer

The client asks the server for **network ownership** of what it grabs, so everyone sees your floating junk, not just you. Without `OrbitGrabServer.server.lua` the system still works — you'll just be admiring it alone.

The server validates every request before granting ownership:

| Guard | Default |
| --- | --- |
| Max reach | 250 studs |
| Max parts per player | 120 concurrent |
| Max parts in one grab | 200 |
| Requests per second | 60 per player |
| Locked parts / other players' characters | always refused |
| Player leaves | ownership returned, parts un-anchored so the map isn't left littered |

Tune these in the `SERVER` table at the top of the server script — never from the client.

---

## Files

```
orbit-grab/
├── README.md
├── default.project.json              Rojo project
├── src/
│   ├── ReplicatedStorage/OrbitGrab/
│   │   ├── Config.lua                every tunable number
│   │   ├── Orbit.lua                 formation + orientation math (pure functions)
│   │   ├── FX.lua                    highlights, glow, particles, trails, sound
│   │   ├── UI.lua                    the entire HUD, built in code
│   │   ├── Carrier.lua               the engine: grab / carry / release / update
│   │   └── init.lua                  package entry point
│   ├── StarterPlayer/StarterPlayerScripts/OrbitGrabClient.client.lua
│   └── ServerScriptService/OrbitGrabServer.server.lua
├── dist/                             generated single-file builds (see tools/bundle.py)
├── tools/bundle.py                   flattens src/ → dist/ for the paste-in workflow
└── tests/                            headless smoke tests (see below)
```

---

## Tests

The whole system runs headless against a small Roblox mock:

```bash
cd tests && npm install      # pulls fengari (a Lua VM in JavaScript)
npm test                     # 73 checks, both the module tree and the bundle
```

```
ALL 64 CHECKS PASSED         # grab, carry, 12 formations, throw, burst, explode,
                             # park, undo, drop, vacuum, models, tuning, input,
                             # chat, limits, death cleanup, 10s stability
BUNDLE: ALL 9 CHECKS PASSED  # dist/OrbitGrab_AllInOne.client.lua
```

`tests/roblox_mock.lua` is a stand-in for the engine, not an emulator — it validates logic and catches nil indexes, bad arguments and typos. Still press Play in Studio before you ship.

---

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Parts move for me, nobody else sees it | Add `OrbitGrabServer.server.lua` to ServerScriptService |
| Right-click opens the Roblox menu | Use **R**; or rebind in `Config.Keys.Throw` |
| Can't grab something | Too big (`MaxPartSize`), locked (`AllowLocked = false`), has `OrbitGrabIgnore`, or it's your own character |
| Grabbing a huge Model grabs one brick | It has more than `MaxModelParts` (150) parts — raise it, or set a `PrimaryPart` |
| "Carry limit reached" | `Config.General.MaxCarried`, or `/orb max 200` |
| Orbiting parts look static | Press **F** — you paused them |
| Parts jitter / lag behind | Lower `Config.Orbit.Smoothing` (floatier) or raise it (snappier) |
| I want the HUD gone | **H**, or `Config.UI.Enabled = false` |

---

## Easy extensions

* **New formation** — add a name to `Config.Orbit.Formations` and a branch in `Orbit.LocalPosition`. That's the whole checklist; the HUD, cycling and chat command pick it up for free.
* **Grab filter** — `Config.General.OnlyInFolder = "Loot"` turns it into a pickup system.
* **Sounds** — `Config.Sounds.Enabled = true` and paste four asset ids.
* **Server-side game logic** — the ownership RemoteEvents are the natural hook for "you may only carry X", persistent inventories, or scoring.
* **Script it from elsewhere** — the client exposes the live system:
  ```lua
  _G.OrbitGrabCarrier:Burst()
  _G.OrbitGrab.Config.Orbit.Formation = "Galaxy"
  ```

# Wraith ARS 2X for MTA:SA

**MTA:SA port by S300by** — contact / support: **Discord: S300by**

A full port of the **Wraith ARS 2X** police radar (originally `wk_wars2x` for FiveM by
WolfKnight) to **Multi Theft Auto: San Andreas**. The base is WolfKnight's FiveM
resource (see the headers in the code); the whole thing was reworked and ported to
MTA:SA by me — S300by.

A working K-band style traffic radar with a front and rear antenna, a fast-lock system,
an operator remote, and a two-camera **ALPR plate reader** — rendered by the original
HTML/CSS/JS interface running inside MTA's CEF browser, so it looks and behaves like the
FiveM original.

---

## Features

**Radar**
- Front and rear antenna, each independently transmitting
- Same-lane / opposing-lane modes with adjustable sensitivity (0.2 – 1.0)
- Strongest target + fastest target tracking, with the classic "fast" box
- Manual speed lock per antenna, or automatic lock above a configurable limit
- km/h or mph
- Audible beep, verbal lock confirmation, speed alert — all with per-player volume

**Plate reader (ALPR)**
- Front and rear camera, reads plates of vehicles ahead of and behind the patrol car
- Manual lock per camera
- BOLO plate list: set a plate and the reader locks onto it automatically
- Server-side hook (`ACCESS.lookupPlate`) so you can flag stolen/wanted plates from your
  own database and have the reader lock and alert on a hit

**Interface**
- The original Wraith ARS 2X UI: draggable radar box, plate reader box and operator remote
- Per-player UI scale and safezone
- Key lock so the officer cannot bump a lock off by accident

**Persistence**
- Everything a player sets up — menu options, UI layout and scale, **plus the device
  state** (power, which panels are shown, antenna modes) — is stored **server-side** and
  restored on login. Set the radar up once and find it identical after a relog, a
  resource restart, or on a different PC.
- Storage is a plain XML file in the resource folder. **No database required.**

---

## Requirements

- MTA:SA server **1.5.9** or newer
- CEF enabled on the server (`<setting name="browser_..."/>` defaults are fine; remote
  pages are not used — everything is served locally from the resource)
- No external resources, no MySQL, no dependencies

---

## Installation

1. Drop the `mta-wraith-radar` folder into your server's `resources` directory.
2. Add it to `mtaserver.conf`, or start it manually:

   ```
   start mta-wraith-radar
   ```
3. Open `config_access.lua` and pick who may use the radar (see below).

That's it. Out of the box the radar is available to the **driver of any GTA:SA police
vehicle**.

---

## Configuration

There are two config files, and you normally only need the first one.

### `config_access.lua` — how the radar plugs into *your* server

**1. Who may use it** — `ACCESS.mode`:

| Mode | Meaning |
|---|---|
| `"everyone"` | Any driver of any vehicle. Good for testing or freeroam. |
| `"police"` | Only GTA:SA law-enforcement vehicle models (list is editable). **Default.** |
| `"elementdata"` | Only vehicles carrying a given element data key, optionally gated on a player element data key too (e.g. an on-duty flag). |
| `"acl"` | Only players in a given ACL group, in any vehicle. |
| `"custom"` | Your own client-side function. |

Example — a roleplay server where the vehicle is flagged as a police car and the player
must be on duty:

```lua
ACCESS.mode             = "elementdata"
ACCESS.vehicleDataKey   = "vehicle:police"
ACCESS.playerDataKey    = "player:duty"
ACCESS.playerDataValue  = "POLICE"
```

**2. Notifications** — by default short radar messages go to the chatbox. Point
`ACCESS.notify` at your own notification resource if you have one.

**3. Plate lookups** — fill in `ACCESS.lookupPlate(player, plate)` (server-side). Return
a short string and the reader locks that camera and alerts the officer; return `nil` for
no hit:

```lua
function ACCESS.lookupPlate(player, plate)
    local rows = exports["my-db"]:dbGet("SELECT reason FROM bolo WHERE plate=? LIMIT 1", plate)
    if rows and rows[1] then return "BOLO: " .. rows[1].reason end
    return nil
end
```

**4. Settings storage key** — `ACCESS.storageMode` is `"account"` (MTA account name),
`"serial"`, or `"custom"` if your gamemode has its own account IDs.

### `config.lua` — how the radar itself behaves

Untouched from the original: default keybinds, default operator menu values (sensitivity,
volumes, speed unit, auto-lock limit), default UI scale and safezone, passenger view and
passenger control toggles.

---

## Controls (defaults)

| Key | Action |
|---|---|
| `J` | Open / close the operator remote (also `ESC` or right click) |
| `Numpad 8` / `Numpad 5` | Lock / unlock the **front** / **rear** antenna speed |
| `Numpad 9` / `Numpad 6` | Lock / unlock the **front** / **rear** plate reader camera |
| `L` | Key lock |

All keys are in `CONFIG.keyDefaults` in `config.lua`.

`/reset_radar_data` wipes the calling player's stored radar settings.

---

## Integration API

**Server export — force a plate reader camera to lock:**

```lua
exports["mta-wraith-radar"]:TogglePlateLock(player, "front", true, true)
--                                          player, cam, beepAudio, boloAudio
```

**Server event — fired for every newly scanned plate:**

```lua
addEvent("wraithRadar:onPlateScanned", true)
addEventHandler("wraithRadar:onPlateScanned", root, function(player, cam, plate)
    -- cam is "front" or "rear"
    outputChatBox(getPlayerName(player) .. " scanned " .. plate)
end)
```

Use the event for logging/MDT feeds, and `ACCESS.lookupPlate` when you want the reader
itself to react.

---

## How the port works

- **The NUI is the original.** `radar.html/css/js` run in MTA's CEF browser
  (`guiCreateBrowser` → `http://mta/local/nui/radar.html`). The only changes: a local
  jQuery instead of FiveM's built-in one, and `sendData()` posting through
  `mta.triggerEvent` instead of a NUI fetch.
- **`compat.lua` / `compat_sv.lua`** translate the FiveM natives to MTA: Citizen threads
  become coroutines pumped on `onClientPreRender`, vectors, entity/vehicle natives,
  raytraces, KVP, the NUI bridge and `json`.
- **`cl_*.lua` / `sv_*.lua`** are the original game logic with only the changes Lua 5.1
  and MTA force (`#vector` → `vLen`, entity comparisons, vehicle validity through
  `WK_IsRadarVehicle`).
- **`integration.lua` / `integration_sv.lua`** are the MTA-specific glue: browser
  creation, settings persistence, access checks and plate lookups.
- **Plate search.** FiveM's 5 m shapetest capsule has no MTA equivalent, and a thin
  raycast would only catch a plate exactly on the axis. `UTIL:GetVehicleInDirection` is
  rewritten to search vehicles in the patrol car's local space — a box with the same
  reach (50 m) and width as the original capsule — and takes the nearest vehicle with a
  plate in clear line of sight.
- **Line of sight** is sampled at two heights so dips and crests in the road do not make
  the radar refuse a car in plain view, while a wall still blocks it.

---

## Known limitations

- MTA has no plate *design* index, so the plate reader always renders design 0.
- Passenger view / passenger control (`CONFIG.allow_passenger_view`) is present from the
  original but **not wired up** in this port; leave it `false`.
- Sonoran CAD integration (`CONFIG.use_sonorancad`) is FiveM-only and does nothing here.
- Sounds play through HTML5 audio inside CEF.

---

## Support & contact

Everything around this MTA:SA port — questions, bugs, integration help — goes directly
to me:

**Discord: `S300by`**

That is the only contact point for this port. Please do not take port issues anywhere
else.

---

## Credits & license

The base is the original **Wraith ARS 2X** (`wk_wars2x`) for FiveM by **WolfKnight**
— MIT License, Copyright (c) 2020-2021 WolfKnight (credited in the header of every
source file). The interface assets (HTML/CSS/JS, images, fonts, sounds) come from the
original and remain his work.

The **MTA:SA port** — the compatibility layer, the CEF/NUI bridge, server-side
persistence, the access/integration layer and the rewritten plate search — is by
**S300by**, Copyright (c) 2026.

Released under the same **MIT License** — see [LICENSE](LICENSE). You may use, modify,
redistribute and sell it, provided the copyright notice and the license text stay
included.

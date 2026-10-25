--[[
    Wraith ARS 2X for MTA:SA - FiveM -> MTA compatibility layer (CLIENT)
    MTA:SA port by S300by - contact: Discord S300by

    Defines the FiveM natives used by cl_*.lua in MTA terms. Must load FIRST
    (before config/utils/radar/...). The original game logic is untouched.

    Base: Wraith ARS 2X (wk_wars2x) for FiveM by WolfKnight (MIT).
]]--

--=================================================================
-- Basics
--=================================================================
function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    outputDebugString("[wk] " .. table.concat(t, "  "))
end

function GetGameTimer() return getTickCount() end
function GetCurrentResourceName() return getResourceName(getThisResource()) end

--=================================================================
-- Citizen thread scheduler (coroutines pumped every frame)
--=================================================================
Citizen = Citizen or {}
local _threads = {}

function Citizen.CreateThread(fn)
    _threads[#_threads + 1] = { co = coroutine.create(fn), wake = 0 }
end

function Citizen.Wait(ms)
    coroutine.yield(ms or 0)
end

function Citizen.SetTimeout(ms, fn)
    setTimer(fn, math.max(tonumber(ms) or 0, 1), 1)
end

CreateThread = Citizen.CreateThread
Wait        = Citizen.Wait
SetTimeout  = Citizen.SetTimeout

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    for i = #_threads, 1, -1 do
        local th = _threads[i]
        if now >= th.wake then
            local ok, res = coroutine.resume(th.co)
            if not ok then
                outputDebugString("[wk thread error] " .. tostring(res), 1)
                table.remove(_threads, i)
            elseif coroutine.status(th.co) == "dead" then
                table.remove(_threads, i)
            else
                th.wake = now + (tonumber(res) or 0)
            end
        end
    end
end)

--=================================================================
-- Vectors (metatable for +,-; #vector does not work in Lua 5.1 -> vLen)
--=================================================================
local vmeta = {}
vmeta.__index = vmeta
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = (a.z or 0) + (b.z or 0) }, vmeta) end
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = (a.z or 0) - (b.z or 0) }, vmeta) end
vmeta.__mul = function(a, s)
    if type(a) == "number" then a, s = s, a end
    return setmetatable({ x = a.x * s, y = a.y * s, z = (a.z or 0) * s }, vmeta)
end

function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z or 0 }, vmeta) end
function vector2(x, y)    return setmetatable({ x = x, y = y, z = 0 }, vmeta) end

function vLen(v) return math.sqrt(v.x * v.x + v.y * v.y + (v.z or 0) * (v.z or 0)) end
function norm(v)
    local l = vLen(v)
    if l == 0 then return vector3(0, 0, 0) end
    return vector3(v.x / l, v.y / l, (v.z or 0) / l)
end
function dot(a, b) return a.x * b.x + a.y * b.y + (a.z or 0) * (b.z or 0) end

--=================================================================
-- Ped / vehicle / entity
--=================================================================
function PlayerPedId() return localPlayer end

function GetVehiclePedIsIn(ped, lastVeh)
    local v = getPedOccupiedVehicle(ped)
    return v or 0
end

-- FiveM seats: -1 = driver, 0 = front passenger, 1.. rear
-- MTA seats:    0 = driver, 1 = front passenger, ...
function GetPedInVehicleSeat(veh, seat)
    if not veh or veh == 0 or not isElement(veh) then return 0 end
    local mtaSeat = (seat == -1) and 0 or (seat + 1)
    local occ = getVehicleOccupant(veh, mtaSeat)
    return occ or 0
end

function IsPedGettingIntoAVehicle(ped) return false end          -- passenger sync only (disabled)
function GetVehiclePedIsEntering(ped) return 0 end
function GetVehicleClass(veh) return isElement(veh) and 18 or -1 end -- validity is handled by integration.lua
function IsPedAPlayer(ped) return isElement(ped) and getElementType(ped) == "player" end
function IsPauseMenuActive() return false end

function DoesEntityExist(e) return isElement(e) and true or false end
function IsEntityAVehicle(e) return isElement(e) and getElementType(e) == "vehicle" end

function GetEntityCoords(e)
    if not isElement(e) then return vector3(0, 0, 0) end
    local x, y, z = getElementPosition(e)
    return vector3(x, y, z)
end

function GetEntityHeading(e)
    local _, _, rz = getElementRotation(e)
    return rz
end

function GetEntityPitch(e)
    local rx = getElementRotation(e)
    return rx
end

-- FiveM GetEntitySpeed returns m/s. MTA: velocity length * 50 = m/s
function GetEntitySpeed(e)
    local vx, vy, vz = getElementVelocity(e)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 50
end

function GetEntityModel(e) return getElementModel(e) end

function GetOffsetFromEntityInWorldCoords(e, ox, oy, oz)
    local m = getElementMatrix(e)
    local x = ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1]
    local y = ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2]
    local z = ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
    return vector3(x, y, z)
end

function HasEntityClearLosToEntity(a, b, traceType)
    local ax, ay, az = getElementPosition(a)
    local bx, by, bz = getElementPosition(b)
    -- isLineOfSightClear: 7 flags (build,veh,ped,obj,dummy,seeThrough,ignoreCam) + ignoredElement.
    -- Only buildings block, so a car behind a wall is missed while traffic does not
    -- block the line of sight.
    --
    -- The LOS is sampled at TWO heights (0.9 and 1.5 m above the centre): on rolling
    -- roads (dips, crests) a straight 3D line from the patrol car to the target often
    -- sinks below the surface and isLineOfSightClear reports it as blocked by terrain,
    -- so the radar would refuse to measure a car in plain sight. A wall blocks both
    -- heights, a small crest only the lower one - one clear sample is enough.
    for _, h in ipairs({ 0.9, 1.5 }) do
        if isLineOfSightClear(ax, ay, az + h, bx, by, bz + h,
                true, false, false, false, false, false, false, a) then
            return true
        end
    end
    return false
end

-- Model dims fallback (overridden in practice by RADAR:GetDynamicRadius in integration.lua)
function GetModelDimensions(mdl)
    return vector3(-1.2, -2.6, -1.0), vector3(1.2, 2.6, 0.8)
end

function GetAllVehicles() return getElementsByType("vehicle") end

-- FiveM entity enumeration -> MTA.
-- UTIL:EnumerateVehicles() in cl_utils.lua walks vehicles through the FiveM natives
-- FindFirstVehicle/FindNextVehicle/EndFindVehicle. Without them the enumeration
-- fails immediately, the vehicle pool (RADAR.vehiclePool) stays empty and the radar
-- never picks up any speeds. They are replaced with a snapshot of streamed-in
-- vehicles - exactly the ones the client holds locally with a valid velocity.
local _vehFinds = {}
local _vehFindSeq = 0

function FindFirstVehicle()
    _vehFindSeq = _vehFindSeq + 1
    local handle = _vehFindSeq
    local list = getElementsByType("vehicle", root, true)
    local first = list[1]
    if not first then return handle, 0 end
    _vehFinds[handle] = { list = list, i = 1 }
    return handle, first
end

function FindNextVehicle(handle)
    local st = _vehFinds[handle]
    if not st then return false, 0 end
    st.i = st.i + 1
    local v = st.list[st.i]
    if not v then return false, 0 end
    return true, v
end

function EndFindVehicle(handle)
    _vehFinds[handle] = nil
end

-- Used by UTIL:IsPlayerInVeh (auto-lock on players only); fast-lock breaks without it
function GetVehicleMaxNumberOfPassengers(veh)
    if not isElement(veh) then return 0 end
    return getVehicleMaxPassengers(veh) or 0
end

-- Model type via MTA getVehicleType (accepts an element or a model id)
local function vtypeOf(mdl)
    local ok, t = pcall(getVehicleType, mdl)
    return ok and t or ""
end
function IsThisModelABoat(mdl)  return vtypeOf(mdl) == "Boat" end
function IsThisModelAHeli(mdl)   return vtypeOf(mdl) == "Helicopter" end
function IsThisModelAPlane(mdl)  return vtypeOf(mdl) == "Plane" end

function IsVehiclePreviouslyOwnedByPlayer(veh)
    -- a "real" vehicle = has an occupant / is persistent (not ambient traffic)
    return getVehicleOccupant(veh, 0) ~= false
end

function GetVehicleNumberPlateText(veh) return getVehiclePlateText(veh) or "" end
function GetVehicleNumberPlateTextIndex(veh) return 0 end  -- MTA has no plate design index

-- Shapetest (unused - UTIL:GetVehicleInDirection is overridden in integration.lua)
function StartShapeTestCapsule() return 0 end
function GetShapeTestResult() return 0, false, vector3(0,0,0), vector3(0,0,0), 0 end

--=================================================================
-- KVP storage (kept server-side per player, see sv_settings.lua)
--
-- The original stored a JSON file on the client, which disappears with a wiped
-- MTA cache and does not follow the player to another PC. The radar settings
-- therefore live on the server; the client only keeps a copy here for the
-- synchronous reads the original code relies on.
--=================================================================
local _kvp = {}
local _kvpReady = false
local _saveTimer = nil

-- Called by integration.lua as soon as the server data arrives
function WK_SetKvpTable(t)
    _kvp = type(t) == "table" and t or {}
    _kvpReady = true
end

function WK_IsKvpReady() return _kvpReady end

local function kvpSave()
    -- Until we know what is stored there is nothing to save - a write right after
    -- start (with an empty table) would wipe the player's saved settings.
    if not _kvpReady then return end

    -- Debounce - a burst of changes (e.g. walking the menu) becomes one write
    if isTimer(_saveTimer) then killTimer(_saveTimer) end
    _saveTimer = setTimer(function()
        triggerServerEvent("wraith:kvpSave", resourceRoot, json.encode(_kvp))
    end, 1000, 1)
end

function GetResourceKvpString(k) local v = _kvp[k]; return v ~= nil and tostring(v) or nil end
function GetResourceKvpInt(k)    return tonumber(_kvp[k]) or 0 end
function SetResourceKvp(k, v)    _kvp[k] = v; kvpSave() end
function SetResourceKvpInt(k, v) _kvp[k] = tonumber(v) or 0; kvpSave() end
function DeleteResourceKvp(k)    _kvp[k] = nil; kvpSave() end

--=================================================================
-- json (encode/decode - postMessage into the NUI needs valid JSON)
--=================================================================
json = {}
local function jsonEncode(v)
    local tv = type(v)
    if tv == "nil" then return "null"
    elseif tv == "number" then return tostring(v)
    elseif tv == "boolean" then return v and "true" or "false"
    elseif tv == "string" then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
            local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return map[c] or string.format('\\u%04x', c:byte())
        end) .. '"'
    elseif tv == "table" then
        -- array vs object
        local n, isArr = 0, true
        for k in pairs(v) do
            n = n + 1
            if type(k) ~= "number" then isArr = false end
        end
        local parts = {}
        if isArr and n > 0 then
            for i = 1, n do parts[i] = jsonEncode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, val in pairs(v) do
                parts[#parts + 1] = jsonEncode(tostring(k)) .. ":" .. jsonEncode(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end
json.encode = function(v) return jsonEncode(v) end
json.decode = function(s)
    if type(s) ~= "string" then return nil end
    local ok, t = pcall(fromJSON, s)
    if ok then return t end
    return nil
end

--=================================================================
-- FiveM (net) events -> MTA
--=================================================================
function RegisterNetEvent(name) addEvent(name, true) end

function AddEventHandler(name, fn)
    -- A FiveM handler takes the arguments directly; MTA passes source separately
    addEventHandler(name, localPlayer, function(...) fn(...) end)
    addEventHandler(name, root, function(...) fn(...) end)
end

local _commands = {}
function RegisterCommand(name, fn)
    _commands[name] = fn
    addCommandHandler(name, function() fn() end)
end

-- FiveM key name -> MTA key name
local function mapKey(k)
    k = tostring(k or ""):lower()
    local np = k:match("^numpad(%d)$")
    if np then return "num_" .. np end
    return k
end

-- FiveM RegisterKeyMapping(command, desc, device, key) -> bindKey on the stored command
WK_KEYBINDS = {}
function RegisterKeyMapping(command, desc, device, key)
    local mtaKey = mapKey(key)
    local handler = function()
        local fn = _commands[command]
        if fn then fn() end
    end
    bindKey(mtaKey, "down", handler)
    WK_KEYBINDS[#WK_KEYBINDS + 1] = { key = mtaKey, handler = handler }
end

function GetPlayerServerId(ply) return 0 end                 -- passenger sync (disabled)
function NetworkGetPlayerIndexFromPed(ped) return 0 end

function TriggerServerEvent(name, ...)
    triggerServerEvent(name, resourceRoot, ...)
end

function TriggerEvent(name, ...)
    -- Some FiveM events (chat:addSuggestion) do not exist in MTA -> ignore silently
    if not name then return end
    pcall(triggerEvent, name, localPlayer, ...)
end

-- Decorators (FiveM) - unused (passenger sync is disabled)
function DecorRegister() end
function DecorSetInt() end
function DecorSetBool() end
function DecorGetInt() return 0 end
function DecorGetBool() return false end
function DecorExistOn() return false end

-- Notification natives -> no-op (UTIL:Notify is overridden in integration.lua)
function SetNotificationTextEntry() end
function AddTextComponentSubstringPlayerName() end
function AddTextComponentString() end
function DrawNotification() end
function SetTextFont() end
function SetTextProportional() end
function SetTextScale() end
function SetTextColour() end
function SetTextDropShadow() end
function SetTextEdge() end
function SetTextCentre() end
function SetTextOutline() end
function SetTextEntry() end
function DrawText() end

--=================================================================
-- NUI bridge (wired up in integration.lua once the browser exists)
--=================================================================
WK_BROWSER = nil
WK_BROWSER_READY = false
local _nuiCallbacks = {}
local _nuiQueue = {}

function SendNUIMessage(tbl)
    local jsonStr = json.encode(tbl)
    if not WK_BROWSER or not isElement(WK_BROWSER) or not WK_BROWSER_READY then
        -- browser is not document-ready yet -> queue, so the first messages survive
        _nuiQueue[#_nuiQueue + 1] = jsonStr
        return
    end
    executeBrowserJavascript(WK_BROWSER, "window.postMessage(" .. jsonStr .. ", '*');")
end

-- called by integration.lua on onClientBrowserDocumentReady
function WK_FlushNui()
    if not WK_BROWSER or not isElement(WK_BROWSER) then return end
    for _, jsonStr in ipairs(_nuiQueue) do
        executeBrowserJavascript(WK_BROWSER, "window.postMessage(" .. jsonStr .. ", '*');")
    end
    _nuiQueue = {}
end

function RegisterNUICallback(name, fn) _nuiCallbacks[name] = fn end

-- called by integration.lua from the wk:nuicb event
function WK_HandleNuiCallback(name, dataJson)
    local cb = _nuiCallbacks[name]
    if not cb then return end
    local data = (dataJson and dataJson ~= "") and json.decode(dataJson) or {}
    cb(data, function() end)
end

function SetNuiFocus(hasFocus, hasCursor)
    if WK_BROWSER and isElement(WK_BROWSER) then
        if hasFocus then focusBrowser(WK_BROWSER) else focusBrowser(nil) end
    end
    showCursor(hasCursor and true or false, false)
end

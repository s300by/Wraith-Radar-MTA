--[[---------------------------------------------------------------------------------------
    Wraith ARS 2X for MTA:SA - MTA glue layer (CLIENT)
    MTA:SA port by S300by - contact: Discord S300by

    Loaded LAST (after all cl_*.lua). Replaces the FiveM-specific parts of the
    original script with MTA equivalents and spawns the CEF browser that runs
    the original NUI.

    Gamemode-specific behaviour is NOT configured here - see config_access.lua.
---------------------------------------------------------------------------------------]]--

local sx, sy = guiGetScreenSize()

--=================================================================
-- Is this vehicle a "radar vehicle"? (drives validity in cl_player.lua)
--=================================================================
local function hasData(el, key)
    local v = getElementData(el, key)
    return v ~= nil and v ~= false and v ~= "" and v ~= 0
end

function WK_IsRadarVehicle(veh)
    if not isElement(veh) then return false end

    local mode = ACCESS.mode

    if mode == "everyone" then
        return true

    elseif mode == "police" then
        return ACCESS.policeModels[getElementModel(veh)] == true

    elseif mode == "elementdata" then
        if ACCESS.playerDataKey then
            if getElementData(localPlayer, ACCESS.playerDataKey) ~= ACCESS.playerDataValue then
                return false
            end
        end
        if ACCESS.vehicleDataKey then
            return hasData(veh, ACCESS.vehicleDataKey)
        end
        return true

    elseif mode == "acl" then
        -- Filled in by the server (ACL is not readable client-side)
        return getElementData(localPlayer, "wraith:aclAllowed") == true

    elseif mode == "custom" then
        local ok, res = pcall(ACCESS.customCheck, veh)
        return ok and res == true
    end

    return false
end

--=================================================================
-- Finding the vehicle in front of / behind the patrol car (plate reader)
--
-- The original uses a FiveM shapetest capsule with a 5 m radius. MTA has no
-- capsule test, and a thin processLineOfSight only catches a plate when the
-- target sits exactly on the ray - so the reader would pick up almost nothing.
-- Instead we look for vehicles directly in the patrol car's local space:
-- a box with the same reach and width as the original capsule.
--=================================================================
local READER_MIN_DIST    = 3.0   -- m - below this the car is basically on the bumper
local READER_MAX_DIST    = 50.0  -- m - reader range (same as the original)
local READER_HALF_WIDTH  = 5.0   -- m - radius of the original capsule (covers the next lane)
local READER_HALF_HEIGHT = 4.0   -- m - height tolerance (hills, bridges, flyovers)

-- World coords -> local space of the entity the matrix came from.
-- The rotation part is orthonormal, so the inverse is just the transpose.
local function toLocal(m, wx, wy, wz)
    local dx, dy, dz = wx - m[4][1], wy - m[4][2], wz - m[4][3]
    return dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
           dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
           dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
end

function UTIL:GetVehicleInDirection(entFrom, coordFrom, coordTo)
    if not isElement(entFrom) then return 0 end

    local m = getElementMatrix(entFrom)
    if not m then return 0 end

    -- READER:Main calls this separately for the front and rear camera and the
    -- only difference is the target point, so we take the direction from it.
    local _, targetY = toLocal(m, coordTo.x, coordTo.y, coordTo.z)
    local sign = targetY >= 0 and 1 or -1

    local dim, int = getElementDimension(entFrom), getElementInterior(entFrom)
    local best, bestDist = 0, math.huge

    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        if veh ~= entFrom and getElementDimension(veh) == dim and getElementInterior(veh) == int then
            local vx, vy, vz = getElementPosition(veh)
            local lx, ly, lz = toLocal(m, vx, vy, vz)
            ly = ly * sign

            if ly >= READER_MIN_DIST and ly <= READER_MAX_DIST
                and math.abs(lx) <= READER_HALF_WIDTH
                and math.abs(lz) <= READER_HALF_HEIGHT
                and ly < bestDist then
                -- Vehicles without a plate (bikes) are ignored - otherwise a
                -- passing bike would wipe the last read plate off the display.
                local plate = getVehiclePlateText(veh)

                -- Closest car wins, so a car behind another car does not get
                -- read by itself; the LOS check is only here for cars behind
                -- walls and buildings.
                if plate and plate ~= "" and HasEntityClearLosToEntity(entFrom, veh, 15) then
                    best, bestDist = veh, ly
                end
            end
        end
    end

    return best
end

--=================================================================
-- Dynamic radius (MTA bounding box instead of GetModelDimensions)
--=================================================================
function RADAR:GetDynamicRadius(veh)
    local mdl = GetEntityModel(veh)
    local key = tostring(mdl)
    if not self:DoesDynamicRadiusDataExist(key) then
        local minx, miny, minz, maxx, maxy, maxz = getElementBoundingBox(veh)
        local sizeX = math.abs((maxx or 1.2) - (minx or -1.2))
        local sizeY = math.abs((maxy or 2.6) - (miny or -2.6))
        local sizeZ = math.abs((maxz or 0.8) - (minz or -1.0))
        local numericSize = sizeX + sizeY + sizeZ
        if numericSize <= 0 then numericSize = 6.0 end
        local dynamicRadius = UTIL:Clamp((numericSize * numericSize) / 12, 5.0, 11.0)
        self:InsertDynamicRadiusData(key, dynamicRadius, numericSize)
        return dynamicRadius, numericSize
    end
    return self:GetRadiusData(key)
end

--=================================================================
-- Notifications (see config_access.lua)
--=================================================================
function UTIL:Notify(text)
    local ok, err = pcall(ACCESS.notify, tostring(text))
    if not ok then
        outputChatBox("[Radar] " .. tostring(text), 255, 180, 50)
        outputDebugString("[wraith] ACCESS.notify failed: " .. tostring(err), 1)
    end
end

--=================================================================
-- CEF browser (fullscreen transparent overlay)
--=================================================================
local guiBrowser = nil

addEventHandler("onClientResourceStart", resourceRoot, function()
    guiBrowser = guiCreateBrowser(0, 0, sx, sy, true, true, false)
    WK_BROWSER = guiGetBrowser(guiBrowser)
    guiSetVisible(guiBrowser, false)
    addEventHandler("onClientBrowserCreated", WK_BROWSER, function()
        loadBrowserURL(WK_BROWSER, "http://mta/local/nui/radar.html")
    end)

    -- While the remote is open the browser holds focus and a keypress may never
    -- reach bindKey - so the NUI watches for it itself (see radar.js).
    SendNUIMessage({ _type = "setRemoteKey", key = CONFIG.keyDefaults.remote_control })
end)

-- Once the page has loaded, flush any queued NUI messages
addEventHandler("onClientBrowserDocumentReady", root, function()
    WK_BROWSER_READY = true
    WK_FlushNui()
end)

-- NUI callbacks from JS (mta.triggerEvent("wk:nuicb", name, jsonData))
addEvent("wk:nuicb", false)
addEventHandler("wk:nuicb", root, function(name, dataJson)
    WK_HandleNuiCallback(name, dataJson)
end)

-- Overlay visibility: only on while the player sits in a radar vehicle, so the
-- fullscreen browser cannot grab the cursor for no reason. The radar/reader
-- displays themselves are driven by the NUI via set*DisplayState.
setTimer(function()
    if not isElement(guiBrowser) then return end
    local canView = PLY and PLY.CanViewRadar and PLY:CanViewRadar()
    guiSetVisible(guiBrowser, canView and true or false)
end, 500, 0)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if isElement(guiBrowser) then destroyElement(guiBrowser) end
    showCursor(false, false)
end)

--=================================================================
-- Persistent settings (stored server-side, see sv_settings.lua)
--
-- The original only remembers the operator menu and the UI layout via KVP.
-- The device state (power, displayed radar/reader, antenna modes) was reset on
-- every load in FiveM - here it is saved too, so an officer sets the radar up
-- once and finds it the same way after a relog or a resource restart.
--=================================================================
local STATE_KEY = "wk_wars2x_state"
local applying = false          -- restore in progress -> do not save it straight back

local function saveState()
    if applying or not RADAR or not READER then return end

    local antennas = {}
    for _, ant in ipairs({ "front", "rear" }) do
        antennas[ant] = {
            xmit = RADAR:IsAntennaTransmitting(ant),
            mode = RADAR:GetAntennaMode(ant)
        }
    end

    SetResourceKvp(STATE_KEY, json.encode({
        power    = RADAR:IsPowerOn(),
        radar    = RADAR:GetDisplayState(),
        reader   = READER:GetDisplayState(),
        antennas = antennas
    }))
end

-- Wraps a method so the state is saved once it has run
local function persistAfter(tbl, name)
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        saveState()
        return unpack(r)
    end
end

persistAfter(RADAR, "SetPowerState")
persistAfter(RADAR, "ToggleDisplayState")
persistAfter(RADAR, "ToggleAntenna")
persistAfter(RADAR, "SetAntennaMode")
persistAfter(READER, "ToggleDisplayState")

local function applyState()
    applying = true

    -- Operator menu (volumes, sensitivity, units...)
    RADAR:UpdateOptionIndexes(true)

    -- A stored blob may be older/incomplete and a missing key would break the
    -- raytrace maths (nil * number). Fill gaps straight from the config - going
    -- through SetSettingValue would call UpdateRayEndCoords before both keys exist.
    for k, v in pairs(CONFIG.menuDefaults) do
        if RADAR.vars.settings[k] == nil then RADAR.vars.settings[k] = v end
    end

    -- The same/opp sensitivity defines the raytrace end points - without this the
    -- stored sensitivity would only take effect after the menu is touched once.
    RADAR:UpdateRayEndCoords()

    -- UI layout and scale
    local uiData = GetResourceKvpString("wk_wars2x_ui_data")
    if uiData then
        local ui = json.decode(uiData)
        if type(ui) == "table" then
            SendNUIMessage({ _type = "loadUiSettings", data = ui })
        end
    end

    -- Device state
    local raw = GetResourceKvpString(STATE_KEY)
    local st = raw and json.decode(raw) or nil

    if type(st) == "table" then
        -- true = skip the two second warm-up simulation, the radar just comes up on
        if st.power then RADAR:SetPowerState(true, true) end

        if type(st.antennas) == "table" then
            for _, ant in ipairs({ "front", "rear" }) do
                local a = st.antennas[ant]
                if type(a) == "table" then
                    -- Set directly rather than via ToggleAntenna/SetAntennaMode -
                    -- those would replay the beep and the xmit voice lines.
                    RADAR.vars.antennas[ant].xmit = a.xmit and true or false
                    RADAR.vars.antennas[ant].mode = tonumber(a.mode) or 0
                end
            end
        end

        RADAR.vars.displayed  = st.radar and true or false
        READER.vars.displayed = st.reader and true or false
    end

    -- Displays: the validation threads still handle hiding them outside a vehicle
    SendNUIMessage({ _type = "setRadarDisplayState", state = RADAR:GetDisplayState() })
    SendNUIMessage({ _type = "setReaderDisplayState", state = READER:GetDisplayState() })
    RADAR:SendSettingUpdate()

    applying = false
end

addEvent("wraith:kvpData", true)
addEventHandler("wraith:kvpData", localPlayer, function(raw)
    if WK_IsKvpReady() then return end

    local t = (type(raw) == "string" and raw ~= "") and json.decode(raw) or nil
    WK_SetKvpTable(type(t) == "table" and t or {})

    -- If the restore blew up halfway, `applying` would stay true and the radar
    -- would silently stop saving from then on - hence the guard.
    local ok, err = pcall(applyState)
    applying = false
    if not ok then
        outputDebugString("[wraith] settings restore failed: " .. tostring(err), 1)
    end
end)

-- Settings belong to an account, which may only exist after login, and the
-- resource starts well before that - so we keep asking until we get an answer.
local requestedAt = 0
local loadTimer
loadTimer = setTimer(function()
    if WK_IsKvpReady() then
        if isTimer(loadTimer) then killTimer(loadTimer) end
        return
    end
    if getTickCount() - requestedAt < 10000 then return end   -- retry in case the reply never came

    requestedAt = getTickCount()
    triggerServerEvent("wraith:kvpLoad", resourceRoot)
end, 2000, 0)

--=================================================================
-- Server-side plate hit (BOLO / wanted / stolen) -> lock + notification
--=================================================================
addEvent("wraith:plateHit", true)
addEventHandler("wraith:plateHit", localPlayer, function(cam, plate, reason)
    if not READER then return end
    READER:SetBoloPlate(plate)          -- so it re-locks on the next pass too
    READER:LockCam(cam, false, true)
    UTIL:Notify("ALPR - " .. tostring(plate) .. ": " .. tostring(reason))
end)

--[[---------------------------------------------------------------------------------------
    Wraith ARS 2X for MTA:SA - server integration config (SHARED: client + server)
    MTA:SA port by S300by - contact: Discord S300by

    Everything that ties the radar to YOUR gamemode lives in this one file.
    The rest of the resource is gamemode-agnostic - you should not need to touch it.
---------------------------------------------------------------------------------------]]--

ACCESS = {}

--=================================================================
-- 1) WHO MAY USE THE RADAR
--
-- Pick one mode. If you need something the modes do not cover, set
-- ACCESS.mode = "custom" and write your own check in ACCESS.customCheck below.
--
--   "everyone"   - any driver of any vehicle (good for testing / freeroam)
--   "police"     - only GTA:SA police vehicle models (see ACCESS.policeModels)
--   "elementdata"- only vehicles that carry a given element data key
--                  AND (optionally) players that carry a given element data key
--   "acl"        - only players in the given ACL group (any vehicle)
--   "custom"     - your own function
--=================================================================
ACCESS.mode = "police"

-- Used by mode "police". GTA:SA law-enforcement vehicle model IDs.
ACCESS.policeModels = {
    [596] = true,   -- Police Car (LS)
    [597] = true,   -- Police Car (SF)
    [598] = true,   -- Police Car (LV)
    [599] = true,   -- Police Ranger
    [601] = true,   -- S.W.A.T. Van
    [523] = true,   -- Police Bike (HPV1000)
    [427] = true,   -- Enforcer
    [428] = true,   -- Securicar
    [490] = true,   -- FBI Rancher
    [528] = true,   -- FBI Truck
    [497] = true,   -- Police Maverick
}

-- Used by mode "elementdata".
-- The vehicle must have this element data set to a truthy value (anything except
-- false / nil / "" / 0). Set to false to skip the vehicle check entirely.
ACCESS.vehicleDataKey = "vehicle:police"

-- Optional extra player gate for mode "elementdata": the player must have this
-- element data set to ACCESS.playerDataValue. Set the key to false to disable.
-- Example for an on-duty check: key = "player:duty", value = "POLICE"
ACCESS.playerDataKey   = false
ACCESS.playerDataValue = true

-- Used by mode "acl". Group name without the "group." prefix.
ACCESS.aclGroup = "Admin"

-- Used by mode "custom". Runs CLIENT-SIDE, once per second per player.
-- `veh` is the vehicle the local player is driving. Return true to allow.
function ACCESS.customCheck(veh)
    -- Example: allow only when the player owns the "police_radar" item
    -- return getElementData(localPlayer, "item:police_radar") == true
    return false
end

--=================================================================
-- 2) NOTIFICATIONS
--
-- The radar sends short status messages ("BOLO plate set to ...", etc.).
-- By default they go to the chatbox. Point this at your own notification
-- resource if you have one.
--=================================================================
ACCESS.notifyExport = false   -- e.g. "my-notifications"

function ACCESS.notify(text)
    -- Called CLIENT-SIDE.
    if ACCESS.notifyExport and exports[ACCESS.notifyExport] then
        -- Adjust the call to match your notification resource's signature:
        -- exports[ACCESS.notifyExport]:createNotification("Radar", text, {255, 180, 50})
        outputChatBox("[Radar] " .. tostring(text), 255, 180, 50)
    else
        outputChatBox("[Radar] " .. tostring(text), 255, 180, 50)
    end
end

--=================================================================
-- 3) PLATE READER LOOKUP (ALPR / BOLO)
--
-- Every time the plate reader picks up a NEW plate, the server fires the
-- event "wraithRadar:onPlateScanned" (see README). If you want the reader to
-- automatically lock onto flagged plates, fill in this function.
--
-- Runs SERVER-SIDE. Return a short string (the hit reason) to trigger a lock,
-- or nil / false for "nothing on this plate".
--
-- Keep it cheap - it runs per scanned plate. Use a cached table or an
-- already-open DB handle rather than a fresh dbConnect.
--=================================================================
function ACCESS.lookupPlate(player, plate)
    -- Example - a hardcoded BOLO list:
    -- local BOLO = { ["ABC123"] = "Stolen vehicle", ["XYZ789"] = "Wanted driver" }
    -- return BOLO[plate]

    -- Example - your own database resource:
    -- local rows = exports["my-db"]:dbGet("SELECT reason FROM bolo WHERE plate=? LIMIT 1", plate)
    -- if rows and rows[1] then return "BOLO: " .. rows[1].reason end

    return nil
end

--=================================================================
-- 4) SETTINGS STORAGE
--
-- Each player's radar setup (operator menu, UI layout, power state, antenna
-- modes) is stored server-side so it survives relogs, resource restarts and
-- a different PC.
--
--   "account" - keyed by the player's MTA account name (default, no setup)
--   "serial"  - keyed by the player's serial (works for guest accounts too)
--   "custom"  - keyed by whatever ACCESS.storageKey returns
--
-- Storage itself is a plain XML file in the resource folder - no database
-- required. See sv_settings.lua if you want to swap in MySQL.
--=================================================================
ACCESS.storageMode = "account"

function ACCESS.storageKey(player)
    -- Used by mode "custom". Return a non-empty string, or nil to skip saving
    -- (e.g. while the player is not logged into your account system yet).
    -- Example: return tostring(getElementData(player, "player:accountId") or "")
    return nil
end

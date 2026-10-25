--[[---------------------------------------------------------------------------------------
    Wraith ARS 2X for MTA:SA - persistent per-player settings (SERVER)
    MTA:SA port by S300by - contact: Discord S300by

    The operator menu, the UI layout and the device state (power, displayed
    panels, antenna modes) are stored per player so they survive a relog, a
    resource restart, a wiped client cache and a different PC.

    Storage is a plain XML file inside the resource folder (settings.xml) - no
    database needed. The key comes from ACCESS.storageMode in config_access.lua.

    `data` is an opaque JSON blob produced by the client KVP shim (compat.lua).
    If you want MySQL instead, replace loadAll() / saveAll() below - nothing
    else in the resource touches storage.
---------------------------------------------------------------------------------------]]--

local STORE_FILE    = "settings.xml"
local MAX_DATA_LEN  = 8192   -- the blob is ~500 B in practice; cap against junk from a client
local SAVE_COOLDOWN = 900    -- ms - the client debounces already, this is just a backstop

local store = {}             -- key -> json blob string
local dirty = false
local lastSave = {}

--=================================================================
-- Storage backend
--=================================================================
local function loadAll()
    local xml = xmlLoadFile(STORE_FILE)
    if not xml then return end

    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local key = xmlNodeGetAttribute(node, "key")
        local val = xmlNodeGetValue(node)
        if key and key ~= "" and val and val ~= "" then
            store[key] = val
        end
    end

    xmlUnloadFile(xml)
end

local function saveAll()
    if not dirty then return end
    dirty = false

    if fileExists(STORE_FILE) then fileDelete(STORE_FILE) end

    local xml = xmlCreateFile(STORE_FILE, "wraithSettings")
    if not xml then
        outputDebugString("[wraith] could not write " .. STORE_FILE, 1)
        return
    end

    for key, val in pairs(store) do
        local node = xmlCreateChild(xml, "player")
        xmlNodeSetAttribute(node, "key", key)
        xmlNodeSetValue(node, val)
    end

    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

--=================================================================
-- Which key does this player's settings live under?
--=================================================================
local function storageKey(plr)
    local mode = ACCESS.storageMode

    if mode == "serial" then
        local serial = getPlayerSerial(plr)
        return (serial and serial ~= "") and ("serial:" .. serial) or nil

    elseif mode == "custom" then
        local ok, key = pcall(ACCESS.storageKey, plr)
        if not ok then
            outputDebugString("[wraith] ACCESS.storageKey failed: " .. tostring(key), 1)
            return nil
        end
        return (type(key) == "string" and key ~= "") and ("custom:" .. key) or nil
    end

    -- default: "account". Guests have no account name to key on, so they fall
    -- back to their serial - otherwise the client would keep retrying forever
    -- and never apply its defaults on a server that does not use accounts.
    local account = getPlayerAccount(plr)
    if account and not isGuestAccount(account) then
        return "account:" .. getAccountName(account)
    end

    local serial = getPlayerSerial(plr)
    return (serial and serial ~= "") and ("serial:" .. serial) or nil
end

--=================================================================
-- Wire-up
--=================================================================
addEventHandler("onResourceStart", resourceRoot, loadAll)

-- Batched write, so a busy patrol shift does not rewrite the file per keystroke
setTimer(saveAll, 10000, 0)
addEventHandler("onResourceStop", resourceRoot, function()
    dirty = true
    saveAll()
end)

-- The client asks for its data as soon as it can be keyed (i.e. after login)
addEvent("wraith:kvpLoad", true)
addEventHandler("wraith:kvpLoad", root, function()
    local plr = client
    if not isElement(plr) then return end

    local key = storageKey(plr)
    -- No key yet (not logged in) -> stay silent, the client retries. Sending an
    -- empty reply here would mark the settings as loaded and lock in defaults.
    if not key then return end

    triggerClientEvent(plr, "wraith:kvpData", plr, store[key] or "")
end)

addEvent("wraith:kvpSave", true)
addEventHandler("wraith:kvpSave", root, function(raw)
    local plr = client
    if not isElement(plr) then return end

    -- The blob is opaque (only the KVP shim in compat.lua reads it), so we just
    -- sanity-check the shape - it is the player's own radar UI state, nothing else.
    if type(raw) ~= "string" or #raw > MAX_DATA_LEN or raw:sub(1, 1) ~= "{" then return end

    local key = storageKey(plr)
    if not key then return end

    local now = getTickCount()
    if (lastSave[plr] or 0) + SAVE_COOLDOWN > now then return end
    lastSave[plr] = now

    store[key] = raw
    dirty = true
end)

addEventHandler("onPlayerQuit", root, function()
    lastSave[source] = nil
end)

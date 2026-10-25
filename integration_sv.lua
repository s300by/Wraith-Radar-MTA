--[[---------------------------------------------------------------------------------------
    Wraith ARS 2X for MTA:SA - server glue (SERVER)
    MTA:SA port by S300by - contact: Discord S300by

    - answers plate scans with a BOLO/wanted lookup (see ACCESS.lookupPlate)
    - re-broadcasts every scan as a public event other resources can listen to
    - keeps the ACL flag in sync when ACCESS.mode == "acl"
---------------------------------------------------------------------------------------]]--

--=================================================================
-- Public event for other resources:
--   addEvent("wraithRadar:onPlateScanned", true)
--   addEventHandler("wraithRadar:onPlateScanned", root, function(player, cam, plate) ... end)
--=================================================================
addEvent("wraithRadar:onPlateScanned", false)

addEvent("wraith:onPlateScanned", true)
addEventHandler("wraith:onPlateScanned", root, function(cam, plate, index)
    local plr = client
    if not isElement(plr) then return end

    plate = tostring(plate or ""):upper()
    if plate == "" then return end
    if cam ~= "front" and cam ~= "rear" then return end

    triggerEvent("wraithRadar:onPlateScanned", resourceRoot, plr, cam, plate)

    local ok, reason = pcall(ACCESS.lookupPlate, plr, plate)
    if not ok then
        outputDebugString("[wraith] ACCESS.lookupPlate failed: " .. tostring(reason), 1)
        return
    end

    if reason and reason ~= "" then
        triggerClientEvent(plr, "wraith:plateHit", plr, cam, plate, tostring(reason))
    end
end)

--=================================================================
-- ACL mode: the client cannot read ACL, so the server flags the player
--=================================================================
local function refreshAcl(plr)
    if ACCESS.mode ~= "acl" then return end
    if not isElement(plr) then return end
    local account = getPlayerAccount(plr)
    local allowed = account and isObjectInACLGroup(
        "user." .. getAccountName(account), aclGetGroup(ACCESS.aclGroup)) or false
    setElementData(plr, "wraith:aclAllowed", allowed and true or false)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, plr in ipairs(getElementsByType("player")) do refreshAcl(plr) end
end)

addEventHandler("onPlayerLogin", root, function() refreshAcl(source) end)
addEventHandler("onPlayerLogout", root, function() refreshAcl(source) end)
addEventHandler("onPlayerJoin", root, function() refreshAcl(source) end)

--[[
    Wraith ARS 2X for MTA:SA - FiveM -> MTA compatibility layer (SERVER)
    MTA:SA port by S300by - contact: Discord S300by

    Must load FIRST on the server (before sv_sync/sv_exports).
    Base: Wraith ARS 2X (wk_wars2x) for FiveM by WolfKnight (MIT).
]]--

function print(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    outputDebugString("[wk-sv] " .. table.concat(t, "  "))
end

function RegisterNetEvent(name) addEvent(name, true) end

function AddEventHandler(name, fn)
    addEventHandler(name, root, function(...)
        -- FiveM `source` = the player who fired the event; in MTA that is `client`
        _G.source = client or source
        fn(...)
    end)
end

-- FiveM TriggerClientEvent(name, target, ...) - target = player element or -1 (everyone)
function TriggerClientEvent(name, target, ...)
    if isElement(target) then
        triggerClientEvent(target, name, resourceRoot, ...)
    elseif target == -1 then
        triggerClientEvent(getElementsByType("player"), name, resourceRoot, ...)
    end
end

function TriggerEvent(name, ...) pcall(triggerEvent, name, resourceRoot, ...) end

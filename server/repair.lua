local QBCore = exports['qb-core']:GetCoreObject()

-- Preview pads needed/available and how many will be used
QBCore.Functions.CreateCallback('pf-mechanicjob:server:calcBrakeRepair', function(source, cb, vehNet)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb({ error = 'Player not found.' }) return end

    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or veh == 0 then cb({ error = 'Vehicle not found.' }) return end

    local state = Entity(veh).state
    local damage = state.partDamage or {}
    local brakeDmg = tonumber(damage.brakes) or 0
    if brakeDmg <= 0 then cb({ error = 'Brakes are already in perfect condition.' }) return end

    local padsNeeded = (brakeDmg >= 100) and 4 or math.max(1, math.min(4, math.ceil(brakeDmg / 25)))
    local item = Player.Functions.GetItemByName('brake_pads')
    local havePads = (item and item.amount) or 0
    local toUse = math.min(padsNeeded, havePads)

    cb({ padsNeeded = padsNeeded, havePads = havePads, toUse = toUse, brakeDmg = brakeDmg })
end)

-- Apply repair: remove items and update state
RegisterNetEvent('pf-mechanicjob:server:applyBrakeRepair', function(vehNet, requestedUse)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local veh = NetworkGetEntityFromNetworkId(vehNet or -1)
    if not veh or veh == 0 then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, nil, 'Vehicle not found.')
        return
    end

    local item = Player.Functions.GetItemByName('brake_pads')
    local havePads = (item and item.amount) or 0
    local toUse = math.min(4, math.max(0, tonumber(requestedUse) or 0), havePads)
    if toUse <= 0 then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, nil, 'No brake pads.')
        return
    end

    -- Remove items
    if not Player.Functions.RemoveItem('brake_pads', toUse) then
        TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, 0, nil, 'Failed to remove brake pads.')
        return
    end
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['brake_pads'], 'remove', toUse)

    -- Update vehicle damage server-side
    local state = Entity(veh).state
    local damage = state.partDamage or {}
    local brakeDmg = tonumber(damage.brakes) or 0
    local newBrakeDmg = math.max(0, brakeDmg - (toUse * 25))
    damage.brakes = newBrakeDmg
    state:set('partDamage', damage, true)

    TriggerClientEvent('pf-mechanicjob:client:brakeRepairResult', src, toUse, newBrakeDmg, nil)
end)

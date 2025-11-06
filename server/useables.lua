local QBCore = exports['qb-core']:GetCoreObject()

-- Make brake_pads usable and trigger client logic
QBCore.Functions.CreateUseableItem('brake_pads', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('qb-core:client:use:brake_pads', source)
end)

-- Make mechanic_tools perform vehicle inspection first
QBCore.Functions.CreateUseableItem('mechanic_tools', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    print('[SERVER DEBUG] mechanic_tools used by player ' .. source) -- Debug
    
    -- Check if player is a mechanic
    if Player.PlayerData.job.name ~= 'mechanic' then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    TriggerClientEvent('pf-mechanicjob:client:inspectVehicle', source)
end)

-- Callback for consuming brake pads atomically
QBCore.Functions.CreateCallback('pf-mechanicjob:server:consumeBrakePad', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end

    local item = Player.Functions.GetItemByName('brake_pads')
    if not item or (item.amount or 0) < 1 then
        cb(false)
        return
    end

    local removed = Player.Functions.RemoveItem('brake_pads', 1)
    if removed then
        -- show UI box on client
        if QBCore.Shared and QBCore.Shared.Items and QBCore.Shared.Items['brake_pads'] then
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items['brake_pads'], 'remove', 1)
        end
        cb(true)
    else
        cb(false)
    end
end)

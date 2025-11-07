local QBCore = exports['qb-core']:GetCoreObject()

-- Helper: Check if player's job is allowed to use mechanic items
local function isAllowedJob(Player, itemName)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end
    
    -- Check if item is public (anyone can use)
    for _, publicItem in ipairs(Config.PublicItems or {}) do
        if publicItem == itemName then return true end
    end
    
    -- Check if player's job is in allowed list
    local playerJob = Player.PlayerData.job.name
    for _, allowedJob in ipairs(Config.AllowedJobs or {}) do
        if playerJob == allowedJob then return true end
    end
    
    return false
end

-- Make brake_pads usable and trigger client logic
QBCore.Functions.CreateUseableItem('brake_pads', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if not isAllowedJob(Player, 'brake_pads') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    TriggerClientEvent('qb-core:client:use:brake_pads', source)
end)

-- Make mechanic_tools usable (FIXED)
QBCore.Functions.CreateUseableItem('mechanic_tools', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    print('[SERVER DEBUG] mechanic_tools used by player ' .. source)
    
    -- Check if player is a mechanic
    if not isAllowedJob(Player, 'mechanic_tools') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    -- Trigger the inspection event from tools_menu.lua
    TriggerClientEvent('pf-mechanicjob:client:openToolsMenu', source)
end)

-- Make alternator usable
QBCore.Functions.CreateUseableItem('alternator', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if not isAllowedJob(Player, 'alternator') then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    
    TriggerClientEvent('pf-mechanicjob:client:use:alternator', source)
end)

-- Make engine_oil usable
QBCore.Functions.CreateUseableItem('engine_oil', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:use:engine_oil', source)
end)

-- Make oil_filter usable
QBCore.Functions.CreateUseableItem('oil_filter', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:use:oil_filter', source)
end)

-- diagnostics tool (same as mechanic_tools)
QBCore.Functions.CreateUseableItem('diagnosticstool', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    if Player.PlayerData.job.name ~= 'mechanic' then
        TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        return
    end
    TriggerClientEvent('pf-mechanicjob:client:openToolsMenu', source)
end)

-- repair_kit
QBCore.Functions.CreateUseableItem('repair_kit', function(source)
    TriggerClientEvent('pf-mechanicjob:client:useRepairKit', source)
end)

-- fuel_injector
QBCore.Functions.CreateUseableItem('fuel_injector', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:fuel_injector', source)
end)

-- powersteeringpump
QBCore.Functions.CreateUseableItem('powersteeringpump', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:powersteeringpump', source)
end)

-- radiator
QBCore.Functions.CreateUseableItem('radiator', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:radiator', source)
end)

-- power_steering_fluid
QBCore.Functions.CreateUseableItem('power_steering_fluid', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:power_steering_fluid', source)
end)

-- transmissionfluid
QBCore.Functions.CreateUseableItem('transmissionfluid', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:transmissionfluid', source)
end)

-- brakefluid
QBCore.Functions.CreateUseableItem('brakefluid', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:brakefluid', source)
end)

-- coolant
QBCore.Functions.CreateUseableItem('coolant', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:coolant', source)
end)

-- service_book
QBCore.Functions.CreateUseableItem('service_book', function(source)
    TriggerClientEvent('pf-mechanicjob:client:use:service_book', source)
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

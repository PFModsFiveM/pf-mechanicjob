local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================================
-- MECHANIC TOOLS (diagnostics/upgrade viewer)
-- ============================================================================
QBCore.Functions.CreateUseableItem('mechanic_tools', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:openUpgradeMenu', source)
end)

-- ============================================================================
-- PERFORMANCE UPGRADES
-- ============================================================================
-- Engine upgrades (1-5)
for i = 1, 5 do
    QBCore.Functions.CreateUseableItem('engine'..i, function(source, item)
        TriggerClientEvent('pf-mechanicjob:client:useUpgradeItem', source, {
            item = 'engine'..i,
            modType = 11,
            modIndex = i - 1,
            label = 'Engine Upgrade Level '..i
        })
    end)
end

-- Brake upgrades (1-3)
for i = 1, 3 do
    QBCore.Functions.CreateUseableItem('brakes'..i, function(source, item)
        TriggerClientEvent('pf-mechanicjob:client:useUpgradeItem', source, {
            item = 'brakes'..i,
            modType = 12,
            modIndex = i - 1,
            label = 'Brake Upgrade Level '..i
        })
    end)
end

-- Transmission upgrades (1-3)
for i = 1, 3 do
    QBCore.Functions.CreateUseableItem('transmission'..i, function(source, item)
        TriggerClientEvent('pf-mechanicjob:client:useUpgradeItem', source, {
            item = 'transmission'..i,
            modType = 13,
            modIndex = i - 1,
            label = 'Transmission Upgrade Level '..i
        })
    end)
end

-- Suspension upgrades (1-4)
for i = 1, 4 do
    QBCore.Functions.CreateUseableItem('suspension'..i, function(source, item)
        TriggerClientEvent('pf-mechanicjob:client:useUpgradeItem', source, {
            item = 'suspension'..i,
            modType = 15,
            modIndex = i - 1,
            label = 'Suspension Upgrade Level '..i
        })
    end)
end

-- Turbo
QBCore.Functions.CreateUseableItem('turbo', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useUpgradeItem', source, {
        item = 'turbo',
        modType = 18,
        modIndex = 0,
        label = 'Turbo',
        isTurbo = true
    })
end)

-- ============================================================================
-- REPAIR ITEMS (CORE COMPONENTS)
-- ============================================================================
QBCore.Functions.CreateUseableItem('alternator', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'alternator')
end)

QBCore.Functions.CreateUseableItem('sparkplugs', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'sparkplugs')
end)

QBCore.Functions.CreateUseableItem('carbattery', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'carbattery')
end)

QBCore.Functions.CreateUseableItem('engine_oil', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'oil')
end)

QBCore.Functions.CreateUseableItem('oil_filter', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'oil_filter')
end)

QBCore.Functions.CreateUseableItem('brake_pads', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'brakes')
end)

QBCore.Functions.CreateUseableItem('susp_arm', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'suspension')
end)

QBCore.Functions.CreateUseableItem('axleparts', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'axle')
end)

QBCore.Functions.CreateUseableItem('engine_part', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'engine_part')
end)

QBCore.Functions.CreateUseableItem('body_part', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'body_part')
end)

QBCore.Functions.CreateUseableItem('tire_new', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'tire_new')
end)

-- ============================================================================
-- FLUIDS
-- ============================================================================
QBCore.Functions.CreateUseableItem('fuel_injector', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'fuel_injector')
end)

QBCore.Functions.CreateUseableItem('powersteeringpump', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'powersteeringpump')
end)

QBCore.Functions.CreateUseableItem('radiator', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'radiator')
end)

QBCore.Functions.CreateUseableItem('power_steering_fluid', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'power_steering_fluid')
end)

QBCore.Functions.CreateUseableItem('transmissionfluid', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'transmissionfluid')
end)

QBCore.Functions.CreateUseableItem('brakefluid', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'brakefluid')
end)

QBCore.Functions.CreateUseableItem('coolant', function(source, item)
    TriggerClientEvent('pf-mechanicjob:client:useRepairItem', source, 'coolant')
end)

-- ============================================================================
-- DPF ITEM
-- ============================================================================
QBCore.Functions.CreateUseableItem(Config.DPFItem or 'dpf', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    
    if Config.Debug then
        print(string.format('[DPF] Player %s used DPF item', source))
    end
    
    -- Client will handle the actual installation logic
    TriggerClientEvent('pf-mechanicjob:client:useDPFItem', source)
end)

-- Make the DPF item useable to trigger install from inventory
QBCore.Functions.CreateUseableItem(Config.DPFItem or 'dpf', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:useDPFItem', source)
end)

-- ============================================================================
-- SERVER CALLBACKS
-- ============================================================================
-- Consume upgrade item after successful installation
RegisterNetEvent('pf-mechanicjob:server:consumeUpgradeItem', function(itemName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local item = Player.Functions.GetItemByName(itemName)
    if not item then return end
    
    if Player.Functions.RemoveItem(itemName, 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'remove', 1)
    end
end)

-- Consume repair item after successful repair
RegisterNetEvent('pf-mechanicjob:server:consumeRepairItem', function(itemName, amount)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    amount = tonumber(amount) or 1
    
    local item = Player.Functions.GetItemByName(itemName)
    if not item or item.amount < amount then 
        TriggerClientEvent('QBCore:Notify', src, 'Not enough items', 'error')
        return 
    end
    
    if Player.Functions.RemoveItem(itemName, amount) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'remove', amount)
    end
end)

-- Return upgrade item after downgrade
RegisterNetEvent('pf-mechanicjob:server:returnUpgradeItem', function(itemName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    if not QBCore.Shared.Items[itemName] then
        if Config.Debug then
            print(string.format('[UPGRADE] Item %s not found in QBCore.Shared.Items', itemName))
        end
        return
    end
    
    if Player.Functions.AddItem(itemName, 1) then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add', 1)
        TriggerClientEvent('QBCore:Notify', src, 'Removed upgrade part returned to inventory', 'success', 3000)
    else
        TriggerClientEvent('QBCore:Notify', src, 'Inventory full - item lost!', 'error', 5000)
    end
end)

-- Sync upgrade to all clients
RegisterNetEvent('pf-mechanicjob:server:syncUpgrade', function(data)
    TriggerClientEvent('pf-mechanicjob:client:syncUpgrade', -1, data)
end)

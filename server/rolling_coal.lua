local QBCore = exports['qb-core']:GetCoreObject()

-- In-memory DPF state: [plate] = true (removed) / false (installed)
local CoalDeleteState = {}

local function normPlate(p)
    return tostring(p or ''):gsub('%s+', ''):upper()
end

-- Callback: get DPF state for a plate
QBCore.Functions.CreateCallback('pf_mech:getCoalState', function(source, cb, plate)
    plate = normPlate(plate)
    cb(CoalDeleteState[plate] == true)
end)

-- Callback: does player have a DPF item?
QBCore.Functions.CreateCallback('pf_mech:hasDPFItem', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end
    local itemName = Config.DPFItem or 'dpf'
    local itm = Player.Functions.GetItemByName(itemName)
    cb(itm and (itm.amount or 0) > 0)
end)

-- Remove DPF: set state, sync clients, give item
RegisterNetEvent('pf_mech:dpf:remove', function(plate)
    local src = source
    plate = normPlate(plate); if plate == '' then return end
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end

    CoalDeleteState[plate] = true
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, true)

    local dpfItem = Config.DPFItem or 'dpf'
    if Player.Functions.AddItem(dpfItem, 1) and QBCore.Shared.Items[dpfItem] then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[dpfItem], 'add', 1)
    end

    TriggerClientEvent('pf_mech:dpf:result', src, 'remove', true, 'DPF removed - rolling coal enabled', plate, true)
end)

-- Install DPF: require item, consume, set state, sync clients
RegisterNetEvent('pf_mech:dpf:install', function(plate)
    local src = source
    plate = normPlate(plate); if plate == '' then return end
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end

    local dpfItem = Config.DPFItem or 'dpf'
    local itm = Player.Functions.GetItemByName(dpfItem)
    if not itm or (itm.amount or 0) < 1 then
        TriggerClientEvent('QBCore:Notify', src, 'You need a DPF filter!', 'error')
        return
    end

    if not Player.Functions.RemoveItem(dpfItem, 1) then
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume DPF item', 'error')
        return
    end
    if QBCore.Shared.Items[dpfItem] then
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[dpfItem], 'remove', 1)
    end

    CoalDeleteState[plate] = false
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, false)
    TriggerClientEvent('pf_mech:dpf:result', src, 'install', true, 'DPF installed - rolling coal disabled', plate, false)
end)

-- Particle relays (used by client rolling_coal.lua)
RegisterNetEvent('pf_mech:coal:syncStart', function(netId)
    TriggerClientEvent('pf_mech:coal:startParticles', -1, netId)
end)
RegisterNetEvent('pf_mech:coal:syncStop', function(netId)
    TriggerClientEvent('pf_mech:coal:stopParticles', -1, netId)
end)

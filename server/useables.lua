local QBCore = exports['qb-core']:GetCoreObject()

-- Make brake_pads usable and trigger client logic
QBCore.Functions.CreateUseableItem('brake_pads', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:use:brake_pads', source)
end)

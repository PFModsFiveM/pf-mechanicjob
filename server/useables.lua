local QBCore = exports['qb-core']:GetCoreObject()

-- Make brake_pads usable and trigger client logic
QBCore.Functions.CreateUseableItem('brake_pads', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('qb-core:client:use:brake_pads', source)
end)

-- Make mechanic_tools open the tools menu
QBCore.Functions.CreateUseableItem('mechanic_tools', function(source, item)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    TriggerClientEvent('pf-mechanicjob:client:openToolsMenu', source)
end)

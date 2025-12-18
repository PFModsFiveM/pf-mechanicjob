local QBCore = exports['qb-core']:GetCoreObject()

RegisterNetEvent('pf-mechanicjob:server:removeMod', function(itemName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    Player.Functions.RemoveItem(itemName, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

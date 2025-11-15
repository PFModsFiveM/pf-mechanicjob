local QBCore = exports['qb-core']:GetCoreObject()

-- Map item name to GTA mod type
local CosmeticItemToModType = {
    spoiler = 0,
    bumper = 1,
    vehicle_bumper = 1,
    skirts = 3,
    exhaust = 4,
    rollcage = 5,
    grille = 6,
    hood = 7,
    fenders = 8,
    roof = 10,
}

-- Open cosmetic mod picker
local function openCosmeticModPicker(itemName, veh)
    if not DoesEntityExist(veh) then return end
    
    local modType = CosmeticItemToModType[itemName]
    if not modType then
        QBCore.Functions.Notify('Unknown cosmetic type', 'error')
        return
    end
    
    SetVehicleModKit(veh, 0)
    local count = GetNumVehicleMods(veh, modType)
    
    if count <= 0 then
        QBCore.Functions.Notify('No modifications available for this part', 'error')
        return
    end
    
    local menu = {
        { header = ('Install %s'):format(itemName:gsub('_', ' ')), isMenuHeader = true }
    }
    
    for i = 0, count - 1 do
        menu[#menu+1] = {
            header = ('Option #%d'):format(i + 1),
            txt = 'Install this modification',
            params = {
                event = 'pf-mechanicjob:client:installCosmeticMod',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), modType = modType, modIndex = i, item = itemName }
            }
        }
    end
    
    menu[#menu+1] = { header = 'Cancel', params = { event = 'qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(menu)
end

-- Install cosmetic mod (with progress bar and server consumption)
RegisterNetEvent('pf-mechanicjob:client:installCosmeticMod', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end
    
    local ped = PlayerPedId()
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn engine off first', 'error')
        return
    end
    
    -- Check for toolbox
    QBCore.Functions.TriggerCallback('pf_mech:hasToolbox', function(has)
        if not has then
            QBCore.Functions.Notify('You need a toolbox', 'error')
            return
        end
        
        -- Progress bar
        RequestAnimDict('mini@repair')
        while not HasAnimDictLoaded('mini@repair') do Wait(0) end
        TaskPlayAnim(ped, 'mini@repair', 'fixing_a_ped', 8.0, -8.0, -1, 49, 0, false, false, false)
        
        QBCore.Functions.Progressbar('installing_cosmetic', 'Installing modification...', 5000, false, true, {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true
        }, {}, {}, {}, function() -- Success
            ClearPedTasks(ped)
            
            -- Tell server to consume item and apply mod
            TriggerServerEvent('pf_mech:server:applyMod', {
                vehicle = data.vehicle,
                item = data.item,
                modType = data.modType,
                modIndex = data.modIndex
            })
            
        end, function() -- Cancel
            ClearPedTasks(ped)
            QBCore.Functions.Notify('Installation cancelled', 'error')
        end)
    end)
end)

-- Apply upgrade when broadcast from server
RegisterNetEvent('pf_mech:client:upgradeApplied', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not DoesEntityExist(veh) then return end
    
    SetVehicleModKit(veh, 0)
    
    if data.isToggle then
        ToggleVehicleMod(veh, data.modType, true)
    else
        SetVehicleMod(veh, data.modType, data.modIndex, false)
    end
end)

-- Open cosmetic picker (called from main.lua)
RegisterNetEvent('pf-mechanicjob:client:openCosmeticPicker', function(itemName, veh)
    openCosmeticModPicker(itemName, veh)
end)

-- Apply mod from server broadcast
RegisterNetEvent('pf_mech:client:modApplied', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle or 0)
    if not DoesEntityExist(veh) then return end
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, data.modType, data.modIndex, false)
end)

local QBCore = exports['qb-core']:GetCoreObject()

-- Mapping of mod types to their index numbers
local ModTypes = {
    spoiler = 0,
    bumper_f = 1,
    bumper_r = 2,
    skirts = 3,
    exhaust = 4,
    rollcage = 5,
    grille = 6,
    hood = 7,
    roof = 10,
}

-- Get readable name for a mod at given index
local function getModName(vehicle, modType, index)
    local modCount = GetNumVehicleMods(vehicle, modType)
    if modCount == 0 then return "Not Available" end
    if index == -1 then return "Stock" end
    if index >= modCount then return "Invalid" end
    
    local modText = GetModTextLabel(vehicle, modType, index)
    if modText then
        local name = GetLabelText(modText)
        if name and name ~= "NULL" then return name end
    end
    return ("Option #%d"):format(index + 1)
end

-- Show menu of available mods for this type
local function showModMenu(vehicle, modType, itemName)
    if not DoesEntityExist(vehicle) then return end
    
    SetVehicleModKit(vehicle, 0)
    local modCount = GetNumVehicleMods(vehicle, modType)
    if modCount == 0 then
        QBCore.Functions.Notify('No mods available for this vehicle', 'error')
        return
    end

    local menu = {
        { header = "Available Mods", isMenuHeader = true },
        { header = "Stock", params = {
            event = "pf-mechanicjob:client:applyMod",
            args = { modType = modType, index = -1, itemName = itemName }
        }}
    }

    for i = 0, modCount-1 do
        menu[#menu+1] = {
            header = getModName(vehicle, modType, i),
            params = {
                event = "pf-mechanicjob:client:applyMod",
                args = { modType = modType, index = i, itemName = itemName }
            }
        }
    end

    menu[#menu+1] = { header = "Close", params = { event = "qb-menu:client:closeMenu" }}
    exports['qb-menu']:openMenu(menu)
end

-- Apply selected mod
RegisterNetEvent('pf-mechanicjob:client:applyMod', function(data)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then return end

    if not DoProgress('Installing mod...', 5000, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
        return
    end

    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, data.modType, data.index, false)
    
    -- Remove item after successful installation
    TriggerServerEvent('pf-mechanicjob:server:removeMod', data.itemName)
    
    QBCore.Functions.Notify('Modification installed', 'success')
end)

-- Handle item usage
local function useModItem(itemName, modType)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        QBCore.Functions.Notify('You must be in a vehicle', 'error')
        return
    end
    showModMenu(vehicle, modType, itemName)
end

-- Register item usages
RegisterNetEvent('pf-mechanicjob:client:useItem', function(item)
    if item == "spoiler" then useModItem(item, ModTypes.spoiler)
    elseif item == "bumper" then
        -- Special case: ask front/rear first
        exports['qb-menu']:openMenu({
            { header = "Bumper Options", isMenuHeader = true },
            { header = "Front Bumper", params = { event = "pf-mechanicjob:client:useBumper", args = { front = true }}},
            { header = "Rear Bumper", params = { event = "pf-mechanicjob:client:useBumper", args = { front = false }}},
            { header = "Close", params = { event = "qb-menu:client:closeMenu" }}
        })
    elseif item == "skirts" then useModItem(item, ModTypes.skirts)
    elseif item == "exhaust" then useModItem(item, ModTypes.exhaust)
    elseif item == "rollcage" then useModItem(item, ModTypes.rollcage)
    elseif item == "hood" then useModItem(item, ModTypes.hood)
    elseif item == "roof" then useModItem(item, ModTypes.roof)
    end
end)

RegisterNetEvent('pf-mechanicjob:client:useBumper', function(data)
    useModItem("bumper", data.front and ModTypes.bumper_f or ModTypes.bumper_r)
end)

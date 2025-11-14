local QBCore = exports['qb-core']:GetCoreObject()

-- Upgrade labels
local UpgradeLabels = {
    engine = "Engine",
    brakes = "Brakes",
    transmission = "Transmission",
    suspension = "Suspension",
    turbo = "Turbo"
}

-- Cosmetic mod labels (EXPANDED to include ALL mod types)
local CosmeticLabels = {
    [0] = "Spoilers",
    [1] = "Front Bumpers",
    [2] = "Rear Bumpers",
    [3] = "Side Skirts",
    [4] = "Exhausts",
    [5] = "Roll Cages",
    [6] = "Grilles",
    [7] = "Hoods",
    [8] = "Fenders",
    [9] = "Right Fenders",
    [10] = "Roof",
    [14] = "Horns",
    [22] = "Xenon Lights",
    [23] = "Front Wheels",
    [24] = "Back Wheels",
    [25] = "Plate Holders",
    [26] = "Trim Design",
    [27] = "Ornaments",
    [28] = "Dashboard",
    [29] = "Dial Design",
    [30] = "Door Speakers",
    [31] = "Seats",
    [32] = "Steering Wheel",
    [33] = "Shifter Leavers",
    [34] = "Plaques",
    [35] = "Speakers",
    [36] = "Trunk",
    [37] = "Hydraulics",
    [38] = "Engine Block",
    [39] = "Air Filter",
    [40] = "Struts",
    [41] = "Arch Cover",
    [42] = "Aerials",
    [43] = "Trim",
    [44] = "Tank",
    [45] = "Windows",
    [46] = "Livery",
    [48] = "Vanity Plates"
}

-- Helper: Get nearby vehicle
local function nearbyVeh(radius)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return 0
end

-- Helper: Get upgrade level name with max
local function getUpgradeLevelName(modType, current, max)
    if modType == 18 then -- Turbo
        return current >= 0 and "Installed" or "Not Installed"
    end
    
    if current == -1 then
        return string.format("Level (0/%d)", max)
    end
    
    return string.format("Level (%d/%d)", current + 1, max)
end

-- Helper: Get all vehicle upgrades
local function getVehicleUpgrades(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    SetVehicleModKit(veh, 0)
    
    local upgrades = {}
    
    -- Engine (modType 11)
    local engineMod = GetVehicleMod(veh, 11)
    local engineMax = GetNumVehicleMods(veh, 11)
    upgrades.engine = {
        current = engineMod,
        max = engineMax,
        label = UpgradeLabels.engine,
        levelName = getUpgradeLevelName(11, engineMod, engineMax)
    }
    
    -- Brakes (modType 12)
    local brakesMod = GetVehicleMod(veh, 12)
    local brakesMax = GetNumVehicleMods(veh, 12)
    upgrades.brakes = {
        current = brakesMod,
        max = brakesMax,
        label = UpgradeLabels.brakes,
        levelName = getUpgradeLevelName(12, brakesMod, brakesMax)
    }
    
    -- Transmission (modType 13)
    local transMod = GetVehicleMod(veh, 13)
    local transMax = GetNumVehicleMods(veh, 13)
    upgrades.transmission = {
        current = transMod,
        max = transMax,
        label = UpgradeLabels.transmission,
        levelName = getUpgradeLevelName(13, transMod, transMax)
    }
    
    -- Suspension (modType 15)
    local suspMod = GetVehicleMod(veh, 15)
    local suspMax = GetNumVehicleMods(veh, 15)
    upgrades.suspension = {
        current = suspMod,
        max = suspMax,
        label = UpgradeLabels.suspension,
        levelName = getUpgradeLevelName(15, suspMod, suspMax)
    }
    
    -- Turbo (modType 18)
    local turboInstalled = IsToggleModOn(veh, 18)
    upgrades.turbo = {
        current = turboInstalled and 0 or -1,
        max = 1,
        label = UpgradeLabels.turbo,
        levelName = getUpgradeLevelName(18, turboInstalled and 0 or -1, 1)
    }
    
    return upgrades
end

-- Helper: Get all cosmetic mod counts for vehicle (UPDATED to check ALL mod types)
local function getVehicleCosmetics(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    SetVehicleModKit(veh, 0)
    
    local cosmetics = {}
    
    -- Check ALL possible mod types (0-49)
    for modType = 0, 49 do
        -- Skip performance mods (already shown in upgrades)
        if modType ~= 11 and modType ~= 12 and modType ~= 13 and modType ~= 15 and modType ~= 16 and modType ~= 18 then
            local count = GetNumVehicleMods(veh, modType)
            
            -- Also check if it's a toggle mod (like xenon lights)
            local isToggleMod = (modType == 22) -- Xenon lights
            
            if count > 0 or isToggleMod then
                local label = CosmeticLabels[modType] or ("Mod Type " .. modType)
                
                cosmetics[#cosmetics + 1] = {
                    modType = modType,
                    label = label,
                    count = count,
                    isToggle = isToggleMod
                }
            end
        end
    end
    
    return cosmetics
end

-- Open cosmetics list menu
local function openCosmeticsMenu(veh)
    local cosmetics = getVehicleCosmetics(veh)
    
    if not cosmetics or #cosmetics == 0 then
        QBCore.Functions.Notify('No cosmetic options available for this vehicle', 'error')
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local displayName = GetLabelText(modelName)
    if displayName == 'NULL' then displayName = modelName end
    
    local menu = {
        {
            header = 'Available Cosmetics',
            txt = string.format('%s | Plate: %s', displayName, plate),
            isMenuHeader = true
        }
    }
    
    -- Sort cosmetics by label
    table.sort(cosmetics, function(a, b) return a.label < b.label end)
    
    for _, cosmetic in ipairs(cosmetics) do
        local optionText
        if cosmetic.isToggle then
            optionText = '[On/Off Option]'
        else
            optionText = string.format('[%d options]', cosmetic.count)
        end
        
        menu[#menu+1] = {
            header = string.format('%s - %s', cosmetic.label, optionText),
            txt = 'View only',
            params = {}
        }
    end
    
    menu[#menu+1] = {
        header = 'Back',
        params = { event = 'pf-mechanicjob:client:openUpgradeMenu' }
    }
    
    menu[#menu+1] = {
        header = 'Close',
        params = { event = 'qb-menu:client:closeMenu' }
    }
    
    exports['qb-menu']:openMenu(menu)
end

-- Open upgrade display menu
RegisterNetEvent('pf-mechanicjob:client:openUpgradeMenu', function()
    local veh = nearbyVeh(6.0)
    
    if veh == 0 then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local modelName = GetDisplayNameFromVehicleModel(GetEntityModel(veh))
    local displayName = GetLabelText(modelName)
    if displayName == 'NULL' then displayName = modelName end
    
    local upgrades = getVehicleUpgrades(veh)
    
    if not upgrades then
        QBCore.Functions.Notify('Unable to read vehicle upgrades', 'error')
        return
    end
    
    -- Build menu
    local menu = {
        {
            header = 'Vehicle Performance Upgrades',
            txt = string.format('%s | Plate: %s', displayName, plate),
            isMenuHeader = true
        }
    }
    
    -- Add upgrade entries (removed armor)
    local upgradeOrder = {'engine', 'brakes', 'transmission', 'suspension', 'turbo'}
    
    for _, key in ipairs(upgradeOrder) do
        local upgrade = upgrades[key]
        
        if upgrade and upgrade.max > 0 then
            local header = upgrade.label
            local txt = upgrade.levelName
            
            menu[#menu+1] = {
                header = header,
                txt = txt,
                params = {}
            }
        else
            -- Upgrade not available for this vehicle
            menu[#menu+1] = {
                header = upgrade.label,
                txt = 'Not available for this vehicle',
                params = {}
            }
        end
    end
    
    -- Add cosmetics button
    menu[#menu+1] = {
        header = 'List of Possible Cosmetics',
        txt = 'View all available cosmetic modifications',
        params = { event = 'pf-mechanicjob:client:openCosmeticsMenu', args = { vehicle = veh } }
    }
    
    menu[#menu+1] = {
        header = 'Close',
        params = { event = 'qb-menu:client:closeMenu' }
    }
    
    -- Open menu
    exports['qb-menu']:openMenu(menu)
end)

-- Handler for opening cosmetics menu
RegisterNetEvent('pf-mechanicjob:client:openCosmeticsMenu', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    openCosmeticsMenu(veh)
end)

-- Debug command (only if Config.Debug)
if Config.Debug then
    RegisterCommand('testupgrades', function()
        TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
    end, false)
end

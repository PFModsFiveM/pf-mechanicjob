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

-- Helper: progress bar (import from main.lua or define locally)
local function DoProgress(label, ms, dict, anim)
    ms = tonumber(ms) or 3000
    label = label or 'Working...'
    local ped = PlayerPedId()

    -- anim (optional)
    if dict and anim then
        if not HasAnimDictLoaded(dict) then
            RequestAnimDict(dict)
            while not HasAnimDictLoaded(dict) do Wait(0) end
        end
        TaskPlayAnim(ped, dict, anim, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    end

    -- Try multiple progress bar systems
    -- 1) ox_lib
    local function resourceActive(name)
        local st = GetResourceState(name)
        return st == 'started' or st == 'starting'
    end

    if resourceActive('ox_lib') and lib and lib.progressCircle then
        local ok = lib.progressCircle({
            duration = ms,
            position = 'bottom',
            label = label,
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true, mouse = false }
        })
        ClearPedTasks(ped)
        return ok and true or false
    end

    -- 2) QBCore.Functions.Progressbar
    if QBCore and QBCore.Functions and type(QBCore.Functions.Progressbar) == 'function' then
        local finished, cancelled = false, true
        QBCore.Functions.Progressbar(
            'pf_mech_prog',
            label,
            ms,
            false,
            true,
            { disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true },
            dict and { animDict = dict, anim = anim, flags = 49 } or {},
            {},
            function() cancelled=false; finished=true end,
            function() cancelled=true;  finished=true end
        )
        while not finished do Wait(25) end
        ClearPedTasksImmediately(ped)
        return not cancelled
    end

    -- 3) Fallback: simple wait
    local untilAt = GetGameTimer() + ms
    while GetGameTimer() < untilAt do
        DisableControlAction(0, 21, true)
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 22, true)
        Wait(0)
    end
    ClearPedTasks(ped)
    return true
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
            
            -- Determine if upgrade can be downgraded
            local canDowngrade = false
            if key == 'turbo' then
                -- Turbo: can remove if installed
                canDowngrade = upgrade.current >= 0
            else
                -- Other upgrades: can downgrade if above level 1 (index 0)
                canDowngrade = upgrade.current > 0
            end
            
            menu[#menu+1] = {
                header = header,
                txt = txt,
                params = canDowngrade and {
                    event = 'pf-mechanicjob:client:downgradeUpgrade',
                    args = { 
                        vehicle = veh, 
                        upgradeType = key,
                        modType = key == 'engine' and 11 or 
                                 key == 'brakes' and 12 or 
                                 key == 'transmission' and 13 or 
                                 key == 'suspension' and 15 or 
                                 key == 'turbo' and 18 or 11,
                        currentLevel = upgrade.current
                    }
                } or {}
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

-- Open cosmetics menu
RegisterNetEvent('pf-mechanicjob:client:openCosmeticsMenu', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    openCosmeticsMenu(veh)
end)

-- NEW: Handler for downgrading upgrades
RegisterNetEvent('pf-mechanicjob:client:downgradeUpgrade', function(data)
    local veh = data and data.vehicle or nearbyVeh(6.0)
    
    if veh == 0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end
    
    -- Check if player is outside vehicle
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('You must be outside the vehicle', 'error')
        return
    end
    
    -- Check if engine is off
    if GetIsVehicleEngineRunning(veh) then
        QBCore.Functions.Notify('Turn the engine off first', 'error')
        return
    end
    
    local upgradeType = data.upgradeType
    local modType = data.modType
    local currentLevel = data.currentLevel
    
    -- Determine new level and item to return
    local newLevel = -1
    local itemToReturn = nil
    
    if upgradeType == 'turbo' then
        -- Turbo: remove and return turbo item
        newLevel = -1
        itemToReturn = 'turbo'
    else
        -- Other upgrades: downgrade by 1 level, minimum is 0 (level 1)
        newLevel = math.max(0, currentLevel - 1)
        
        -- Determine item name for current level
        -- Example: engine at level 3 (index 2) returns engine3
        if upgradeType == 'engine' then
            itemToReturn = 'engine' .. (currentLevel + 1)
        elseif upgradeType == 'brakes' then
            itemToReturn = 'brakes' .. (currentLevel + 1)
        elseif upgradeType == 'transmission' then
            itemToReturn = 'transmission' .. (currentLevel + 1)
        elseif upgradeType == 'suspension' then
            itemToReturn = 'suspension' .. (currentLevel + 1)
        end
    end
    
    -- FIXED: Use proper repair animation
    local animDict = 'mini@repair'
    local animName = 'fixing_a_ped'
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do Wait(0) end
    
    TaskPlayAnim(ped, animDict, animName, 8.0, -8.0, -1, 49, 0.0, false, false, false)
    
    -- Show progress bar
    local progressTime = 6000 -- 6 seconds
    local progressLabel = string.format('Removing %s upgrade...', upgradeType)
    
    if not DoProgress(progressLabel, progressTime, animDict, animName) then
        ClearPedTasks(ped)
        QBCore.Functions.Notify('Downgrade cancelled', 'error')
        return
    end
    
    ClearPedTasks(ped)
    
    -- Apply the downgrade
    SetVehicleModKit(veh, 0)
    
    if upgradeType == 'turbo' then
        ToggleVehicleMod(veh, 18, false)
        QBCore.Functions.Notify('Turbo removed', 'success', 3000)
    else
        SetVehicleMod(veh, modType, newLevel, false)
        QBCore.Functions.Notify(string.format('%s downgraded to Level %d', upgradeType:gsub("^%l", string.upper), newLevel + 1), 'success', 3000)
    end
    
    -- Return item to inventory
    if itemToReturn then
        TriggerServerEvent('pf-mechanicjob:server:returnUpgradeItem', itemToReturn)
    end
    
    -- Sync to all clients
    TriggerServerEvent('pf-mechanicjob:server:syncUpgrade', {
        vehicle = NetworkGetNetworkIdFromEntity(veh),
        modType = modType,
        modIndex = newLevel,
        isTurbo = upgradeType == 'turbo'
    })
    
    -- Reopen menu to show updated state
    Wait(200)
    TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
end)

-- Debug command (only if Config.Debug)
if Config.Debug then
    RegisterCommand('testupgrades', function()
        TriggerEvent('pf-mechanicjob:client:openUpgradeMenu')
    end, false)
end

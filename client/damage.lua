-- Vehicle Component Damage System with Environmental Effects and Realistic Failures
local QBCore = exports['qb-core']:GetCoreObject()

-- Configuration
local DamageConfig = {
    enabled = true,
    checkInterval = 15000, -- Check every 15 seconds
    
    -- Base damage rates (% per check interval)
    damageRates = {
        sparkplugs = 0.08,
        carbattery = 0.04,
        oil = 0.06,
        oil_filter = 0.05,
        suspension = 0.04,
        axle = 0.03
    },
    
    -- Starting thresholds
    starting = {
        battery_hard_start = 50,    -- Below 50% = hard start
        battery_may_fail = 30,      -- Below 30% = may not start
        battery_power_cut = 30,     -- Below 30% = random power cuts
        sparkplug_misfire = 40,     -- Below 40% = misfires
        attempts_max = 5            -- Max starting attempts before fail
    },
    
    -- Environmental damage multipliers
    environmental = {
        mud_multiplier = 3.0,
        water_depth_critical = 0.5,
        offroad_protection = 0.3,
        no_snorkel_penalty = 2.0
    },
    
    -- Thresholds
    warningThreshold = 30,
    criticalThreshold = 10
}

-- Track vehicle states
local vehicleStates = {}
local lastWarnings = {}
local lastEnvironmentalWarning = 0

-- Offroad vehicle classes (get less environmental damage)
local OffroadVehicleClasses = {
    [8] = true,   -- Motorcycles (some)
    [9] = true,   -- Off-road
    [11] = true,  -- Utility
    [18] = true   -- Emergency (some have snorkels)
}

-- Vehicles with snorkels (custom list - expand as needed)
local VehiclesWithSnorkel = {
    [`bifta`] = true,
    [`bfinjection`] = true,
    [`dubsta3`] = true,
    [`kalahari`] = true,
    [`mesa3`] = true,
    [`rebel`] = true,
    [`rebel2`] = true,
    [`sandking`] = true,
    [`sandking2`] = true,
    [`dloader`] = true,
    [`blazer`] = true,
    [`insurgent`] = true,
    [`insurgent2`] = true,
    [`technical`] = true,
    [`guardian`] = true,
    [`dubsta`] = true,
    [`dubsta2`] = true
}

-- Helper: Check if vehicle has snorkel
local function hasSnorkel(veh)
    local model = GetEntityModel(veh)
    return VehiclesWithSnorkel[model] or false
end

-- Helper: Check if vehicle is offroad type
local function isOffroadVehicle(veh)
    local class = GetVehicleClass(veh)
    return OffroadVehicleClasses[class] or false
end

-- Helper: Get water/mud depth at vehicle position
local function getWaterDepth(veh)
    if not veh or not DoesEntityExist(veh) then return 0 end
    
    local coords = GetEntityCoords(veh)
    local waterHeight = GetWaterHeight(coords.x, coords.y, coords.z)
    
    if waterHeight and waterHeight > 0 then
        local vehicleHeight = coords.z
        local depth = waterHeight - vehicleHeight
        return math.max(0, depth)
    end
    
    return 0
end

-- Helper: Check if vehicle is in mud/dirt (heuristic)
local function isInMud(veh)
    if not veh or not DoesEntityExist(veh) then return false end
    
    local coords = GetEntityCoords(veh)
    local rayHandle = StartShapeTestRay(coords.x, coords.y, coords.z + 2.0, coords.x, coords.y, coords.z - 2.0, 1, veh, 0)
    local _, hit, _, _, materialHash = GetShapeTestResult(rayHandle)
    
    if hit then
        -- Common mud/dirt material hashes (approximations)
        local mudMaterials = {
            [-1286696947] = true, -- dirt
            [1109728704] = true,  -- mud
            [2128369009] = true,  -- grass_dirt
            [-1885547121] = true, -- sand
        }
        
        return mudMaterials[materialHash] or false
    end
    
    return false
end

-- Helper: Get or initialize vehicle damage state
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    local state = Entity(veh)
    if not state or not state.state then return nil end
    
    local damage = state.state.partDamage or {}
    
    damage.sparkplugs = damage.sparkplugs or 0
    damage.carbattery = damage.carbattery or 0
    damage.oil = damage.oil or 0
    damage.oil_filter = damage.oil_filter or 0
    damage.suspension = damage.suspension or 0
    damage.axle = damage.axle or 0
    
    return damage
end

-- Helper: Apply damage to vehicle state
local function applyDamage(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then return end
    
    local state = Entity(veh)
    if not state or not state.state then return end
    
    state.state:set('partDamage', damage, true)
end

-- NEW: Handle vehicle starting with battery/sparkplug failures
local function attemptVehicleStart(veh, damage)
    local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
    local sparkplugHealth = 100 - (tonumber(damage.sparkplugs) or 0)
    
    -- Dead battery = no start
    if batteryHealth <= 0 then
        QBCore.Functions.Notify('🔋 Battery is completely dead!', 'error', 3000)
        SetVehicleEngineOn(veh, false, true, true)
        return false
    end
    
    -- Dead sparkplugs = no start
    if sparkplugHealth <= 0 then
        QBCore.Functions.Notify('⚡ Spark plugs failed - engine won\'t start!', 'error', 3000)
        SetVehicleEngineOn(veh, false, true, true)
        return false
    end
    
    -- Calculate start chance based on battery & sparkplugs
    local startChance = 100
    
    -- Battery affects starting
    if batteryHealth < DamageConfig.starting.battery_hard_start then
        if batteryHealth < DamageConfig.starting.battery_may_fail then
            -- Below 30% = 30-70% chance to start
            startChance = math.max(20, batteryHealth * 2)
        else
            -- 30-50% = harder starting but will eventually work
            startChance = 70 + (batteryHealth - 30) * 1.5
        end
    end
    
    -- Sparkplugs affect starting
    if sparkplugHealth < DamageConfig.starting.sparkplug_misfire then
        startChance = startChance * (sparkplugHealth / 100)
    end
    
    local roll = math.random(1, 100)
    local started = roll <= startChance
    
    if not started then
        -- Failed start damages battery slightly
        damage.carbattery = math.min(100, (damage.carbattery or 0) + 1)
        applyDamage(veh, damage)
        
        if batteryHealth < 30 then
            QBCore.Functions.Notify('🔋 Battery struggling... Try again', 'error', 2000)
        else
            QBCore.Functions.Notify('⚡ Engine misfired', 'error', 2000)
        end
    else
        if batteryHealth < 50 then
            QBCore.Functions.Notify('🔋 Engine started (battery weak)', 'warning', 2000)
        end
    end
    
    return started
end

-- NEW: Monitor power cuts while driving
CreateThread(function()
    while true do
        Wait(5000) -- Check every 5 seconds
        
        if not DamageConfig.enabled then goto skip end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto skip end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto skip end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto skip end
        
        if not GetIsVehicleEngineRunning(veh) then goto skip end
        
        local damage = getVehicleDamage(veh)
        if not damage then goto skip end
        
        local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
        
        -- Power cuts when battery below 30%
        if batteryHealth < DamageConfig.starting.battery_power_cut then
            local cutChance = (30 - batteryHealth) * 2 -- 0-60% chance
            
            if math.random(100) < cutChance then
                -- Power cut!
                SetVehicleEngineOn(veh, false, true, false)
                
                -- Damage battery from power cut
                damage.carbattery = math.min(100, (damage.carbattery or 0) + 2)
                applyDamage(veh, damage)
                
                QBCore.Functions.Notify('⚠️ Power cut! Battery failing!', 'error', 3000)
                
                -- Wait random time before can restart
                Wait(math.random(2000, 5000))
                
                -- More power cuts = more battery damage
                if batteryHealth < 15 then
                    damage.carbattery = math.min(100, (damage.carbattery or 0) + 3)
                    applyDamage(veh, damage)
                end
            end
        end
        
        ::skip::
    end
end)

-- NEW: Intercept engine starting
CreateThread(function()
    while true do
        Wait(0)
        
        if not DamageConfig.enabled then goto continue end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto continue end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto continue end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto continue end
        
        -- Detect when player tries to start engine
        if IsControlJustPressed(0, 74) then -- INPUT_VEH_EXIT (H key, also engine on/off)
            local damage = getVehicleDamage(veh)
            if not damage then goto continue end
            
            if not GetIsVehicleEngineRunning(veh) then
                -- Trying to start engine
                local plate = GetVehicleNumberPlateText(veh)
                vehicleStates[plate] = vehicleStates[plate] or { startAttempts = 0 }
                vehicleStates[plate].startAttempts = vehicleStates[plate].startAttempts + 1
                
                if not attemptVehicleStart(veh, damage) then
                    -- Failed to start - prevent default start
                    SetVehicleEngineOn(veh, false, true, true)
                    
                    if vehicleStates[plate].startAttempts >= DamageConfig.starting.attempts_max then
                        QBCore.Functions.Notify('🔋 Battery drained from failed starts!', 'error', 4000)
                        damage.carbattery = math.min(100, (damage.carbattery or 0) + 5)
                        applyDamage(veh, damage)
                        vehicleStates[plate].startAttempts = 0
                    end
                else
                    vehicleStates[plate].startAttempts = 0
                end
            end
        end
        
        ::continue::
    end
end)

-- Helper: Calculate environmental damage multiplier
local function calculateEnvironmentalMultiplier(veh)
    if not veh or not DoesEntityExist(veh) then return 1.0 end
    
    local multiplier = 1.0
    local speed = GetEntitySpeed(veh) * 2.236936 -- MPH
    
    -- Check water depth
    local waterDepth = getWaterDepth(veh)
    local inMud = isInMud(veh)
    
    if waterDepth > 0.1 or inMud then
        local isOffroad = isOffroadVehicle(veh)
        local hasSnork = hasSnorkel(veh)
        
        -- Base environmental damage
        multiplier = DamageConfig.environmental.mud_multiplier
        
        -- Offroad vehicles handle it better
        if isOffroad then
            multiplier = multiplier * DamageConfig.environmental.offroad_protection
        end
        
        -- Deep water without snorkel = disaster
        if waterDepth > DamageConfig.environmental.water_depth_critical and not hasSnork then
            multiplier = multiplier * DamageConfig.environmental.no_snorkel_penalty
            
            -- Chance of immediate stall
            if math.random(100) < 15 then
                SetVehicleEngineOn(veh, false, true, true)
                SetVehicleUndriveable(veh, true)
                Wait(3000)
                SetVehicleUndriveable(veh, false)
            end
        end
        
        -- Moving fast through water/mud = worse
        if speed > 30 then
            multiplier = multiplier * 1.5
        end
    end
    
    return multiplier
end

-- Helper: Calculate driving condition damage multiplier
local function calculateDrivingMultiplier(veh, partKey)
    if not veh or not DoesEntityExist(veh) then return 1.0 end
    
    local speed = GetEntitySpeed(veh) * 2.236936
    local rpm = GetVehicleCurrentRpm(veh)
    local multiplier = 1.0
    
    if partKey == 'sparkplugs' then
        if speed > 100 then
            multiplier = 2.0
        elseif rpm > 0.9 then
            multiplier = 1.5
        end
        
    elseif partKey == 'carbattery' then
        if GetIsVehicleEngineRunning(veh) then
            multiplier = 1.0
        else
            multiplier = 1.5
        end
        
    elseif partKey == 'oil' or partKey == 'oil_filter' then
        if speed > 80 then
            multiplier = 1.8
        end
        
    elseif partKey == 'suspension' then
        if not IsVehicleOnAllWheels(veh) then
            multiplier = 3.0
        elseif speed > 60 then
            multiplier = 1.5
        end
        
    elseif partKey == 'axle' then
        if HasEntityCollidedWithAnything(veh) then
            multiplier = 5.0
        elseif speed > 70 then
            multiplier = 1.3
        end
    end
    
    return multiplier
end

-- NEW: Enhanced damage effects with oil-related engine damage
local function applyDamageEffects(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then return end
    
    -- Spark plugs: Reduce power & chance of misfires
    local sparkplugDmg = tonumber(damage.sparkplugs) or 0
    if sparkplugDmg > 50 then
        local penalty = (sparkplugDmg - 50) / 50
        SetVehicleEnginePowerMultiplier(veh, math.max(0.4, 1.0 - (penalty * 0.4)))
        
        -- Random misfires
        if sparkplugDmg > 70 and math.random(100) < 5 then
            SetVehicleEngineOn(veh, false, false, false)
            Wait(500)
            SetVehicleEngineOn(veh, true, false, false)
        end
    end
    
    -- Battery: Power cuts and stalling
    local batteryDmg = tonumber(damage.carbattery) or 0
    if batteryDmg > 80 and math.random(100) < 3 then
        SetVehicleEngineOn(veh, false, true, true)
    end
    
    -- Oil: Direct engine damage when low
    local oilDmg = tonumber(damage.oil) or 0
    local oilHealth = 100 - oilDmg
    
    if oilHealth < 50 then
        local engineHealth = GetVehicleEngineHealth(veh)
        if engineHealth > 100 then
            -- Oil below 50% = progressive engine damage
            local damageRate = (50 - oilHealth) / 10 -- 0-5 damage per tick
            SetVehicleEngineHealth(veh, engineHealth - damageRate)
        end
    end
    
    if oilHealth < 20 then
        -- Critical oil = severe engine damage
        local engineHealth = GetVehicleEngineHealth(veh)
        if engineHealth > 100 then
            SetVehicleEngineHealth(veh, engineHealth - 10)
        end
        
        -- Smoke from engine
        if math.random(100) < 10 then
            QBCore.Functions.Notify('💨 Engine smoking - critical oil level!', 'error', 4000)
        end
    end
    
    -- Oil filter: Degrades with dirty oil
    if oilDmg > 50 then
        damage.oil_filter = math.min(100, (damage.oil_filter or 0) + 0.3)
    end
    
    -- Dirty oil filter makes oil degrade faster (feedback loop)
    local filterDmg = tonumber(damage.oil_filter) or 0
    if filterDmg > 60 then
        damage.oil = math.min(100, (damage.oil or 0) + 0.2)
    end
end

-- Helper: Show environmental warnings
local function checkEnvironmentalWarnings(veh, envMultiplier)
    if not veh or not DoesEntityExist(veh) then return end
    
    local now = GetGameTimer()
    if (now - lastEnvironmentalWarning) < 30000 then return end -- Once per 30s
    
    local waterDepth = getWaterDepth(veh)
    local inMud = isInMud(veh)
    local hasSnork = hasSnorkel(veh)
    local isOffroad = isOffroadVehicle(veh)
    
    if waterDepth > DamageConfig.environmental.water_depth_critical and not hasSnork then
        QBCore.Functions.Notify('⚠️ Deep water! Engine at risk without snorkel!', 'error', 5000)
        lastEnvironmentalWarning = now
    elseif (waterDepth > 0.2 or inMud) and not isOffroad and not hasSnork then
        QBCore.Functions.Notify('⚠️ Mud/water causing accelerated wear!', 'warning', 5000)
        lastEnvironmentalWarning = now
    end
end

-- Helper: Show component warnings
local function checkComponentWarnings(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then return end
    
    local plate = GetVehicleNumberPlateText(veh) or 'UNKNOWN'
    local now = GetGameTimer()
    
    lastWarnings[plate] = lastWarnings[plate] or {}
    
    local partNames = {
        sparkplugs = 'Spark Plugs',
        carbattery = 'Battery',
        oil = 'Engine Oil',
        oil_filter = 'Oil Filter',
        suspension = 'Suspension',
        axle = 'Axle'
    }
    
    for part, dmg in pairs(damage) do
        dmg = tonumber(dmg) or 0
        
        if dmg >= 70 and dmg < 100 then
            if not lastWarnings[plate][part] or (now - lastWarnings[plate][part]) > 120000 then
                local name = partNames[part] or part
                QBCore.Functions.Notify(string.format('🔧 %s critically low!', name), 'error', 5000)
                lastWarnings[plate][part] = now
            end
        end
    end
end

-- Main damage loop
CreateThread(function()
    while true do
        Wait(DamageConfig.checkInterval)
        
        if not DamageConfig.enabled then goto continue end
        
        local ped = PlayerPedId()
        if not ped or not DoesEntityExist(ped) then goto continue end
        if not IsPedInAnyVehicle(ped, false) then goto continue end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 or not DoesEntityExist(veh) then goto continue end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto continue end
        
        -- Get current damage
        local damage = getVehicleDamage(veh)
        if not damage then goto continue end
        
        -- Calculate environmental multiplier
        local envMultiplier = calculateEnvironmentalMultiplier(veh)
        
        -- Apply environmental-specific damage
        local waterDepth = getWaterDepth(veh)
        local inMud = isInMud(veh)
        
        if waterDepth > 0.1 or inMud then
            -- Oil gets dirty faster in water/mud
            damage.oil = math.min(100, (tonumber(damage.oil) or 0) + (0.3 * envMultiplier))
            damage.oil_filter = math.min(100, (tonumber(damage.oil_filter) or 0) + (0.25 * envMultiplier))
            
            -- Battery shorts in water
            if waterDepth > 0.3 then
                damage.carbattery = math.min(100, (tonumber(damage.carbattery) or 0) + (0.4 * envMultiplier))
            end
            
            -- Suspension/axle damage from rough terrain
            if inMud then
                damage.suspension = math.min(100, (tonumber(damage.suspension) or 0) + (0.2 * envMultiplier))
                damage.axle = math.min(100, (tonumber(damage.axle) or 0) + (0.15 * envMultiplier))
            end
        end
        
        -- Calculate and apply normal driving damage
        for part, baseRate in pairs(DamageConfig.damageRates) do
            local drivingMult = calculateDrivingMultiplier(veh, part)
            local totalMult = drivingMult * envMultiplier
            local newDamage = baseRate * totalMult
            
            damage[part] = math.min(100, (tonumber(damage[part]) or 0) + newDamage)
        end
        
        -- Apply changes
        applyDamage(veh, damage)
        applyDamageEffects(veh, damage)
        checkEnvironmentalWarnings(veh, envMultiplier)
        checkComponentWarnings(veh, damage)
        
        ::continue::
    end
end)

-- Commands
RegisterCommand('toggledamage', function()
    DamageConfig.enabled = not DamageConfig.enabled
    QBCore.Functions.Notify('Damage system: ' .. (DamageConfig.enabled and 'Enabled' or 'Disabled'), 'info')
end, false)

RegisterCommand('resetdamage', function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then 
        QBCore.Functions.Notify('Not in a vehicle', 'error')
        return 
    end
    
    local veh = GetVehiclePedIsIn(ped, false)
    local damage = {
        sparkplugs = 0,
        carbattery = 0,
        oil = 0,
        oil_filter = 0,
        suspension = 0,
        axle = 0
    }
    
    applyDamage(veh, damage)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehicleFixed(veh)
    QBCore.Functions.Notify('All damage reset', 'success')
end, false)

-- Debug command to check environmental conditions
RegisterCommand('checkenv', function()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return end
    
    local veh = GetVehiclePedIsIn(ped, false)
    local waterDepth = getWaterDepth(veh)
    local inMud = isInMud(veh)
    local damage = getVehicleDamage(veh) or {}
    local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
    local oilHealth = 100 - (tonumber(damage.oil) or 0)
    QBCore.Functions.Notify(string.format('Battery: %d%% | Oil: %d%% | Water: %.2fm', batteryHealth, oilHealth, waterDepth), 'info', 5000)
end, false)

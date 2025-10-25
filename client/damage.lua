-- Vehicle Component Damage System with Environmental Effects and Realistic Failures
local QBCore = exports['qb-core']:GetCoreObject()

-- Configuration
local DamageConfig = {
    enabled = true,
    checkInterval = 15000, -- Check every 15 seconds
    
    -- Base damage rates (% per check interval)
    damageRates = {
        alternator = 0.03,
        sparkplugs = 0.08,
        carbattery = 0.04,
        oil = 0.06,
        oil_filter = 0.05,
        brakes = 0.05,         -- NEW: Brakes
        suspension = 0.04,
        axle = 0.03
    },
    
    -- Starting thresholds
    starting = {
        battery_hard_start = 50,
        battery_may_fail = 30,
        battery_power_cut = 30,
        sparkplug_misfire = 40,
        alternator_stutter = 60,
        attempts_max = 5
    },
    
    -- Brake degradation
    brakes = {
        fade_threshold = 60,     -- Below 60% = reduced braking
        critical_threshold = 30, -- Below 30% = severe brake fade
        max_power_loss = 0.6     -- Up to 60% brake power loss
    },
    
    -- Alternator stuttering
    alternator = {
        stutter_interval = 300000,  -- 5 minutes between stutters
        damage_per_stutter = 10,    -- 10% damage per stutter event
        base_stutter_duration = 2000, -- 2 seconds at 60%
        max_stutter_duration = 15000  -- 15 seconds at 0%
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
local batteryDeadNotified = {}
local lastAlternatorStutter = {}
local lastBrakeWarning = {} -- NEW: Track brake warnings

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
    
    damage.alternator = damage.alternator or 0
    damage.sparkplugs = damage.sparkplugs or 0
    damage.carbattery = damage.carbattery or 0
    damage.oil = damage.oil or 0
    damage.oil_filter = damage.oil_filter or 0
    damage.brakes = damage.brakes or 0  -- NEW
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

-- NEW: Handle vehicle starting with battery/sparkplug/alternator failures
local function attemptVehicleStart(veh, damage)
    local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
    local sparkplugHealth = 100 - (tonumber(damage.sparkplugs) or 0)
    local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
    
    print('[DAMAGE DEBUG] Attempting start - Battery:', batteryHealth, '% Sparkplugs:', sparkplugHealth, '% Alternator:', alternatorHealth, '%')
    
    local plate = GetVehicleNumberPlateText(veh) or 'UNKNOWN'
    
    -- Dead battery = no start (only notify once)
    if batteryHealth <= 0 then
        if not batteryDeadNotified[plate] then
            QBCore.Functions.Notify('🔋 Battery is completely dead! Needs replacement.', 'error', 5000)
            batteryDeadNotified[plate] = true
        end
        SetVehicleEngineOn(veh, false, true, true)
        return false
    else
        batteryDeadNotified[plate] = nil -- Reset notification flag when battery is alive
    end
    
    -- Dead sparkplugs = no start
    if sparkplugHealth <= 0 then
        QBCore.Functions.Notify('⚡ Spark plugs failed - engine won\'t start!', 'error', 3000)
        SetVehicleEngineOn(veh, false, true, true)
        return false
    end
    
    -- Calculate start chance based on battery, sparkplugs & alternator
    local startChance = 100
    
    -- Battery affects starting
    if batteryHealth < DamageConfig.starting.battery_hard_start then
        if batteryHealth < DamageConfig.starting.battery_may_fail then
            startChance = math.max(20, batteryHealth * 2)
        else
            startChance = 70 + (batteryHealth - 30) * 1.5
        end
    end
    
    -- Sparkplugs affect starting
    if sparkplugHealth < DamageConfig.starting.sparkplug_misfire then
        startChance = startChance * (sparkplugHealth / 100)
    end
    
    -- Bad alternator makes starting harder (drains battery faster)
    if alternatorHealth < 50 then
        startChance = startChance * (alternatorHealth / 100)
    end
    
    print('[DAMAGE DEBUG] Start chance:', startChance, '%')
    
    local roll = math.random(1, 100)
    local started = roll <= startChance
    
    if not started then
        damage.carbattery = math.min(100, (damage.carbattery or 0) + 1)
        applyDamage(veh, damage)
        
        if batteryHealth < 30 then
            QBCore.Functions.Notify('🔋 Battery struggling... Try again', 'error', 2000)
        else
            QBCore.Functions.Notify('⚡ Engine misfired', 'error', 2000)
        end
        print('[DAMAGE DEBUG] Start FAILED (rolled', roll, 'needed <=', startChance, ')')
    else
        if batteryHealth < 50 then
            QBCore.Functions.Notify('🔋 Engine started (battery weak)', 'warning', 2000)
        end
        if alternatorHealth < 40 then
            QBCore.Functions.Notify('⚡ Charging system fault detected', 'warning', 3000)
        end
        print('[DAMAGE DEBUG] Start SUCCESS')
    end
    
    return started
end

-- Helper: Calculate environmental damage multiplier (MOVE THIS UP)
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

-- REPLACE: Alternator stuttering system with dynamic intervals
CreateThread(function()
    while true do
        Wait(1000) -- Check every second
        
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
        
        local plate = GetVehicleNumberPlateText(veh)
        local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
        
        -- Check if alternator should stutter
        if alternatorHealth < DamageConfig.starting.alternator_stutter then
            local now = GetGameTimer()
            lastAlternatorStutter[plate] = lastAlternatorStutter[plate] or 0
            
            -- Calculate dynamic stutter interval based on health
            -- 60% = 5 minutes, 30% = 2.5 minutes, 0% = 30 seconds
            local healthRatio = alternatorHealth / 60 -- 0-1 scale (60% to 0%)
            local minInterval = 30000 -- 30 seconds minimum
            local maxInterval = 300000 -- 5 minutes maximum
            local dynamicInterval = minInterval + (healthRatio * (maxInterval - minInterval))
            
            print(string.format('[DAMAGE DEBUG] Alternator health: %d%% | Next stutter in: %.1f seconds', 
                alternatorHealth, 
                (dynamicInterval - (now - lastAlternatorStutter[plate])) / 1000
            ))
            
            -- Time for next stutter?
            if (now - lastAlternatorStutter[plate]) >= dynamicInterval then
                print('[DAMAGE DEBUG] Alternator stutter starting!')
                
                -- Calculate stutter duration based on damage
                local stutterPercent = (60 - alternatorHealth) / 60 -- 0-1 scale
                local stutterDuration = DamageConfig.alternator.base_stutter_duration + 
                    (stutterPercent * (DamageConfig.alternator.max_stutter_duration - DamageConfig.alternator.base_stutter_duration))
                
                QBCore.Functions.Notify('⚡ Alternator failing! Electrical issues!', 'error', 4000)
                
                -- Stutter effect: rapid on/off
                local stutterEnd = now + stutterDuration
                CreateThread(function()
                    while GetGameTimer() < stutterEnd do
                        if not DoesEntityExist(veh) then break end
                        
                        -- Turn off
                        SetVehicleEngineOn(veh, false, false, false)
                        SetVehicleLights(veh, 1) -- Force lights off
                        Wait(math.random(200, 500))
                        
                        -- Turn on
                        SetVehicleEngineOn(veh, true, false, false)
                        SetVehicleLights(veh, 0) -- Normal lights
                        Wait(math.random(300, 700))
                    end
                    
                    -- Ensure engine is on after stutter
                    if DoesEntityExist(veh) then
                        SetVehicleEngineOn(veh, true, false, false)
                    end
                end)
                
                -- Damage alternator further from stuttering
                damage.alternator = math.min(100, (damage.alternator or 0) + DamageConfig.alternator.damage_per_stutter)
                
                -- Stuttering also drains battery
                damage.carbattery = math.min(100, (damage.carbattery or 0) + 2)
                
                applyDamage(veh, damage)
                
                lastAlternatorStutter[plate] = now
                
                print(string.format('[DAMAGE DEBUG] Alternator stuttered for %dms. Health now: %d%%. Next stutter in: %.1f seconds', 
                    math.floor(stutterDuration), 
                    100 - damage.alternator,
                    dynamicInterval / 1000
                ))
            end
        end
        
        ::skip::
    end
end)

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

-- REPLACE: Intercept engine starting (better detection)
local lastEngineState = {}

CreateThread(function()
    while true do
        Wait(100) -- Check every 100ms
        
        if not DamageConfig.enabled then goto continue end
        
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then 
            lastEngineState = {}
            goto continue 
        end
        
        local veh = GetVehiclePedIsIn(ped, false)
        if not veh or veh == 0 then goto continue end
        
        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto continue end
        
        local plate = GetVehicleNumberPlateText(veh)
        local isEngineOn = GetIsVehicleEngineRunning(veh)
        local wasEngineOn = lastEngineState[plate]
        
        -- Detect engine start attempt (engine went from off to on)
        if isEngineOn and not wasEngineOn then
            print('[DAMAGE DEBUG] Engine start detected!') -- Debug
            
            local damage = getVehicleDamage(veh)
            if damage then
                vehicleStates[plate] = vehicleStates[plate] or { startAttempts = 0 }
                
                -- Check if start should succeed
                if not attemptVehicleStart(veh, damage) then
                    print('[DAMAGE DEBUG] Forcing engine off') -- Debug
                    -- Failed to start - force engine off
                    SetVehicleEngineOn(veh, false, true, true)
                    
                    vehicleStates[plate].startAttempts = vehicleStates[plate].startAttempts + 1
                    
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
        
        lastEngineState[plate] = isEngineOn
        
        ::continue::
    end
end)

-- Helper: Calculate driving condition damage multiplier
local function calculateDrivingMultiplier(veh, partKey)
    if not veh or not DoesEntityExist(veh) then return 1.0 end
    
    local speed = GetEntitySpeed(veh) * 2.236936
    local rpm = GetVehicleCurrentRpm(veh)
    local multiplier = 1.0
    
    if partKey == 'alternator' then
        if speed > 80 or rpm > 0.85 then
            multiplier = 1.5
        end
        
    elseif partKey == 'sparkplugs' then
        if speed > 100 then multiplier = 2.0
        elseif rpm > 0.9 then multiplier = 1.5 end
        
    elseif partKey == 'carbattery' then
        local damage = getVehicleDamage(veh)
        if damage then
            local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
            if alternatorHealth < 50 then
                multiplier = 2.0
            end
        end
        if GetIsVehicleEngineRunning(veh) then
            multiplier = multiplier * 1.0
        else
            multiplier = multiplier * 1.5
        end
        
    elseif partKey == 'brakes' then
        -- NEW: Brake wear based on usage
        local isBraking = IsControlPressed(0, 72) -- Brake key
        
        if isBraking then
            -- Heavy braking at high speed = more wear
            if speed > 60 then
                multiplier = 3.0
            elseif speed > 30 then
                multiplier = 2.0
            else
                multiplier = 1.5
            end
            
            -- Hard braking (full pressure) = extra wear
            local brakeValue = GetControlValue(0, 72)
            if brakeValue > 200 then
                multiplier = multiplier * 1.5
            end
        else
            multiplier = 0.1 -- Minimal wear when not braking
        end
        
    elseif partKey == 'oil' or partKey == 'oil_filter' then
        if speed > 80 then multiplier = 1.8 end
        
    elseif partKey == 'suspension' then
        if not IsVehicleOnAllWheels(veh) then multiplier = 3.0
        elseif speed > 60 then multiplier = 1.5 end
        
    elseif partKey == 'axle' then
        if HasEntityCollidedWithAnything(veh) then multiplier = 5.0
        elseif speed > 70 then multiplier = 1.3 end
    end
    
    return multiplier
end

-- REPLACE the brake force thread completely
CreateThread(function()
    while true do
        Wait(0)

        if not DamageConfig.enabled then goto next end

        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then goto next end

        local veh = GetVehiclePedIsIn(ped, false)
        if veh == 0 or not DoesEntityExist(veh) then goto next end

        local driver = GetPedInVehicleSeat(veh, -1)
        if driver ~= ped then goto next end

        local dmg = getVehicleDamage(veh)
        if not dmg then goto next end

        local brakeHealth = math.max(0, math.min(100, 100 - (tonumber(dmg.brakes) or 0)))

        -- Disable S key (brake/reverse) when brakes are at 0%
        if brakeHealth <= 0 then
            DisableControlAction(0, 72, true) -- INPUT_VEH_BRAKE
        end

        -- Apply brake force reduction based on health (linear 1:1 mapping)
        -- 100% health = 100% brake force
        -- 90% health = 90% brake force
        -- 0% health = 0% brake force
        local brakeMultiplier = brakeHealth / 100.0
        
        -- Get base brake force and apply multiplier
        local baseBrakeForce = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce')
        if baseBrakeForce and baseBrakeForce > 0 then
            local modifiedBrakeForce = baseBrakeForce * brakeMultiplier
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', modifiedBrakeForce)
        end

        ::next::
    end
end)

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
    
    -- Note: Brakes are handled in dedicated thread
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
        alternator = 'Alternator',
        sparkplugs = 'Spark Plugs',
        carbattery = 'Battery',
        oil = 'Engine Oil',
        oil_filter = 'Oil Filter',
        brakes = 'Brake Pads',  -- NEW
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
        
        -- Debug output (FIX: ensure all values are numbers)
        local alternatorHealth = math.floor(100 - (tonumber(damage.alternator) or 0))
        local batteryHealth = math.floor(100 - (tonumber(damage.carbattery) or 0))
        local brakeHealth = math.floor(100 - (tonumber(damage.brakes) or 0))
        local oilHealth = math.floor(100 - (tonumber(damage.oil) or 0))
        local plugHealth = math.floor(100 - (tonumber(damage.sparkplugs) or 0))
        
        print(string.format('[DAMAGE DEBUG] Alt: %d%% | Bat: %d%% | Brakes: %d%% | Oil: %d%% | Plugs: %d%%', 
            alternatorHealth,
            batteryHealth,
            brakeHealth,
            oilHealth, 
            plugHealth
        ))
        
        -- Calculate brake multiplier for debug
        if brakeHealth < DamageConfig.brakes.fade_threshold then
            local healthRatio = brakeHealth / 100
            local minPower = 1.0 - DamageConfig.brakes.max_power_loss
            local brakeMultiplier = math.max(minPower, minPower + (healthRatio * DamageConfig.brakes.max_power_loss))
            print(string.format('[BRAKE DEBUG] Brake power: %.0f%% (Health: %d%%)', brakeMultiplier * 100, brakeHealth))
        end
        
        local envMultiplier = calculateEnvironmentalMultiplier(veh)
        local waterDepth = getWaterDepth(veh)
        local inMud = isInMud(veh)
        
        if waterDepth > 0.1 or inMud then
            print(string.format('[DAMAGE DEBUG] Environmental damage active! Multiplier: %.2f', envMultiplier))
            damage.oil = math.min(100, (tonumber(damage.oil) or 0) + (0.3 * envMultiplier))
            damage.oil_filter = math.min(100, (tonumber(damage.oil_filter) or 0) + (0.25 * envMultiplier))
            
            if waterDepth > 0.3 then
                damage.carbattery = math.min(100, (tonumber(damage.carbattery) or 0) + (0.4 * envMultiplier))
            end
            
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
        alternator = 0,
        sparkplugs = 0,
        carbattery = 0,
        oil = 0,
        oil_filter = 0,
        brakes = 0,  -- NEW
        suspension = 0,
        axle = 0
    }
    
    applyDamage(veh, damage)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehicleFixed(veh)
    
    -- Reset notification flags
    local plate = GetVehicleNumberPlateText(veh)
    batteryDeadNotified[plate] = nil
    lastAlternatorStutter[plate] = nil
    lastBrakeWarning[plate] = nil  -- NEW
    
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

-- NEW: Command to damage battery for testing
RegisterCommand('damagebattery', function(source, args)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then 
        QBCore.Functions.Notify('Not in a vehicle', 'error')
        return 
    end
    
    local veh = GetVehiclePedIsIn(ped, false)
    local damage = getVehicleDamage(veh) or {}
    
    local amount = tonumber(args[1]) or 40
    damage.carbattery = math.min(100, (damage.carbattery or 0) + amount)
    
    applyDamage(veh, damage)
    
    local batteryHealth = 100 - damage.carbattery
    QBCore.Functions.Notify(string.format('Battery damaged to %d%%', batteryHealth), 'success')
    print('[DAMAGE] Battery health now:', batteryHealth, '%')
end, false)

-- NEW: Command to damage sparkplugs for testing
RegisterCommand('damageplugs', function(source, args)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then 
        QBCore.Functions.Notify('Not in a vehicle', 'error')
        return 
    end
    
    local veh = GetVehiclePedIsIn(ped, false)
    local damage = getVehicleDamage(veh) or {}
    
    local amount = tonumber(args[1]) or 40
    damage.sparkplugs = math.min(100, (damage.sparkplugs or 0) + amount)
    
    applyDamage(veh, damage)
    
    local sparkplugHealth = 100 - damage.sparkplugs
    QBCore.Functions.Notify(string.format('Spark plugs damaged to %d%%', sparkplugHealth), 'success')
    print('[DAMAGE] Sparkplug health now:', sparkplugHealth, '%')
end, false)

-- NEW: Command to damage alternator for testing
RegisterCommand('damagealternator', function(source, args)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then 
        QBCore.Functions.Notify('Not in a vehicle', 'error')
        return 
    end
    
    local veh = GetVehiclePedIsIn(ped, false)
    local damage = getVehicleDamage(veh) or {}
    
    local amount = tonumber(args[1]) or 40
    damage.alternator = math.min(100, (damage.alternator or 0) + amount)
    
    applyDamage(veh, damage)
    
    -- Reset stutter timer so it stutters immediately for testing
    local plate = GetVehicleNumberPlateText(veh)
    lastAlternatorStutter[plate] = 0
    
    local alternatorHealth = 100 - damage.alternator
    QBCore.Functions.Notify(string.format('Alternator damaged to %d%%', alternatorHealth), 'success')
    print('[DAMAGE] Alternator health now:', alternatorHealth, '%')
end, false)

-- NEW: Command to damage brakes for testing
RegisterCommand('damagebrakes', function(source, args)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then 
        QBCore.Functions.Notify('Not in a vehicle', 'error')
        return 
    end

    local veh = GetVehiclePedIsIn(ped, false)
    local damage = getVehicleDamage(veh) or {}

    local amount = tonumber(args[1]) or 40
    damage.brakes = math.min(100, (tonumber(damage.brakes) or 0) + amount)

    applyDamage(veh, damage)

    local brakeHealth = math.floor(100 - (tonumber(damage.brakes) or 0))
    local brakePower = brakeHealth -- 1:1 mapping

    QBCore.Functions.Notify(string.format('Brakes damaged to %d%% (%d%% brake power)', brakeHealth, brakePower), 'success')
    print(('[DAMAGE] Brake health: %d%% | Brake power: %d%%'):format(brakeHealth, brakePower))

    if brakeHealth <= 0 then
        QBCore.Functions.Notify('🛑 TOTAL BRAKE FAILURE! S key disabled! Use handbrake/crashes to stop!', 'error', 6000)
    elseif brakeHealth < 30 then
        QBCore.Functions.Notify('🛑 CRITICAL: Only 30% braking power!', 'error', 5000)
    elseif brakeHealth < 60 then
        QBCore.Functions.Notify('⚠️ Reduced braking power', 'warning', 3000)
    end
end, false)

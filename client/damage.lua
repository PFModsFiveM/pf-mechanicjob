-- Vehicle Component Damage System with Environmental Effects and Realistic Failures
local QBCore = exports['qb-core']:GetCoreObject()

-- Global safe state setter so this file never crashes on state:set
if not SafeStateSet then
    function SafeStateSet(veh, key, value)
        if not veh or veh == 0 or not DoesEntityExist(veh) then return end
        local st = Entity(veh).state
        if st and st.set then
            st:set(key, value, true)
        else
            TriggerServerEvent('pf_mech:server:setState', NetworkGetNetworkIdFromEntity(veh), key, value)
        end
    end
end

-- Helper: Debug notify (only shows if Config.Debug = true)
local function DebugNotify(msg, type)
    if Config.Debug then
        QBCore.Functions.Notify(msg, type or 'primary', 3000)
    end
    if Config.Debug then
        print('[DAMAGE DEBUG] ' .. tostring(msg))
    end
end

-- Configuration
local DamageConfig = {
    enabled = true,
    checkInterval = 5000,
    damageRates = {
        alternator = 0.03,
        sparkplugs = 0.08,
        carbattery = 0.04,
        oil = 0.02,              -- RESTORE: was 0.00
        oil_filter = 0.01,       -- RESTORE: was 0.00
        brakes = 0.05,
        suspension = 0.04,
        axle = 0.03,
        fuel_injector = 0.01,    -- RESTORE: was 0.00
        powersteeringpump = 0.00,
        power_steering_fluid = 0.00,
        radiator = 0.00,
        transmissionfluid = 0.00,
        brakefluid = 0.00,
        coolant = 0.00,
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
local lastBrakeWarning = {}
local repairInProgress = {} -- NEW: Track vehicles being repaired [plate] = true

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

-- Helper: Get water/mud depth (add IsEntityInWater fallback)
local function getWaterDepth(veh)
    if not veh or not DoesEntityExist(veh) then return 0.0 end
    local x,y,z = table.unpack(GetEntityCoords(veh))
    local found, height = GetWaterHeight(x, y, z)
    if found then
        local depth = (height - z)
        if depth < 0 then depth = 0 end
        return depth
    end
    if IsEntityInWater(veh) then
        -- Fallback: treat as at least shallow (0.3) when native fails
        return 0.3
    end
    return 0.0
end

-- Increase speed wear factors (more visible)
local function speedWearFactor(mph)
    if mph <= 40.0 then return 0.00 end
    if mph <= 80.0 then return 0.30 end
    if mph <= 100.0 then return 0.80 end
    if mph <= 120.0 then return 1.60 end
    local over = mph - 120.0
    return 2.5 + (over * 0.12)       -- >120 ramps sharply
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
    damage.fuel_injector = damage.fuel_injector or 0
    damage.powersteeringpump = damage.powersteeringpump or 0
    damage.radiator = damage.radiator or 0
    damage.power_steering_fluid = damage.power_steering_fluid or 0
    damage.transmissionfluid = damage.transmissionfluid or 0
    damage.brakefluid = damage.brakefluid or 0
    damage.coolant = damage.coolant or 0
    damage.engine_part = damage.engine_part or 0
    damage.body_part   = damage.body_part or 0
    return damage
end

-- Helper: Apply damage to vehicle state (ADD engine_part/body_part preservation)
local function applyDamage(veh, damage)
    if not veh or not DoesEntityExist(veh) or not damage then 
        print('[DAMAGE ERROR] applyDamage called with invalid parameters')
        return 
    end
    
    local state = Entity(veh)
    if not state or not state.state then 
        print('[DAMAGE ERROR] Vehicle entity state not available')
        return 
    end
    
    local cleanDamage = {
        alternator = math.min(100, math.max(0, tonumber(damage.alternator) or 0)),
        sparkplugs = math.min(100, math.max(0, tonumber(damage.sparkplugs) or 0)),
        carbattery = math.min(100, math.max(0, tonumber(damage.carbattery) or 0)),
        brakes     = math.min(100, math.max(0, tonumber(damage.brakes) or 0)),
        suspension = math.min(100, math.max(0, tonumber(damage.suspension) or 0)),
        axle       = math.min(100, math.max(0, tonumber(damage.axle) or 0)),
        -- NEW: keep virtual damage values for engine/body so debug menu can reflect them
        engine_part = math.min(100, math.max(0, tonumber(damage.engine_part) or 0)),
        body_part   = math.min(100, math.max(0, tonumber(damage.body_part) or 0)),
    }

    -- Fractional (round to 2 decimals to minimize network spam)
    local function keep(key)
        local v = tonumber(damage[key]) or 0
        v = math.min(100, math.max(0, v))
        cleanDamage[key] = tonumber(string.format('%.2f', v))
    end
    keep('oil')
    keep('oil_filter')
    keep('fuel_injector')
    keep('powersteeringpump')
    keep('radiator')
    keep('power_steering_fluid')
    keep('transmissionfluid')
    keep('brakefluid')
    keep('coolant')

    -- Debug only when oil actually changes noticeably
    if (Entity(veh).state.partDamage and Entity(veh).state.partDamage.oil) then
        local prev = tonumber(Entity(veh).state.partDamage.oil) or 0
        if math.abs(prev - cleanDamage.oil) >= 0.10 then
            print(string.format('[DAMAGE DEBUG] Oil damage %.2f -> %.2f', prev, cleanDamage.oil))
        end
    end

    SafeStateSet(veh, 'partDamage', cleanDamage)
    
    -- Wait a frame to ensure state is set
    Wait(0)
    
    -- Verify the state was actually set
    local verify = (Entity(veh).state.partDamage) or {}
    print('[DAMAGE DEBUG] Verified partDamage after set:', json.encode(verify))
end

-- NEW: Handle vehicle starting with battery/sparkplug/alternator failures
local function attemptVehicleStart(veh, damage)
    local batteryHealth = 100 - (tonumber(damage.carbattery) or 0)
    local sparkplugHealth = 100 - (tonumber(damage.sparkplugs) or 0)
    local alternatorHealth = 100 - (tonumber(damage.alternator) or 0)
    local injectorHealth   = 100 - (tonumber(damage.fuel_injector) or 0)
    
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
    
    -- Make starting harder if fuel injector is damaged
    if injectorHealth < 60 then
        startChance = startChance * (injectorHealth / 100.0)
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

-- Cache for original handling values to avoid compounding multipliers
local BrakeHandlingBase = {}      -- [veh] = { brake = number, hand = number }
local BrakeLastMultiplier = {}    -- [veh] = number
-- NEW: keep the original unmodified handling so we can fully restore
local OriginalBrakeHandling = {}  -- [veh] = { brake = number, hand = number }

-- NEW: Function to reset brake cache (call after repairs)
local function ResetBrakeCache(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end

    -- If we never captured originals, approximate them by undoing last multiplier
    local lastMult = BrakeLastMultiplier[veh] or 1.0
    local curBrake = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce') or 1.0
    local curHand  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce') or 1.0
    local approxOrig = { brake = (lastMult > 0 and (curBrake / lastMult) or curBrake), hand = (lastMult > 0 and (curHand / lastMult) or curHand) }

    -- Prefer previously saved originals if present
    local orig = OriginalBrakeHandling[veh] or approxOrig

    -- Restore originals immediately
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', orig.brake)
    SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', orig.hand)

    -- Rebuild caches
    OriginalBrakeHandling[veh] = orig
    BrakeHandlingBase[veh] = { brake = orig.brake, hand = orig.hand }
    BrakeLastMultiplier[veh] = 1.0

    if Config.Debug then
        print(string.format('[BRAKE RESET] Restored base: brake=%.4f hand=%.4f', orig.brake, orig.hand))
    end
end

-- Export for other scripts to call
exports('ResetBrakeCache', ResetBrakeCache)

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

        local effBrakeDmg = math.max(tonumber(dmg.brakes) or 0, tonumber(dmg.brakefluid) or 0)
        local brakeHealth = math.max(0, math.min(100, 100 - effBrakeDmg))

        if brakeHealth <= 0 then
            local vel = GetEntityVelocity(veh)
            local fwd = GetEntityForwardVector(veh)
            local fwdSpeed = vel.x*fwd.x + vel.y*fwd.y + vel.z*fwd.z
            local speed = math.sqrt(vel.x*vel.x + vel.y*vel.y + vel.z*vel.z)
            if fwdSpeed > 0.5 and speed > 0.5 then
                DisableControlAction(0, 72, true)
            end
        end

        local brakeMultiplier = brakeHealth / 100.0

        if not BrakeHandlingBase[veh] then
            local curBrake = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce') or 0.0
            local curHand  = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce') or 0.0
            local lastMult = BrakeLastMultiplier[veh] or 1.0
            local origBrake = (lastMult > 0 and curBrake / lastMult) or curBrake
            local origHand  = (lastMult > 0 and curHand  / lastMult) or curHand
            if not OriginalBrakeHandling[veh] then
                OriginalBrakeHandling[veh] = { brake = origBrake, hand = origHand }
            end
            BrakeHandlingBase[veh] = { brake = OriginalBrakeHandling[veh].brake, hand = OriginalBrakeHandling[veh].hand }
        end

        local base = BrakeHandlingBase[veh]
        if base and base.brake and base.brake > 0 then
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', base.brake * brakeMultiplier)
        end
        if base and base.hand and base.hand > 0 then
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', base.hand * brakeMultiplier)
        end

        BrakeLastMultiplier[veh] = brakeMultiplier

        -- NEW: If fully healthy (pads and fluid), force-restore to originals immediately
        if brakeMultiplier >= 0.999 then
            local orig = OriginalBrakeHandling[veh]
            if orig then
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fBrakeForce', orig.brake)
                SetVehicleHandlingFloat(veh, 'CHandlingData', 'fHandBrakeForce', orig.hand)
                BrakeHandlingBase[veh] = { brake = orig.brake, hand = orig.hand }
                BrakeLastMultiplier[veh] = 1.0
            end
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
    
    -- Fuel injector: hard to start if damaged
    local injectorDmg = tonumber(damage.fuel_injector) or 0
    if injectorDmg > 70 then
        if math.random(100) < injectorDmg - 60 then
            SetVehicleEngineOn(veh, false, true, true)
            QBCore.Functions.Notify('⚠️ Fuel injector failing!', 'error', 3000)
        end
    end

    -- Power steering pump: harder to steer if damaged
    local psDmg = tonumber(damage.powersteeringpump) or 0
    if psDmg > 0 then
        local mult = 1.0 - (psDmg / 100)
        SetVehicleSteeringScale(veh, mult)
        if psDmg > 70 then
            QBCore.Functions.Notify('⚠️ Power steering pump failing!', 'error', 3000)
        end
    end

    -- Radiator: overheating if damaged
    local radDmg = tonumber(damage.radiator) or 0
    if radDmg > 70 then
        if math.random(100) < (radDmg - 60) then
            SetVehicleEngineTemperature(veh, 120.0)
            QBCore.Functions.Notify('⚠️ Radiator failing! Overheating!', 'error', 3000)
            if radDmg > 90 and math.random(100) < 10 then
                SetVehicleEngineOn(veh, false, true, true)
            end
        end
    end

    -- Transmission fluid: delays gear change if low
    local tfDmg = tonumber(damage.transmissionfluid) or 0
    if tfDmg > 50 then
        local delay = math.floor((tfDmg - 50) * 10)
        Citizen.Wait(delay)
    end

    -- Brake fluid: acts like damaged brakes
    local bfDmg = tonumber(damage.brakefluid) or 0
    if bfDmg > 50 then
        -- Use same logic as brakes (reduce brake force)
        -- (Handled in brake thread)
    end

    -- Coolant: overheating and fire if low
    local coolantDmg = tonumber(damage.coolant) or 0
    if coolantDmg > 80 then
        if math.random(100) < (coolantDmg - 80) then
            SetVehicleEngineTemperature(veh, 150.0)
            QBCore.Functions.Notify('⚠️ Coolant low! Overheating!', 'error', 3000)
            -- Steam effect (SYNCED)
            pcall(function()
                TriggerServerEvent('pf_mech:vfx:oneshot', {
                    dict='core',
                    name='exp_grd_petrol_pump',
                    type='entity',
                    netId=NetworkGetNetworkIdFromEntity(veh),
                    pos={0.0, 2.0, 1.0},
                    rot={0.0, 0.0, 0.0},
                    scale=1.0
                })
            end)
            if coolantDmg >= 100 and math.random(100) < 20 then
                -- Fire!
                StartEntityFire(veh)
                QBCore.Functions.Notify('🔥 Engine fire! Coolant empty!', 'error', 5000)
            end
        end
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

-- NEW: Track mileage per vehicle (persisted in entity state)
local function getVehicleMileage(veh)
    if not veh or not DoesEntityExist(veh) then return 0 end
    local state = Entity(veh).state
    return tonumber(state.mileage) or 0
end
local function addMileage(veh, miles)
    if not veh or not DoesEntityExist(veh) then return end
    local state = Entity(veh).state
    local current = tonumber(state.mileage) or 0
    SafeStateSet(veh, 'mileage', current + miles)
end

-- NEW: Tables used but previously undefined
local LastBrakePress = {}
local BrakeHeat = {}

-- DEBUG: Valid parts for damage commands
local debugValidParts = {
    alternator=true, sparkplugs=true, carbattery=true, oil=true, oil_filter=true,
    brakes=true, suspension=true, axle=true, fuel_injector=true, powersteeringpump=true,
    radiator=true, power_steering_fluid=true, transmissionfluid=true, brakefluid=true,
    coolant=true
}

local function applyAndSyncDamage(veh, damage)
    applyDamage(veh, damage)
    applyDamageEffects(veh, damage)
end

local function setPartDamage(veh, part, value)
    if not DoesEntityExist(veh) then return false, 'No vehicle' end
    if not debugValidParts[part] then return false, 'Invalid part' end
    local damage = getVehicleDamage(veh) or {}
    damage[part] = math.max(0, math.min(100, tonumber(value) or 0))
    applyAndSyncDamage(veh, damage)
    return true
end

local function addPartDamage(veh, part, add)
    if not DoesEntityExist(veh) then return false, 'No vehicle' end
    if not debugValidParts[part] then return false, 'Invalid part' end
    local damage = getVehicleDamage(veh) or {}
    local current = tonumber(damage[part]) or 0
    damage[part] = math.max(0, math.min(100, current + (tonumber(add) or 0)))
    applyAndSyncDamage(veh, damage)
    return true
end

-- DEBUG COMMANDS (only register if Config.Debug = true)
if Config.Debug then
    RegisterCommand('damagepart', function(_, args)
        local part, value = args[1], args[2]
        if not part or not value then
            print('Usage: /damagepart <part> <value 0-100>')
            return
        end
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local ok, err = setPartDamage(veh, part, value)
        if ok then QBCore.Functions.Notify(('Set %s damage to %s%%'):format(part, value), 'success')
        else QBCore.Functions.Notify(err, 'error') end
    end)

    RegisterCommand('damageadd', function(_, args)
        local part, value = args[1], args[2]
        if not part or not value then
            print('Usage: /damageadd <part> <delta>')
            return
        end
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local ok, err = addPartDamage(veh, part, value)
        if ok then QBCore.Functions.Notify(('Added %s%% damage to %s'):format(value, part), 'warning')
        else QBCore.Functions.Notify(err, 'error') end
    end)

    RegisterCommand('damageall', function(_, args)
        local value = tonumber(args[1]) or 0
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return QBCore.Functions.Notify('No vehicle', 'error') end
        local damage = getVehicleDamage(veh) or {}
        for part,_ in pairs(debugValidParts) do
            damage[part] = math.max(0, math.min(100, value))
        end
        applyAndSyncDamage(veh, damage)
        QBCore.Functions.Notify(('All parts set to %d%%'):format(value), 'success')
    end)

    RegisterCommand('damagereset', function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return QBCore.Functions.Notify('No vehicle', 'error') end
        local damage = getVehicleDamage(veh) or {}
        for part,_ in pairs(debugValidParts) do damage[part] = 0 end
        applyAndSyncDamage(veh, damage)
        QBCore.Functions.Notify('All part damage reset', 'success')
    end)

    -- Convenience damage commands: /damageoil 80, /damagebrakes 60, etc.
    local function clamp01(v) return math.max(0, math.min(100, tonumber(v) or 0)) end
    local function setPartAndSync(veh, part, value)
        local d = getVehicleDamage(veh) or {}
        d[part] = clamp01(value)
        applyDamage(veh, d)
        applyDamageEffects(veh, d)
    end
    local function regDamageCommand(cmd, partKey)
        RegisterCommand(cmd, function(_, args)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 then QBCore.Functions.Notify('Not in a vehicle', 'error'); return end
            local val = args[1]
            if val == nil then
                QBCore.Functions.Notify(('Usage: /%s <0-100>'):format(cmd), 'error')
                return
            end
            setPartAndSync(veh, partKey, val)
            QBCore.Functions.Notify(('Set %s damage to %d%%'):format(partKey, clamp01(val)), 'primary')
        end, false)
    end

    -- Register per-part commands
    regDamageCommand('damageoil',                'oil')
    regDamageCommand('damagebrakes',             'brakes')
    regDamageCommand('damagebattery',            'carbattery')
    regDamageCommand('damagecarbattery',         'carbattery')
    regDamageCommand('damagesparkplugs',         'sparkplugs')
    regDamageCommand('damagealternator',         'alternator')
    regDamageCommand('damageradiator',           'radiator')
    regDamageCommand('damagecoolant',            'coolant')
    regDamageCommand('damagebrakefluid',         'brakefluid')
    regDamageCommand('damagetransmissionfluid',  'transmissionfluid')
    regDamageCommand('damagepowersteeringpump',  'powersteeringpump')
    regDamageCommand('damagepowersteeringfluid', 'power_steering_fluid')
    regDamageCommand('damagesuspension',         'suspension')
    regDamageCommand('damageaxle',               'axle')
end -- END Config.Debug block

-- Main damage loop
CreateThread(function()
    local lastPos = {}
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
        
        local plate = GetVehicleNumberPlateText(veh)
        if repairInProgress[plate] then goto continue end
        
        local damage = getVehicleDamage(veh)
        if not damage then goto continue end
        
        local speed = GetEntitySpeed(veh) * 2.236936
        local rpm   = GetVehicleCurrentRpm(veh)
        local waterDepth = getWaterDepth(veh)
        local inMud = isInMud(veh)

        -- ========== MILEAGE TRACKING ==========
        local pos = GetEntityCoords(veh)
        if lastPos[veh] then
            local dist = #(pos - lastPos[veh]) * 0.000621371 -- meters to miles
            addMileage(veh, dist)
        end
        lastPos[veh] = pos

        -- ========== BRAKES (extended wear system) ==========
        do
            local cfg = Config.WearRates.brakes -- Use config values
            local brakeAdd = 0.0
            local speed = GetEntitySpeed(veh) * 2.236936
            local isBraking = IsControlPressed(0, 72)
            local isHandbrake = IsControlPressed(0, 76)
            local isAccel = IsControlPressed(0, 71)
            local isBrakeKey = IsControlPressed(0, 72)
            local brakePressure = GetControlValue(0, 72) or 0
            local steerAngle = math.abs(GetVehicleSteeringAngle(veh) or 0.0)

            -- Baseline random wear while moving
            if speed > 5.0 then
                brakeAdd = brakeAdd + (math.random(
                    math.floor(cfg.baselineRandomMin * 100),
                    math.floor(cfg.baselineRandomMax * 100)
                ) / 100.0)
            end

            -- Speed extra
            if speed > cfg.speedExtraStartMPH then
                local over = speed - cfg.speedExtraStartMPH
                brakeAdd = brakeAdd + (over * cfg.speedExtraScale)
            end

            -- Active braking
            if isBraking then
                local base = (speed > 60) and 0.55 or (speed > 30 and 0.35 or 0.18)
                base = base * (0.4 + (brakePressure / 255.0) * 0.9)
                brakeAdd = brakeAdd + base

                -- Sustained press bonus
                local now = GetGameTimer()
                if not LastBrakePress[veh] then LastBrakePress[veh] = now end
                if (now - LastBrakePress[veh]) >= cfg.sustainedBrakeInterval then
                    brakeAdd = brakeAdd + cfg.sustainedBonus
                    LastBrakePress[veh] = now + 800
                end

                -- Cornering stress
                if steerAngle > cfg.steeringAngleWearStart then
                    local angOver = steerAngle - cfg.steeringAngleWearStart
                    brakeAdd = brakeAdd + (angOver * cfg.steeringAngleScale)
                end
            else
                LastBrakePress[veh] = nil
            end

            -- Handbrake slides
            if isHandbrake and speed > 6.0 then
                brakeAdd = brakeAdd + cfg.handbrakePerTick
            end

            -- Burnout (W+S)
            if isAccel and isBrakeKey and speed > 1.5 then
                brakeAdd = brakeAdd + cfg.burnoutExtra
            end

            -- Downhill
            do
                local vel = GetEntityVelocity(veh)
                local fwd = GetEntityForwardVector(veh)
                local fwdSpeed = vel.x*fwd.x + vel.y*fwd.y + vel.z*fwd.z
                if isBraking and fwdSpeed < cfg.downhillDecelThreshold then
                    brakeAdd = brakeAdd + cfg.downhillBonus
                end
            end

            -- Heat system
            local heat = BrakeHeat[veh] or 0
            if isBraking or isHandbrake then
                heat = heat + (brakeAdd * cfg.heatIncreasePerWear)
            else
                heat = math.max(0, heat - cfg.heatDecayPerTick)
            end
            BrakeHeat[veh] = heat

            if heat > 120 then
                brakeAdd = brakeAdd + (heat * cfg.heatWearScale)
            end

            if brakeAdd > 0 then
                damage.brakes = math.min(100, (tonumber(damage.brakes) or 0) + brakeAdd)
            end
        end

        -- ========== RADIATOR - USE CONFIG ==========
        do
            local cfg = Config.WearRates.radiator
            local bodyHealth = GetVehicleBodyHealth(veh)
            if bodyHealth < 800 then
                local bodyDmg = (1000 - bodyHealth) / 1000
                damage.radiator = math.min(100, (tonumber(damage.radiator) or 0) + (bodyDmg * cfg.bodyDamageScale))
            end
            if HasEntityCollidedWithAnything(veh) and speed > 20.0 then
                damage.radiator = math.min(100, (tonumber(damage.radiator) or 0) + cfg.collisionDamage)
            end
            if waterDepth > 0.2 then
                damage.radiator = math.min(100, (tonumber(damage.radiator) or 0) + cfg.waterIngestionRate)
            end
        end

        -- ========== COOLANT - USE CONFIG ==========
        do
            local cfg = Config.WearRates.coolant
            local coolantAdd = 0.0
            if speed > cfg.speedThreshold then
                local over = speed - cfg.speedThreshold
                coolantAdd = coolantAdd + (cfg.speedLossBase + (over * cfg.speedLossScale))
            end
            local temp = GetVehicleEngineTemperature(veh) or 90.0
            if temp > cfg.tempThreshold then
                coolantAdd = coolantAdd + ((temp - cfg.tempThreshold) * cfg.tempLossScale)
            end
            local radDmg = tonumber(damage.radiator) or 0
            if radDmg > cfg.radiatorDamageThreshold then
                coolantAdd = coolantAdd + ((radDmg - cfg.radiatorDamageThreshold) * cfg.radiatorLossScale)
            end
            if waterDepth > 0.1 then
                coolantAdd = coolantAdd + cfg.waterContamination
            end
            damage.coolant = math.min(100, (tonumber(damage.coolant) or 0) + coolantAdd)
        end

        -- ========== AXLE & SUSPENSION - USE CONFIG ==========
        do
            local cfg = Config.WearRates.suspension
            local onGround = IsVehicleOnAllWheels(veh)
            if not onGround and speed > cfg.airtimeSpeedThreshold then
                local airFactor = math.min(2.0, speed / 60.0)
                damage.axle       = math.min(100, (tonumber(damage.axle) or 0) + (airFactor * cfg.airtimeScale))
                damage.suspension = math.min(100, (tonumber(damage.suspension) or 0) + (airFactor * cfg.suspensionAirtimeScale))
            end
            if speed > 60 then
                damage.suspension = math.min(100, (tonumber(damage.suspension) or 0) + cfg.highSpeedWear)
            end
        end

        -- ========== SPARK PLUGS - USE CONFIG ==========
        do
            local cfg = Config.WearRates.sparkplugs
            local plugAdd = 0.0
            local miles = getVehicleMileage(veh)
            local mileageDmg = math.floor(miles / cfg.mileagePerPercent)
            if mileageDmg > (tonumber(damage.sparkplugs) or 0) then
                plugAdd = plugAdd + (mileageDmg - (tonumber(damage.sparkplugs) or 0))
            end
            local temp = GetVehicleEngineTemperature(veh) or 90.0
            if temp > cfg.overheatingTempThreshold then
                plugAdd = plugAdd + ((temp - cfg.overheatingTempThreshold) * cfg.overheatingScale)
            end
            if IsEntityOnFire(veh) then
                plugAdd = plugAdd + cfg.fireDamage
            end
            local sparkDmg = tonumber(damage.sparkplugs) or 0
            if sparkDmg > cfg.misfireThreshold and math.random(100) < cfg.misfireChance then
                plugAdd = plugAdd + cfg.misfireDamage
            end
            local oilHealth = 100 - (tonumber(damage.oil) or 0)
            if oilHealth < cfg.oilLeakThreshold then
                plugAdd = plugAdd + ((cfg.oilLeakThreshold - oilHealth) * cfg.oilLeakScale)
            end
            damage.sparkplugs = math.min(100, (tonumber(damage.sparkplugs) or 0) + plugAdd)
        end

        -- ========== OIL & OIL FILTER (RESTORED) ==========
        do
            local oilAdd = DamageConfig.damageRates.oil
            local filterAdd = DamageConfig.damageRates.oil_filter
            
            -- Speed multiplier
            if speed > 80 then
                oilAdd = oilAdd * 1.8
                filterAdd = filterAdd * 1.5
            end
            
            -- High RPM
            if rpm > 0.85 then
                oilAdd = oilAdd * 1.5
            end
            
            -- Engine temp
            local temp = GetVehicleEngineTemperature(veh) or 90.0
            if temp > 110.0 then
                oilAdd = oilAdd + ((temp - 110.0) * 0.02)
            end
            
            -- Dirty filter makes oil degrade faster
            local filterDmg = tonumber(damage.oil_filter) or 0
            if filterDmg > 60 then
                oilAdd = oilAdd + (filterDmg * 0.003)
            end
            
            -- Dirty oil clogs filter
            local oilDmg = tonumber(damage.oil) or 0
            if oilDmg > 50 then
                filterAdd = filterAdd + (oilDmg * 0.002)
            end
            
            damage.oil = math.min(100, (tonumber(damage.oil) or 0) + oilAdd)
            damage.oil_filter = math.min(100, (tonumber(damage.oil_filter) or 0) + filterAdd)
        end

        -- ========== FUEL INJECTOR (RESTORED) ==========
        do
            local injAdd = DamageConfig.damageRates.fuel_injector
            if injAdd > 0 then
                -- Degrade faster with dirty fuel (simulated by low oil quality)
                local oilHealth = 100 - (tonumber(damage.oil) or 0)
                if oilHealth < 40 then
                    injAdd = injAdd * 2.0
                end
                
                -- High speed wear
                if speed > 90 then
                    injAdd = injAdd * 1.5
                end
                
                damage.fuel_injector = math.min(100, (tonumber(damage.fuel_injector) or 0) + injAdd)
            end
        end

        -- chassis wear from terrain
        if inMud then
            damage.suspension = math.min(100, (tonumber(damage.suspension) or 0) + Config.WearRates.suspension.mudWear)
            damage.axle       = math.min(100, (tonumber(damage.axle) or 0) + Config.WearRates.axle.mudWear)
        end
        if waterDepth > 0.30 then
            damage.carbattery = math.min(100, (tonumber(damage.carbattery) or 0) + 0.8)
        end

        -- Persist & effects
        applyDamage(veh, damage)
        applyDamageEffects(veh, damage)
        local envMultiplier = calculateEnvironmentalMultiplier(veh)
        checkEnvironmentalWarnings(veh, envMultiplier)
        checkComponentWarnings(veh, damage)
        
        ::continue::
    end
end)

-- Commands (fixed) - WRAP IN DEBUG CHECK
if Config.Debug then
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
        local state = Entity(veh).state
        local damage = {
            alternator = 0, sparkplugs = 0, carbattery = 0,
            oil = 0, oil_filter = 0, brakes = 0,
            suspension = 0, axle = 0,
            fuel_injector = 0, powersteeringpump = 0, radiator = 0,
            power_steering_fluid = 0, transmissionfluid = 0,
            brakefluid = 0, coolant = 0
        }
        SafeStateSet(veh, 'partDamage', damage)
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehicleFixed(veh)
        QBCore.Functions.Notify('Vehicle damage reset', 'success')
    end, false)

    RegisterCommand('savedamage', function()
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            QBCore.Functions.Notify('Not in a vehicle', 'error')
            return
        end
        
        local veh = GetVehiclePedIsIn(ped, false)
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
        local state = Entity(veh).state
        local partDamage = state.partDamage or {}
        
        TriggerServerEvent('pf_mech:sync:forceSave', plate)
        QBCore.Functions.Notify(string.format('Saved %s (oil: %.1f%%)', plate, tonumber(partDamage.oil) or 0), 'success')
    end, false)
end -- END DEBUG COMMANDS

-- Helper: Check if player has toolbox (moved from main.lua if needed, or reference main.lua version)
local function hasToolbox(callback)
    QBCore.Functions.TriggerCallback('pf_mech:hasToolbox', function(has)
        if not has then
            QBCore.Functions.Notify('You need a toolbox to do mechanic work!', 'error')
        end
        callback(has)
    end)
end

-- Generic repair item handler (replaces all individual RegisterNetEvent handlers)
RegisterNetEvent('pf-mechanicjob:client:useRepairItem', function(itemName)
    local veh = getRepairVehicle()
    if not veh then return QBCore.Functions.Notify('No vehicle nearby', 'error') end
    if not ensureControl(veh) then return QBCore.Functions.Notify('Cannot get control of vehicle', 'error') end

    local damage = getVehicleDamage(veh) or {}
    
    -- Map item to damage key and check if repair is needed
    local itemToDamageKey = {
        alternator = 'alternator',
        engine_oil = 'oil',
        oil_filter = 'oil_filter',
        fuel_injector = 'fuel_injector',
        powersteeringpump = 'powersteeringpump',
        radiator = 'radiator',
        power_steering_fluid = 'power_steering_fluid',
        transmissionfluid = 'transmissionfluid',
        brakefluid = 'brakefluid',
        coolant = 'coolant',
        sparkplugs = 'sparkplugs',
        carbattery = 'carbattery',
        brake_pads = 'brakes',
        susp_arm = 'suspension',
        axleparts = 'axle',
        engine_part = 'engine',
        body_part = 'body',
        tire_new = 'tires'
    }
    
    local damageKey = itemToDamageKey[itemName]
    if not damageKey then return QBCore.Functions.Notify('Invalid repair item', 'error') end
    
    -- Special handling for engine/body (use health values)
    if damageKey == 'engine' then
        local engineHealth = GetVehicleEngineHealth(veh)
        if engineHealth >= 1000.0 then return QBCore.Functions.Notify('Engine already OK', 'success') end
    elseif damageKey == 'body' then
        local bodyHealth = GetVehicleBodyHealth(veh)
        if bodyHealth >= 1000.0 then return QBCore.Functions.Notify('Body already OK', 'success') end
    elseif damageKey == 'tires' then
        -- Check if any tire is burst
        local hasBurstTire = false
        for i = 0, 5 do
            if IsVehicleTyreBurst(veh, i, false) then
                hasBurstTire = true
                break
            end
        end
        if not hasBurstTire then return QBCore.Functions.Notify('Tires already OK', 'success') end
    elseif damageKey == 'brakes' then
        -- Check if any brake pad is worn
        local brakeDmg = tonumber(damage.brakes) or 0
        if brakeDmg <= 0 then return QBCore.Functions.Notify('Brake pads already OK', 'success') end
    elseif damageKey == 'suspension' then
        -- Check if suspension is damaged
        local suspDmg = tonumber(damage.suspension) or 0
        if suspDmg <= 0 then return QBCore.Functions.Notify('Suspension already OK', 'success') end
    elseif damageKey == 'axle' then
        -- Check if axle is damaged
        local axleDmg = tonumber(damage.axle) or 0
        if axleDmg <= 0 then return QBCore.Functions.Notify('Axle already OK', 'success') end
    else
        if (tonumber(damage[damageKey]) or 0) <= 0 then
            -- Get item label for notification
            local itemLabel = itemName:gsub('_', ' '):gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper()..rest:lower()
            end)
            if QBCore.Shared.Items[itemName] and QBCore.Shared.Items[itemName].label then
                itemLabel = QBCore.Shared.Items[itemName].label
            end
            return QBCore.Functions.Notify(itemLabel..' already OK', 'success')
        end
    end

    -- NEW: Check if toolbox is required for this item
    local needsToolbox = true
    if Config.NoToolboxRequired then
        for _, exemptItem in ipairs(Config.NoToolboxRequired) do
            if exemptItem == itemName then
                needsToolbox = false
                break
            end
        end
    end

    local function doRepair()
        -- Get item label for progress bar
        local itemLabel = itemName:gsub('_', ' ')
        if QBCore.Shared.Items[itemName] and QBCore.Shared.Items[itemName].label then
            itemLabel = QBCore.Shared.Items[itemName].label
        end
        
        -- Get appropriate time based on item
        local repairTimes = {
            alternator = 4000,
            engine_oil = 5000,
            oil_filter = 3500,
            fuel_injector = 4500,
            powersteeringpump = 5000,
            radiator = 6000,
            power_steering_fluid = 3000,
            transmissionfluid = 4000,
            brakefluid = 3000,
            coolant = 3500,
            sparkplugs = 4000,
            carbattery = 3500,
            brake_pads = 4500,
            susp_arm = 5000,
            axleparts = 6000,
            engine_part = 8000,
            body_part = 7000,
            tire_new = 4000
        }
        
        local repairTime = repairTimes[itemName] or 4000

        QBCore.Functions.TriggerCallback('pf-mechanicjob:server:consumeItem', function(ok)
            if not ok then return QBCore.Functions.Notify('Missing '..itemLabel, 'error') end
            
            doMechanicAction('Replacing '..itemLabel, repairTime)
            
            -- Apply repair based on item type
            if damageKey == 'engine' then
                SetVehicleEngineHealth(veh, math.min(1000.0, GetVehicleEngineHealth(veh) + 200.0))
                damage.engine = math.max(0, (damage.engine or 0) - 20)
            elseif damageKey == 'body' then
                local newHealth = math.min(1000.0, GetVehicleBodyHealth(veh) + 200.0)
                SetVehicleBodyHealth(veh, newHealth)
                if newHealth >= 1000.0 then
                    SetVehicleDeformationFixed(veh)
                    SetVehicleFixed(veh)
                end
                damage.body = math.max(0, (damage.body or 0) - 20)
            elseif damageKey == 'tires' then
                -- Fix one burst tire
                for i = 0, 5 do
                    if IsVehicleTyreBurst(veh, i, false) then
                        SetVehicleTyreFixed(veh, i)
                        damage.tires = damage.tires or {}
                        local key = ({[0]='lf',[1]='rf',[2]='lr',[3]='rr',[4]='lm',[5]='rm'})[i] or tostring(i)
                        damage.tires[key] = 0
                        break
                    end
                end
            elseif damageKey == 'oil' then
                SetVehicleEngineHealth(veh, math.min(1000.0, GetVehicleEngineHealth(veh) + 150.0))
                damage.oil = 0
            elseif damageKey == 'brakes' then
                -- FIX: per-item brake pad repair based on max_items (default 4)
                local maxItems = (Config.PartRules.brake_pads and Config.PartRules.brake_pads.max_items) or 4
                local perItem = 100 / maxItems                       -- each pad restores this % of health
                local currentDamage = tonumber(damage.brakes) or 0    -- damage scale 0-100
                local newDamage = math.max(0, currentDamage - perItem)
                damage.brakes = newDamage
                ResetBrakeCache(veh)
            elseif damageKey == 'suspension' then
                damage.suspension = math.max(0, (damage.suspension or 0) - 50)
            elseif damageKey == 'axle' then
                damage.axle = math.max(0, (damage.axle or 0) - 50)
            elseif damageKey == 'sparkplugs' then
                SetVehicleEngineHealth(veh, math.min(1000.0, GetVehicleEngineHealth(veh) + 50.0))
                damage.sparkplugs = math.max(0, (damage.sparkplugs or 0) - 30)
            else
                -- For all other parts, set to 0
                damage[damageKey] = 0
            end
            
            SafeStateSet(veh, 'partDamage', damage)
            QBCore.Functions.Notify(itemLabel..' replaced', 'success')
        end, itemName)
    end

    -- Check for toolbox if needed
    if needsToolbox then
        hasToolbox(function(has)
            if not has then return end
            doRepair()
        end)
    else
        doRepair()
    end
end)

-- Keep old individual event handlers for backwards compatibility (but they just call the new handler)
RegisterNetEvent('pf-mechanicjob:client:use:alternator', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'alternator')
end)

RegisterNetEvent('pf-mechanicjob:client:use:engine_oil', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'engine_oil')
end)

RegisterNetEvent('pf-mechanicjob:client:use:oil_filter', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'oil_filter')
end)

RegisterNetEvent('pf-mechanicjob:client:use:fuel_injector', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'fuel_injector')
end)

RegisterNetEvent('pf-mechanicjob:client:use:powersteeringpump', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'powersteeringpump')
end)

RegisterNetEvent('pf-mechanicjob:client:use:radiator', function()
    TriggerEvent('pf-mechanicjob:client:useRepairItem', 'radiator')
end)

-- power_steering_fluid (ALREADY EXISTS - keep as is)
-- ...existing code...

-- transmissionfluid (ALREADY EXISTS - keep as is)
-- ...existing code...

-- brakefluid (ALREADY EXISTS - keep as is)
-- ...existing code...

-- coolant (ALREADY EXISTS - keep as is)
exports('GetPartDamageTable', function(veh)
    if not veh or not DoesEntityExist(veh) then return {} end
    local st = Entity(veh).state
    return st.partDamage or {}
end)

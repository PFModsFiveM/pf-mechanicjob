local QBCore = exports['qb-core']:GetCoreObject()

-- Track vehicles spawned from garage
local garageSpawnedVehicles = {}

-- Helper: Which garage system is active?
local function getGarageSystem()
    return (Config and Config.GarageSystem) or 'qb-garages'
end

-- Register vehicle spawn event for both garage systems
if getGarageSystem() == 'qb-garages' then
    RegisterNetEvent('QBCore:Client:OnVehicleSpawn', function(veh)
        if not veh or not DoesEntityExist(veh) then return end
        
        Wait(500)
        
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
        
        -- Request saved state from database
        QBCore.Functions.TriggerCallback('pf_mech:loadVehicleState', function(data)
            if not data then return end
            
            -- Apply FULL partDamage first
            if data.partDamage then
                local state = Entity(veh).state
                state:set('partDamage', data.partDamage, true)
                
                if Config.Debug then
                    print(string.format('[GARAGE SYNC] Restored %s: oil=%.1f%%, brakes=%.1f%%', plate, 
                        tonumber(data.partDamage.oil) or 0, 
                        tonumber(data.partDamage.brakes) or 0))
                end
            end
            
            -- Apply mileage
            if data.mileage then
                local state = Entity(veh).state
                state:set('mileage', tonumber(data.mileage) or 0, true)
            end
            
            -- Apply health values
            if data.engineHealth then SetVehicleEngineHealth(veh, tonumber(data.engineHealth)) end
            if data.bodyHealth then SetVehicleBodyHealth(veh, tonumber(data.bodyHealth)) end
            if data.tankHealth then SetVehiclePetrolTankHealth(veh, tonumber(data.tankHealth)) end
            if data.dirtLevel then SetVehicleDirtLevel(veh, tonumber(data.dirtLevel)) end
        end, plate)
        
        garageSpawnedVehicles[plate] = veh
    end)
elseif getGarageSystem() == 'cd_garages' then
    -- cd_garages: vehicle spawn event
    RegisterNetEvent('cd_garages:client:vehicleSpawned', function(veh, plate)
        if not veh or not DoesEntityExist(veh) then return end
        Wait(500)
        plate = (plate or GetVehicleNumberPlateText(veh) or ''):gsub('%s+', ''):upper()
        -- Request saved state from database
        QBCore.Functions.TriggerCallback('pf_mech:loadVehicleState', function(data)
            if not data then return end
            if data.partDamage then
                local state = Entity(veh).state
                state:set('partDamage', data.partDamage, true)
                if Config.Debug then
                    print(string.format('[GARAGE SYNC][CD] Restored %s: oil=%.1f%%, brakes=%.1f%%', plate, 
                        tonumber(data.partDamage.oil) or 0, 
                        tonumber(data.partDamage.brakes) or 0))
                end
            end
            if data.mileage then
                local state = Entity(veh).state
                state:set('mileage', tonumber(data.mileage) or 0, true)
            end
            if data.engineHealth then SetVehicleEngineHealth(veh, tonumber(data.engineHealth)) end
            if data.bodyHealth then SetVehicleBodyHealth(veh, tonumber(data.bodyHealth)) end
            if data.tankHealth then SetVehiclePetrolTankHealth(veh, tonumber(data.tankHealth)) end
            if data.dirtLevel then SetVehicleDirtLevel(veh, tonumber(data.dirtLevel)) end
        end, plate)
        garageSpawnedVehicles[plate] = veh
    end)
end

-- Helper: Build payload from vehicle
local function buildPayloadFromVehicle(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    local state = Entity(veh).state
    local partDamage = state.partDamage or {}
    local mileage = tonumber(state.mileage) or 0
    
    SetVehicleModKit(veh, 0)
    local mods = {}
    for i = 0, 49 do
        local mod = GetVehicleMod(veh, i)
        if mod and mod ~= -1 then mods[tostring(i)] = mod end
    end
    
    local cosmetics = {
        windowTint = GetVehicleWindowTint(veh),
        wheelType = GetVehicleWheelType(veh),
        xenonColor = GetVehicleXenonLightsColour(veh),
        plateIndex = GetVehicleNumberPlateTextIndex(veh),
        livery = GetVehicleLivery(veh),
        extras = {}
    }
    
    -- Capture extras
    for i = 0, 20 do
        if DoesExtraExist(veh, i) then
            cosmetics.extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i)
        end
    end
    
    local pr, pg, pb = GetVehicleCustomPrimaryColour(veh)
    local sr, sg, sb = GetVehicleCustomSecondaryColour(veh)
    local colors = {
        primary = (pr and pg and pb) and {pr, pg, pb} or nil,
        secondary = (sr and sg and sb) and {sr, sg, sb} or nil,
        pearlescent = GetVehicleExtraColours(veh),
        wheel = select(2, GetVehicleExtraColours(veh))
    }
    
    return {
        plate = plate,
        mods = mods,
        cosmetics = cosmetics,
        colors = colors,
        partDamage = partDamage,
        mileage = mileage,
        engineHealth = GetVehicleEngineHealth(veh),
        bodyHealth = GetVehicleBodyHealth(veh),
        tankHealth = GetVehiclePetrolTankHealth(veh),
        dirtLevel = GetVehicleDirtLevel(veh)
    }
end

-- NEW: Continuous state sync (every 10 seconds while driving)
-- This ensures server ALWAYS has latest damage state, so when qb-garages stores the car, it's up-to-date
CreateThread(function()
    while true do
        Wait(10000) -- 10 seconds
        
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and DoesEntityExist(veh) then
                if GetPedInVehicleSeat(veh, -1) == ped then
                    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
                    local state = Entity(veh).state
                    
                    -- Get FULL vehicle properties using qb-core function
                    local props = QBCore.Functions.GetVehicleProperties(veh)
                    
                    -- Add our custom diagnostics data
                    props.partDamage = state.partDamage or {}
                    props.mileage = tonumber(state.mileage) or 0
                    
                    -- Tell server to cache this full state
                    if getGarageSystem() == 'qb-garages' then
                        TriggerServerEvent('pf_mech:sync:cacheVehicleState', {
                            plate = plate,
                            netId = NetworkGetNetworkIdFromEntity(veh),
                            props = props  -- Send entire props object
                        })
                    elseif getGarageSystem() == 'cd_garages' then
                        -- cd_garages: use their export/event for state sync if needed
                        TriggerServerEvent('pf_mech:sync:cacheVehicleState', {
                            plate = plate,
                            netId = NetworkGetNetworkIdFromEntity(veh),
                            props = props  -- Send entire props object
                        })
                    end
                    
                    if Config.Debug then
                        print(string.format('[GARAGE SYNC] Synced full state: %s (oil: %.1f%%)', 
                            plate, 
                            tonumber((props.partDamage or {}).oil) or 0
                        ))
                    end
                end
            end
        end
    end
end)

-- Manual save command for testing
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

-- Export for qb-garages to use (captures everything via GetVehicleProperties)
exports('SyncVehicleDiagnostics', function(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local plate = GetVehicleNumberPlateText(veh):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    local state = Entity(veh).state
    local props = QBCore.Functions.GetVehicleProperties(veh)
    props.partDamage = state.partDamage or {}
    props.mileage = tonumber(state.mileage) or 0
    
    TriggerServerEvent('pf_mech:saveFullDiagnostics', plate, props)
end)

-- Export for qb-garages to use
exports('RestoreVehicleDiagnostics', function(veh, diag)
    if not veh or not DoesEntityExist(veh) or not diag then return end
    local state = Entity(veh).state
    if diag.partDamage then state:set('partDamage', diag.partDamage, true) end
    if diag.mileage then state:set('mileage', diag.mileage, true) end
    if diag.engineHealth then SetVehicleEngineHealth(veh, diag.engineHealth + 0.0) end
    if diag.bodyHealth then SetVehicleBodyHealth(veh, diag.bodyHealth + 0.0) end
end)

-- Export current diagnostics snapshot
exports('GetCurrentDiagnostics', function(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local state = Entity(veh).state
    local props = QBCore.Functions.GetVehicleProperties(veh)
    props.partDamage = state.partDamage or {}
    props.mileage = tonumber(state.mileage) or 0
    return props
end)

-- Apply diagnostics snapshot to vehicle
exports('ApplyVehicleDiagnostics', function(veh, data)
    if not veh or not DoesEntityExist(veh) or not data then return end
    
    -- Apply custom data
    local st = Entity(veh).state
    if data.partDamage then st:set('partDamage', data.partDamage, true) end
    if data.mileage then st:set('mileage', tonumber(data.mileage) or 0, true) end
    
    -- Apply standard vehicle properties
    if QBCore.Functions.SetVehicleProperties then
        QBCore.Functions.SetVehicleProperties(veh, data)
    end
end)

-- Debug export
exports('DebugPrintDiag', function(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local st = Entity(veh).state
    print('[DIAG DEBUG] plate='..(GetVehicleNumberPlateText(veh) or 'N/A')..' state='..json.encode(st.partDamage or {}))
end)

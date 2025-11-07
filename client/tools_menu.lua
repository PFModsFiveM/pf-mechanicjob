local QBCore = exports['qb-core']:GetCoreObject()

print('[TOOLS_MENU] Client script loaded') -- Debug: confirm file loads

-- Helper: Get vehicle damage
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local state = Entity(veh)
    if not state or not state.state then return nil end
    local damage = state.state.partDamage or {}
    damage.brakes = damage.brakes or 0
    damage.fuel_injector = damage.fuel_injector or 0
    damage.powersteeringpump = damage.powersteeringpump or 0
    damage.radiator = damage.radiator or 0
    damage.power_steering_fluid = damage.power_steering_fluid or 0
    damage.transmissionfluid = damage.transmissionfluid or 0
    damage.brakefluid = damage.brakefluid or 0
    damage.coolant = damage.coolant or 0
    damage.alternator = damage.alternator or 0
    damage.sparkplugs = damage.sparkplugs or 0
    damage.carbattery = damage.carbattery or 0
    damage.oil = damage.oil or 0             -- make sure oil key always present
    damage.oil_filter = damage.oil_filter or 0
    damage.brakes = damage.brakes or 0
    damage.suspension = damage.suspension or 0
    damage.axle = damage.axle or 0
    return damage
end

-- Helper: get usable vehicle (in or near player)
function getRepairVehicle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and DoesEntityExist(veh) then return veh end
    end
    local coords = GetEntityCoords(ped)
    local veh = GetClosestVehicle(coords.x, coords.y, coords.z, 6.0, 0, 70)
    if veh ~= 0 and DoesEntityExist(veh) then return veh end
    return nil
end

-- Helper: request control before mutating entity state
function ensureControl(entity, timeoutMs)
    if not entity or entity == 0 then return false end
    local start = GetGameTimer()
    while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - start) < (timeoutMs or 700) do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

-- Helper: progress bar helper
function doMechanicAction(label, ms)
    if QBCore.Functions.Progressbar then
        QBCore.Functions.Progressbar('pf_mech_repair', label or 'Working...', ms or 2000, false, true, {
            disableMovement = true, disableCarMovement = true, disableMouse = false, disableCombat = true,
        }, {
            animDict = 'mini@repair', anim = 'fixing_a_ped', flags = 49,
        }, {}, {}, function() end, function() end)
    else
        Wait(ms or 2000)
    end
end

-- Helper: Calculate parts needed for repair
local function partsNeededForRepair(partKey, healthPercent)
    local rule = (Config.PartRules or {})[partKey] or {}
    local maxItems = tonumber(rule.max_items) or 0

    if maxItems <= 0 then
        if partKey:match('engine') or rule.type == 'engine' then maxItems = 5 end
        if partKey == 'body_part' or rule.type == 'body' then maxItems = 5 end
        if partKey == 'sparkplugs' or rule.type == 'sparkplugs' then maxItems = 8 end
        if rule.type == 'battery' then maxItems = 1 end
        if rule.type == 'axle' then maxItems = 4 end
        if partKey == 'tire_new' then maxItems = 4 end
        if rule.type == 'oil' or partKey == 'engine_oil' then maxItems = 1 end
        if rule.type == 'oil_filter' or partKey == 'oil_filter' then maxItems = 1 end
        if partKey == 'brakes' then maxItems = 4 end
        if partKey == 'fuel_injector' then maxItems = 4 end
        if partKey == 'powersteeringpump' then maxItems = 1 end
        if partKey == 'radiator' then maxItems = 1 end
        if partKey == 'power_steering_fluid' then maxItems = 1 end
        if partKey == 'transmissionfluid' then maxItems = 1 end
        if partKey == 'brakefluid' then maxItems = 1 end
        if partKey == 'coolant' then maxItems = 1 end
    end

    healthPercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))

    if maxItems <= 0 then return 0 end
    local missingPercent = 100 - healthPercent
    -- Use ceiling so any damage > 0 requires at least 1 item for single-item parts
    local needed = math.ceil((missingPercent / 100) * maxItems)
    return math.max(0, math.min(needed, maxItems))
end

local DiagnosticLabels = {
    alternator = "Alternator",
    sparkplugs = "Spark Plugs",
    carbattery = "Car Battery",
    engine_oil = "Engine Oil",
    oil_filter = "Oil Filter",
    brakes = "Brake Pads",
    susp_arm = "Suspension Arm",
    axleparts = "Axle Parts",
    engine_part = "Engine Part",
    body_part = "Body Panel",
    tire_new = "Tire",
    fuel_injector = "Fuel Injector",
    powersteeringpump = "Power Steering Pump",
    radiator = "Radiator",
    power_steering_fluid = "Power Steering Fluid",
    transmissionfluid = "Transmission Fluid",
    brakefluid = "Brake Fluid",
    coolant = "Coolant"
}

-- NEW: Map part keys to item image filenames
local DiagnosticImages = {
    alternator = 'alternator.png',
    sparkplugs = 'sparkplugs.png',
    carbattery = 'carbattery.png',
    engine_oil = 'engine_oil.png',
    oil_filter = 'oil_filter.png',
    brakes = 'brake_pads.png',
    susp_arm = 'susp_arm.png',
    axleparts = 'axleparts.png',
    engine_part = 'engine_part.png',
    body_part = 'body_part.png',
    tire_new = 'tire_new.png',
    fuel_injector = 'fuel_injector.png',
    powersteeringpump = 'powersteeringpump.png',
    radiator = 'radiator.png',
    power_steering_fluid = 'power_steering_fluid.png',
    transmissionfluid = 'transmissionfluid.png',
    brakefluid = 'brakefluid.png',
    coolant = 'coolant.png'
}

-- Register the openToolsMenu event
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu', function()
    print('[TOOLS DEBUG] openToolsMenu event received')
    
    local veh = getRepairVehicle()
    if not veh then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end

    -- Start clipboard inspection animation
    local ped = PlayerPedId()
    local clipboardDict = "missheistdockssetup1clipboard@base"
    local clipboardAnim = "base"
    local clipboardProp = `prop_notepad_01`

    RequestAnimDict(clipboardDict)
    while not HasAnimDictLoaded(clipboardDict) do Wait(10) end
    
    RequestModel(clipboardProp)
    while not HasModelLoaded(clipboardProp) do Wait(10) end

    currentClipboard = CreateObject(clipboardProp, 0.0, 0.0, 0.0, true, true, false)
    local bone = GetPedBoneIndex(ped, 18905)
    AttachEntityToEntity(currentClipboard, ped, bone, 0.1, 0.02, 0.05, -50.0, 90.0, 0.0, true, true, false, true, 1, true)
    
    TaskPlayAnim(ped, clipboardDict, clipboardAnim, 8.0, -8.0, -1, 50, 0, false, false, false)

    if not QBCore.Functions.Progressbar then
        QBCore.Functions.Notify('Progressbar not available', 'error')
        ClearPedTasks(ped)
        if currentClipboard then DeleteEntity(currentClipboard) end
        currentClipboard = nil
        return
    end

    QBCore.Functions.Progressbar(
        'inspect_vehicle',
        'Inspecting vehicle...',
        10000,
        false,
        true,
        {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        {},
        {},
        {},
        function() -- success
            ClearPedTasks(ped)
            if currentClipboard then
                DeleteEntity(currentClipboard)
                currentClipboard = nil
            end
            TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
        end,
        function() -- cancel
            ClearPedTasks(ped)
            if currentClipboard then
                DeleteEntity(currentClipboard)
                currentClipboard = nil
            end
            QBCore.Functions.Notify('Inspection cancelled', 'error')
        end
    )
end)

-- Show diagnostics menu after inspection completes
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu:showMenu', function(veh)
    if not DoesEntityExist(veh) then
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return
    end

    local engineHealth = math.floor(math.max(0, math.min(1000, GetVehicleEngineHealth(veh) or 0)) / 10)
    local bodyHealth = math.floor(math.max(0, math.min(1000, GetVehicleBodyHealth(veh) or 0)) / 10)
    local tankHealth = math.floor(math.max(0, math.min(1000, GetVehiclePetrolTankHealth(veh) or 0)) / 10)
    
    -- FIX: Get damage from entity state correctly
    local state = Entity(veh).state
    local damage = state.partDamage or {}
    
    -- Calculate health percentages (100 - damage)
    local health = {}
    health.alternator = math.floor(100 - (tonumber(damage.alternator) or 0))
    health.sparkplugs = math.floor(100 - (tonumber(damage.sparkplugs) or 0))
    health.carbattery = math.floor(100 - (tonumber(damage.carbattery) or 0))
    health.engine_oil = math.floor(100 - (tonumber(damage.oil) or 0))
    health.oil_filter = math.floor(100 - (tonumber(damage.oil_filter) or 0))
    health.brakes = math.floor(100 - (tonumber(damage.brakes) or 0))
    health.susp_arm = math.floor(100 - (tonumber(damage.suspension) or 0))
    health.axleparts = math.floor(100 - (tonumber(damage.axle) or 0))
    health.engine_overall = engineHealth
    health.body_overall = bodyHealth
    health.fuel_injector = math.floor(100 - (tonumber(damage.fuel_injector) or 0))
    health.powersteeringpump = math.floor(100 - (tonumber(damage.powersteeringpump) or 0))
    health.radiator = math.floor(100 - (tonumber(damage.radiator) or 0))
    health.power_steering_fluid = math.floor(100 - (tonumber(damage.power_steering_fluid) or 0))
    health.transmissionfluid = math.floor(100 - (tonumber(damage.transmissionfluid) or 0))
    health.brakefluid = math.floor(100 - (tonumber(damage.brakefluid) or 0))
    health.coolant = math.floor(100 - (tonumber(damage.coolant) or 0))

    -- Debug print to verify values
    if Config.Debug then
        print('[TOOLS DEBUG] Raw damage state:', json.encode(damage))
        print('[TOOLS DEBUG] Calculated health:', json.encode(health))
    end

    local menu = {
        { header = 'Vehicle Diagnostics', txt = GetVehicleNumberPlateText(veh) or 'Unknown', isMenuHeader = true },
        { header = 'Overall Condition', txt = string.format('Engine %d%% • Body %d%% • Tank %d%%', engineHealth, bodyHealth, tankHealth), isMenuHeader = true }
    }

    local function addPartEntry(ruleKey, label, hp)
        hp = math.floor(tonumber(hp) or 0)
        hp = math.max(0, math.min(100, hp))
        
        local txt
        if hp >= 100 then
            txt = 'Perfect condition'
        else
            local needed = partsNeededForRepair(ruleKey, hp)
            needed = math.floor(tonumber(needed) or 0)
            txt = string.format('Needs: %d parts', needed)
        end
        
        local img = DiagnosticImages[ruleKey] or nil
        
        menu[#menu+1] = {
            header = string.format('%s — %d%%', label, hp),
            txt = txt,
            icon = img,
            params = hp < 100 and {
                event = 'pf-mechanicjob:client:repairPart',
                args = { vehicle = veh, part = ruleKey, needed = partsNeededForRepair(ruleKey, hp) }
            } or {}
        }
    end

    addPartEntry('engine_part', DiagnosticLabels.engine_part or 'Engine', health.engine_overall)
    addPartEntry('body_part', DiagnosticLabels.body_part or 'Body', health.body_overall)
    addPartEntry('alternator', DiagnosticLabels.alternator, health.alternator)
    addPartEntry('carbattery', DiagnosticLabels.carbattery, health.carbattery)
    addPartEntry('sparkplugs', DiagnosticLabels.sparkplugs, health.sparkplugs)
    addPartEntry('engine_oil', DiagnosticLabels.engine_oil, health.engine_oil)
    addPartEntry('oil_filter', DiagnosticLabels.oil_filter, health.oil_filter)
    addPartEntry('brakes', DiagnosticLabels.brakes, health.brakes)
    addPartEntry('susp_arm', DiagnosticLabels.susp_arm, health.susp_arm)
    addPartEntry('axleparts', DiagnosticLabels.axleparts, health.axleparts)
    addPartEntry('fuel_injector', DiagnosticLabels.fuel_injector, health.fuel_injector)
    addPartEntry('powersteeringpump', DiagnosticLabels.powersteeringpump, health.powersteeringpump)
    addPartEntry('radiator', DiagnosticLabels.radiator, health.radiator)
    addPartEntry('power_steering_fluid', DiagnosticLabels.power_steering_fluid, health.power_steering_fluid)
    addPartEntry('transmissionfluid', DiagnosticLabels.transmissionfluid, health.transmissionfluid)
    addPartEntry('brakefluid', DiagnosticLabels.brakefluid, health.brakefluid)
    addPartEntry('coolant', DiagnosticLabels.coolant, health.coolant)

    local burstCount = 0
    local wheelNames = { [0]='Front Left', [1]='Front Right', [2]='Rear Left', [3]='Rear Right', [4]='Middle Left', [5]='Middle Right' }
    
    for i=0,5 do
        local isBurst = false
        pcall(function() isBurst = IsVehicleTyreBurst(veh, i, false) end)
        
        if isBurst then
            burstCount = burstCount + 1
            local label = wheelNames[i] or ('Wheel '..tostring(i))
            menu[#menu+1] = {
                header = string.format('Tire %s — 0%%', label),
                txt = 'Needs: 1 tire',
                params = {}
            }
        end
    end

    if burstCount == 0 then
        menu[#menu+1] = {
            header = 'Tires — 100%',
            txt = 'Perfect condition',
            params = {}
        }
    end

    menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }

    if exports['qb-menu'] and exports['qb-menu'].openMenu then
        exports['qb-menu']:openMenu(menu)
    else
        QBCore.Functions.Notify('qb-menu not found.', 'error')
    end
end)

-- Repair part handler
RegisterNetEvent('pf-mechanicjob:client:repairPart', function(data)
    local vehicle = data.vehicle
    local part = data.part
    local needed = tonumber(data.needed) or 1

    if not DoesEntityExist(vehicle) then return end

    local label = DiagnosticLabels[part] or part

    local itemMap = {
        engine_part = 'engine_part',
        body_part = 'body_part',
        carbattery = 'carbattery',
        sparkplugs = 'sparkplugs',
        alternator = 'alternator',
        engine_oil = 'engine_oil',
        oil_filter = 'oil_filter',
        brakes = 'brake_pads',
        susp_arm = 'susp_arm',
        axleparts = 'axleparts',
        tire_new = 'tire_new',
        fuel_injector = 'fuel_injector',
        powersteeringpump = 'powersteeringpump',
        radiator = 'radiator',
        power_steering_fluid = 'power_steering_fluid',
        transmissionfluid = 'transmissionfluid',
        brakefluid = 'brakefluid',
        coolant = 'coolant'
    }

    local itemName = itemMap[part] or part

    if not QBCore.Functions.Progressbar then
        QBCore.Functions.Notify('Progressbar not available', 'error')
        return
    end

    QBCore.Functions.Progressbar(
        'repair_part',
        string.format('Replacing %s...', label),
        5000,
        false,
        true,
        {
            disableMovement = true,
            disableCarMovement = true,
            disableMouse = false,
            disableCombat = true,
        },
        {
            animDict = 'mini@repair',
            anim = 'fixing_a_ped',
            flags = 49,
        },
        {},
        {},
        function() -- success
            QBCore.Functions.TriggerCallback('pf_mech:server:attemptRepair', function(success, msg)
                if success then
                    QBCore.Functions.Notify(msg or 'Repair successful', 'success')
                else
                    QBCore.Functions.Notify(msg or 'Missing required parts', 'error')
                end
            end, NetworkGetNetworkIdFromEntity(vehicle), part, needed, nil)
        end,
        function() -- cancel
            QBCore.Functions.Notify('Repair cancelled', 'error')
        end
    )
end)

-- Repair kit logic
RegisterNetEvent('pf-mechanicjob:client:useRepairKit', function()
    local veh = getRepairVehicle()
    if not veh then QBCore.Functions.Notify('No vehicle nearby', 'error'); return end
    if not ensureControl(veh) then QBCore.Functions.Notify('Cannot get control of vehicle', 'error'); return end

    -- Consume first to validate item exists
    QBCore.Functions.TriggerCallback('pf-mechanicjob:server:consumeItem', function(ok)
        if not ok then
            QBCore.Functions.Notify('No repair kit found', 'error')
            return
        end

        -- Mechanic animation + progress
        doMechanicAction('Using repair kit...', 5000)

        local damage = getVehicleDamage(veh) or {}
        local changed = false

        -- +20% health to alternator/battery if under 30% health (i.e. >70% damage)
        if (100 - (tonumber(damage.alternator) or 0)) < 30 then
            damage.alternator = math.max(0, (tonumber(damage.alternator) or 0) - 20)
            changed = true
        end
        if (100 - (tonumber(damage.carbattery) or 0)) < 30 then
            damage.carbattery = math.max(0, (tonumber(damage.carbattery) or 0) - 20)
            changed = true
        end

        -- Engine: add ~20% to engine health if below 70%
        local eng = GetVehicleEngineHealth(veh)
        if eng < 700 then
            SetVehicleEngineHealth(veh, math.min(1000.0, eng + 200.0))
            changed = true
        end

        if changed then
            -- replace direct state:set
            SafeStateSet(veh, 'partDamage', damage)
            QBCore.Functions.Notify('Repair kit used', 'success')
        else
            QBCore.Functions.Notify('Nothing eligible (targets must be under 30%)', 'error')
        end
    end, 'repair_kit')
end)

-- Clean up clipboard when menu closes
RegisterNetEvent('qb-menu:client:closeMenu', function()
    if currentClipboard and DoesEntityExist(currentClipboard) then
        print('[TOOLS DEBUG] Cleaning up clipboard')
        local ped = PlayerPedId()
        ClearPedTasks(ped)
        DeleteEntity(currentClipboard)
        currentClipboard = nil
    end
end)

local function SafeStateSet(veh, key, value)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local st = Entity(veh).state
    if st and st.set then
        st:set(key, value, true)
    else
        TriggerServerEvent('pf_mech:server:setState', NetworkGetNetworkIdFromEntity(veh), key, value)
    end
end
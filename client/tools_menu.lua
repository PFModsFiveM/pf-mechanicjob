local QBCore = exports['qb-core']:GetCoreObject()
print('[TOOLS_MENU] Client script loaded')

-- UNCONDITIONAL EARLY EXPORTS (avoid race / conditional export lookup)
-- Internal calls can just use GetCurrentDiagnostics() directly.
local function GetCurrentDiagnosticsInternal(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local st = Entity(veh).state or {}
    local partDamage = st.partDamage or {}
    return {
        partDamage = partDamage,
        mileage = tonumber(st.mileage) or 0,
        engineHealth = GetVehicleEngineHealth(veh),
        bodyHealth = GetVehicleBodyHealth(veh),
        tankHealth = GetVehiclePetrolTankHealth(veh),
        dirtLevel = GetVehicleDirtLevel(veh)
    }
end
function GetCurrentDiagnostics(veh) return GetCurrentDiagnosticsInternal(veh) end
exports('GetCurrentDiagnostics', GetCurrentDiagnosticsInternal)

-- Simple wheel steps mini-sequence (kept small; minigames.lua can override with richer one)
local function DoWheelStepsInternal()
    local ped = PlayerPedId()
    RequestAnimDict('mini@repair')
    while not HasAnimDictLoaded('mini@repair') do Wait(0) end
    local seq = {
        { 'Loosening lugs...', 1100 },
        { 'Removing wheel...', 1100 },
        { 'Fitting new wheel...', 1300 },
    }
    if QBCore.Functions.Progressbar then
        for i,s in ipairs(seq) do
            local done=false
            QBCore.Functions.Progressbar('pf_wheel_'..i, s[1], s[2], false, true,
                { disableMovement=true, disableCarMovement=true, disableCombat=true },
                { animDict='mini@repair', anim='fixing_a_ped', flags=49 },
                {}, {}, function() done=true end, function() done=true end
            )
            while not done do Wait(10) end
        end
    else
        for _,s in ipairs(seq) do Wait(s[2]) end
    end
    ClearPedTasks(ped)
    return true
end
exports('DoWheelSteps', DoWheelStepsInternal)

-- =========================================================
-- MISSING HELPER FUNCTIONS (moved from main.lua)
-- =========================================================
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

function ensureControl(entity, timeoutMs)
    if not entity or entity == 0 then return false end
    local start = GetGameTimer()
    while not NetworkHasControlOfEntity(entity) and (GetGameTimer() - start) < (timeoutMs or 700) do
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    end
    return NetworkHasControlOfEntity(entity)
end

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

-- =========================================================
-- SIMPLE WHEEL DAMAGE DETECTION (VANILLA BURST ONLY)
-- =========================================================
local function GetWheelIndices(veh)
    if not veh or not DoesEntityExist(veh) then return {0,1,2,3} end
    local total = 4
    pcall(function()
        local n = GetVehicleNumberOfWheels(veh)
        if n and n > 0 then total = n end
    end)
    if total <= 4 then return {0,1,2,3} end
    local out = {}
    for i=0, math.min(total-1, 5) do out[#out+1] = i end
    return out
end

-- Simple burst check PLUS health fallback (rear wheels sometimes report health but not burst)
function IsWheelDamaged(veh, idx)
    if not veh or not DoesEntityExist(veh) then return false end
    local burst = false
    pcall(function()
        burst = IsVehicleTyreBurst(veh, idx, false) or IsVehicleTyreBurst(veh, idx, true)
    end)
    if burst then return true end
    -- Fallback: some tyres (often rear) keep health but are functionally "damaged"
    local health = 100.0
    pcall(function()
        health = GetVehicleTyreHealth(veh, idx) or 100.0
    end)
    return health < 50.0
end

PF_IsWheelDamaged = IsWheelDamaged
exports('IsWheelDamaged', function(veh, idx) return IsWheelDamaged(veh, idx) end)

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

-- NEW: Map part keys to item image filenames (kept, but we will prefer inventory images)
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

-- NEW: Resolve images from the active inventory UI (qb-inventory / lj-inventory / ox_inventory)
local function resourceStarted(name)
    local st = GetResourceState(name)
    return st == 'started' or st == 'starting'
end
local function getInventoryImageBase()
    if resourceStarted('ox_inventory') then
        return 'nui://ox_inventory/web/images/'
    elseif resourceStarted('qb-inventory') then
        return 'nui://qb-inventory/html/images/'
    elseif resourceStarted('lj-inventory') then
        return 'nui://lj-inventory/html/images/'
    else
        -- fallback to qb-inventory structure
        return 'nui://qb-inventory/html/images/'
    end
end
local INVENTORY_IMAGE_BASE = getInventoryImageBase()
local FALLBACK_IMAGE_BASE = 'nui://pf-mechanicjob/html/img/'
local DEFAULT_PLACEHOLDER = FALLBACK_IMAGE_BASE .. 'placeholder.png'

-- Map partKey -> inventory item name (defaults to same key)
local PartToItemName = {
    alternator='alternator',
    sparkplugs='sparkplugs',
    carbattery='carbattery',
    engine_oil='engine_oil',
    oil_filter='oil_filter',
    brakes='brake_pads',
    susp_arm='susp_arm',
    axleparts='axleparts',
    engine_part='engine_part',
    body_part='body_part',
    tire_new='tire_new',
    fuel_injector='fuel_injector',
    powersteeringpump='powersteeringpump',
    radiator='radiator',
    power_steering_fluid='power_steering_fluid',
    transmissionfluid='transmissionfluid',
    brakefluid='brakefluid',
    coolant='coolant',
}

-- OPTIONAL: inject simple CSS once to enlarge qb-menu icons (only if qb-menu listens for custom action)
local qbMenuCssInjected = false
local function InjectQbMenuIconCSS()
    if qbMenuCssInjected then return end
    qbMenuCssInjected = true
    SendNUIMessage({
        action = 'pf_mech_inject_css',
        css = '.qb-menu-item img, .qb-menu-item-icon img { width:42px !important; height:42px !important; object-fit:contain }'
    })
end

-- FIX getMenuIcon (undefined fname)
local function getMenuIcon(partKey)
    partKey = tostring(partKey or '')
    local itemName = (PartToItemName and PartToItemName[partKey]) or partKey
    if QBCore and QBCore.Shared and QBCore.Shared.Items then
        local itm = QBCore.Shared.Items[itemName]
        if itm and itm.image then
            local fname = itm.image:match('%.') and itm.image or (itm.image .. '.png')
            return INVENTORY_IMAGE_BASE .. fname
        end
    end
    local mapped = DiagnosticImages[partKey]
    if mapped then return INVENTORY_IMAGE_BASE .. mapped end
    if mapped then return FALLBACK_IMAGE_BASE .. mapped end
    return DEFAULT_PLACEHOLDER
end

-- NEW: qb-menu layout CSS (inline icons bigger, taller menu)
local function InjectQbMenuLayoutCSS()
    if qbMenuCssInjected then return end
    qbMenuCssInjected = true
    SendNUIMessage({
        action='pf_mech_inject_css',
        css=table.concat({
            '.qb-menu-container,.qb-menu{max-height:75vh!important;}',
            '.qb-menu-item{min-height:58px!important;display:flex!important;align-items:center!important;}',
            '.qb-menu-item-icon img{width:46px!important;height:46px!important;margin-right:12px!important;object-fit:contain!important;}',
        },'')
    })
end

-- FIX: OpenMenuGeneric (populate ox_lib options)
local function OpenMenuGeneric(menu)
    local useOx = (Config and Config.MenuSystem == 'ox_lib')
    if useOx and resourceStarted('ox_lib') and lib and lib.registerContext then
        local contextId = 'pf_mech_diag_' .. GetGameTimer()
        local title, options = 'Diagnostics', {}
        for _, item in ipairs(menu) do
            if item.isMenuHeader then
                title = item.header or title
            else
                options[#options+1] = {
                    title = item.header or 'Item',
                    description = item.txt or '',
                    image = item.icon,
                    disabled = not (item.params and item.params.event),
                    onSelect = function()
                        if item.params and item.params.event then
                            TriggerEvent(item.params.event, item.params.args)
                        end
                    end
                }
            end
        end
        lib.registerContext({ id=contextId, title=title, options=options })
        lib.showContext(contextId)
    else
        if exports['qb-menu'] and exports['qb-menu'].openMenu then
            InjectQbMenuLayoutCSS()
            exports['qb-menu']:openMenu(menu)
        else
            QBCore.Functions.Notify('Menu system not found', 'error')
        end
    end
end

-- FIX: inspection progressbar (cleanup + trigger showMenu)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu', function()
    local veh = getRepairVehicle()
    if not veh then QBCore.Functions.Notify('No vehicle nearby','error'); return end
    local ped = PlayerPedId()
    local dict, anim, prop = "missheistdockssetup1clipboard@base", "base", `prop_notepad_01`
    RequestAnimDict(dict) while not HasAnimDictLoaded(dict) do Wait(0) end
    RequestModel(prop) while not HasModelLoaded(prop) do Wait(0) end
    currentClipboard = CreateObject(prop, 0,0,0,true,true,false)
    AttachEntityToEntity(currentClipboard, ped, GetPedBoneIndex(ped,18905), 0.1,0.02,0.05, -50.0,90.0,0.0, true,true,false,true,1,true)
    TaskPlayAnim(ped, dict, anim, 8.0,-8.0,-1,50,0,false,false,false)
    if not QBCore.Functions.Progressbar then
        QBCore.Functions.Notify('Progressbar not available','error')
        ClearPedTasks(ped); if currentClipboard then DeleteEntity(currentClipboard) end; currentClipboard=nil; return
    end
    QBCore.Functions.Progressbar('inspect_vehicle','Inspecting vehicle...',10000,false,true,
        { disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true },
        { animDict=dict, anim=anim, flags=50 }, {}, {},
        function()
            ClearPedTasks(ped)
            if currentClipboard then DeleteEntity(currentClipboard) currentClipboard=nil end
            TriggerEvent('pf-mechanicjob:client:openToolsMenu:showMenu', veh)
        end,
        function()
            ClearPedTasks(ped)
            if currentClipboard then DeleteEntity(currentClipboard) currentClipboard=nil end
            QBCore.Functions.Notify('Inspection cancelled','error')
        end
    )
end)

-- Show diagnostics menu after inspection completes (replace old handler)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu:showMenu', function(veh)
    if not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found', 'error'); return end

    local engineHealth = math.floor((GetVehicleEngineHealth(veh) or 0) / 10)
    local bodyHealth   = math.floor((GetVehicleBodyHealth(veh) or 0) / 10)
    local tankHealth   = math.floor((GetVehiclePetrolTankHealth(veh) or 0) / 10)

    -- NEW: read mileage and format
    local function formatMiles(mi)
        mi = tonumber(mi) or 0
        local s = string.format('%.1f', mi)
        local int, dec = s:match('^(%d+)%.(%d+)$')
        int = int:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,','')
        return int .. '.' .. dec
    end
    local st = Entity(veh).state
    local mileageMi = formatMiles(st and st.mileage or 0)

    local state = Entity(veh).state
    local damage = state.partDamage or {}

    -- REORDER: show plate and mileage in the same box
    local plate = GetVehicleNumberPlateText(veh) or 'Unknown'
    local menu = {
        { header='Vehicle Diagnostics', txt=('%s • Mileage: %s mi'):format(plate, mileageMi), isMenuHeader=true },
        { header='Overall Condition', txt=('Engine %d%% • Body %d%% • Tank %d%%'):format(engineHealth, bodyHealth, tankHealth), isMenuHeader=true },
    }
    local function calcHealth(d) return math.max(0, 100 - (tonumber(d) or 0)) end
    local partMap = {
        { key='engine_part', label=DiagnosticLabels.engine_part or 'Engine', hp=engineHealth },
        { key='body_part', label=DiagnosticLabels.body_part or 'Body', hp=bodyHealth },
        { key='alternator', label=DiagnosticLabels.alternator, hp=calcHealth(damage.alternator) },
        { key='carbattery', label=DiagnosticLabels.carbattery, hp=calcHealth(damage.carbattery) },
        { key='sparkplugs', label=DiagnosticLabels.sparkplugs, hp=calcHealth(damage.sparkplugs) },
        { key='engine_oil', label=DiagnosticLabels.engine_oil, hp=calcHealth(damage.oil) },
        { key='oil_filter', label=DiagnosticLabels.oil_filter, hp=calcHealth(damage.oil_filter) },
        { key='brakes', label=DiagnosticLabels.brakes, hp=calcHealth(damage.brakes) },
        { key='susp_arm', label=DiagnosticLabels.susp_arm, hp=calcHealth(damage.suspension) },
        { key='axleparts', label=DiagnosticLabels.axleparts, hp=calcHealth(damage.axle) },
        { key='fuel_injector', label=DiagnosticLabels.fuel_injector, hp=calcHealth(damage.fuel_injector) },
        { key='powersteeringpump', label=DiagnosticLabels.powersteeringpump, hp=calcHealth(damage.powersteeringpump) },
        { key='radiator', label=DiagnosticLabels.radiator, hp=calcHealth(damage.radiator) },
        { key='power_steering_fluid', label=DiagnosticLabels.power_steering_fluid, hp=calcHealth(damage.power_steering_fluid) },
        { key='transmissionfluid', label=DiagnosticLabels.transmissionfluid, hp=calcHealth(damage.transmissionfluid) },
        { key='brakefluid', label=DiagnosticLabels.brakefluid, hp=calcHealth(damage.brakefluid) },
        { key='coolant', label=DiagnosticLabels.coolant, hp=calcHealth(damage.coolant) },
    }
    local function addPartEntry(p)
        local hp = math.min(100, math.max(0, tonumber(p.hp) or 0))
        local hpInt = math.floor(hp + 0.5)
        local needed = hpInt >= 100 and 0 or partsNeededForRepair(p.key, hpInt)
        local txt = hpInt >= 100 and 'Perfect condition' or ('Needs: %d parts'):format(needed)
        menu[#menu+1] = {
            header = ('%s — %d%%'):format(p.label or p.key, hpInt),
            txt = txt,
            icon = getMenuIcon(p.key),
            params = (hpInt < 100 and needed > 0) and {
                event='pf-mechanicjob:client:repairPart',
                args={ vehicle=veh, part=p.key, needed=needed }
            } or {}
        }
    end

    for _,p in ipairs(partMap) do addPartEntry(p) end

    -- Tires (rear wheels were not showing due to placeholder & health-only damage)
    local wheelNames = { [0]='Front Left',[1]='Front Right',[2]='Rear Left',[3]='Rear Right',[4]='Middle Left',[5]='Middle Right' }
    local damagedCount=0
    for _,i in ipairs(GetWheelIndices(veh)) do
        local damaged = IsWheelDamaged(veh, i)
        if damaged then
            damagedCount = damagedCount + 1
            menu[#menu+1] = {
                header=('Tire %s — 0%%'):format(wheelNames[i] or i),
                txt='Needs: 1 tire',
                icon=getMenuIcon('tire_new'),
                params={ event='pf-mechanicjob:client:repairTireWheel', args={ vehicle=veh, wheel=i } }
            }
        end
    end
    if damagedCount==0 then
        menu[#menu+1] = { header='Tires — 100%', txt='Perfect condition', icon=getMenuIcon('tire_new'), params={} }
    end

    if Config.MenuSystem ~= 'ox_lib' then
        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    end

    OpenMenuGeneric(menu)
end)

-- FIX: repairPart handler (restore callback logic + event usage)
RegisterNetEvent('pf-mechanicjob:client:repairPart', function(data)
    local vehicle, part = data.vehicle, data.part
    local needed = tonumber(data.needed) or 1
    if not vehicle or not DoesEntityExist(vehicle) then return end
    local label = DiagnosticLabels[part] or part
    QBCore.Functions.Progressbar('repair_part', ('Replacing %s...'):format(label), 5000, false, true,
        { disableCombat=true, disableMovement=true, disableCarMovement=true },
        { animDict='mini@repair', anim='fixing_a_ped', flags=49 }, {}, {},
        function()
            QBCore.Functions.TriggerCallback('pf_mech:server:attemptRepair', function(success,msg)
                if success then
                    QBCore.Functions.Notify(msg or 'Repair successful','success')
                else
                    QBCore.Functions.Notify(msg or 'Missing required parts','error')
                end
            end, NetworkGetNetworkIdFromEntity(vehicle), part, needed, nil)
        end,
        function() QBCore.Functions.Notify('Repair cancelled','error') end
    )
end)

-- Wheel repair (burst or detached) - make more robust for rear wheels
RegisterNetEvent('pf-mechanicjob:client:repairTireWheel', function(data)
    local veh   = data and data.vehicle or getRepairVehicle()
    local wheel = data and tonumber(data.wheel or -1) or -1
    if not veh or veh == 0 or not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found','error'); return end

    -- Validate wheel index
    local valid=false
    for _,idx in ipairs(GetWheelIndices(veh)) do if idx == wheel then valid=true break end end
    if not valid then QBCore.Functions.Notify('Invalid wheel index','error'); return end

    if not ensureControl(veh) then QBCore.Functions.Notify('Cannot get control','error'); return end
    if not IsWheelDamaged(veh, wheel) then
        QBCore.Functions.Notify('Wheel not damaged','error')
        return
    end

    QBCore.Functions.TriggerCallback('pf-mechanicjob:server:consumeItem', function(ok)
        if not ok then QBCore.Functions.Notify('Missing tire','error'); return end

        doMechanicAction('Replacing tire...', 4000)

        -- First fix attempt
        SetVehicleTyreFixed(veh, wheel)
        Wait(120)

        -- If still damaged, force reattach
        if IsWheelDamaged(veh, wheel) then
            SetVehicleTyreBurst(veh, wheel, false, 1000.0)
            Wait(100)
            SetVehicleTyreFixed(veh, wheel)
            Wait(150)
        end

        -- Second fallback (some rears need double)
        if IsWheelDamaged(veh, wheel) then
            SetVehicleTyreBurst(veh, wheel, true, 25.0)
            Wait(120)
            SetVehicleTyreFixed(veh, wheel)
            Wait(200)
        end

        if IsWheelDamaged(veh, wheel) then
            QBCore.Functions.Notify('Tire could not be restored (mod conflict). Retry.', 'error')
            return
        end

        -- Update state
        local st = Entity(veh).state
        local pd = st.partDamage or {}
        pd.tires = pd.tires or {}
        local key = ({[0]='lf',[1]='rf',[2]='lr',[3]='rr',[4]='lm',[5]='rm'})[wheel] or tostring(wheel)
        pd.tires[key] = 0
        st:set('partDamage', pd, true)

        QBCore.Functions.Notify('Tire replaced', 'success')
    end, 'tire_new')
end)

-- Helper: Clean up clipboard when menu closes
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
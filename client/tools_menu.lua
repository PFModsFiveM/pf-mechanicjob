local QBCore = exports['qb-core']:GetCoreObject()

print('[TOOLS_MENU] Client script loaded') -- Debug: confirm file loads

-- Helper: Get vehicle damage (same logic as damage.lua)
local function getVehicleDamage(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    local state = Entity(veh)
    if not state or not state.state then return nil end
    local damage = state.state.partDamage or {}
    damage.brakes = damage.brakes or 0
    return damage
end

-- Helper: Calculate pads needed (same logic as damage.lua)
local function calcPadsNeeded(brakeDmg)
    if brakeDmg <= 0 then return 0 end
    return math.min(4, math.ceil(brakeDmg / 25))
end

-- Helper: Get nearest vehicle
local function getRepairVehicle()
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

-- NEW: Vehicle inspection with door control and clipboard prop
RegisterNetEvent('pf-mechanicjob:client:inspectVehicle', function()
    print('[TOOLS DEBUG] inspectVehicle event fired') -- Debug
    
    local veh = getRepairVehicle()
    if not veh then 
        print('[TOOLS DEBUG] No vehicle found') -- Debug
        QBCore.Functions.Notify('No vehicle found nearby.', 'error')
        return 
    end

    print('[TOOLS DEBUG] Vehicle found, starting inspection') -- Debug

    local ped = PlayerPedId()
    local clipboardObj = nil
    
    -- Open all doors during inspection
    for i = 0, 7 do
        SetVehicleDoorOpen(veh, i, false, false)
    end
    print('[TOOLS DEBUG] Doors opened') -- Debug

    -- Load welding animation (NOT clipboard yet)
    local weldDict = 'mini@repair'
    local weldAnim = 'fixing_a_ped'
    
    RequestAnimDict(weldDict)
    while not HasAnimDictLoaded(weldDict) do Wait(10) end
    
    -- Start welding animation FIRST
    TaskPlayAnim(ped, weldDict, weldAnim, 8.0, -8.0, -1, 49, 0, false, false, false)
    print('[TOOLS DEBUG] Welding animation started') -- Debug
    
    -- Use QBCore progressbar (most compatible)
    local progressSuccess = false
    if QBCore.Functions.Progressbar then
        print('[TOOLS DEBUG] Using QBCore progressbar')
        
        local inspectionComplete = nil  -- nil = waiting, true = success, false = cancelled
        
        QBCore.Functions.Progressbar(
            'vehicle_inspection',
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
                inspectionComplete = true
                print('[TOOLS DEBUG] Inspection complete - SUCCESS')
            end,
            function() -- cancel
                inspectionComplete = false
                print('[TOOLS DEBUG] Inspection cancelled')
            end
        )
        
        -- Wait for progress to complete (nil = still running)
        while inspectionComplete == nil do
            Wait(100)
        end
        
        -- Stop welding animation
        ClearPedTasks(ped)
        print('[TOOLS DEBUG] Welding animation stopped')
        
        -- Close all doors
        if DoesEntityExist(veh) then
            for i = 0, 7 do
                SetVehicleDoorShut(veh, i, false)
            end
        end
        
        -- Only open menu if inspection completed successfully
        if inspectionComplete == true then
            Wait(200) -- Brief pause before showing clipboard
            
            -- NOW load and show clipboard
            local clipboardModel = `p_amb_clipboard_01`
            local clipboardDict = 'missfam4'
            local clipboardAnim = 'base'
            
            RequestModel(clipboardModel)
            while not HasModelLoaded(clipboardModel) do Wait(10) end
            
            RequestAnimDict(clipboardDict)
            while not HasAnimDictLoaded(clipboardDict) do Wait(10) end
            
            -- Create clipboard prop
            clipboardObj = CreateObject(clipboardModel, 0.0, 0.0, 0.0, true, true, false)
            local boneIndex = GetPedBoneIndex(ped, 18905) -- Left hand bone
            AttachEntityToEntity(clipboardObj, ped, boneIndex, 0.10, 0.02, 0.08, -130.0, -50.0, 0.0, true, true, false, true, 1, true)
            
            -- Play clipboard animation
            TaskPlayAnim(ped, clipboardDict, clipboardAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
            
            print('[TOOLS DEBUG] Clipboard shown, opening menu')
            Wait(300) -- Let clipboard animation settle
            
            -- Store clipboard object globally so we can clean it up when menu closes
            currentClipboard = clipboardObj
            
            TriggerEvent('pf-mechanicjob:client:openToolsMenu')
        else
            QBCore.Functions.Notify('Inspection cancelled.', 'error')
        end
        
        progressSuccess = true
    end

    if not progressSuccess then
        print('[TOOLS DEBUG] Using fallback countdown')
        -- Fallback: simple 10 second countdown
        local startTime = GetGameTimer()
        local duration = 10000
        
        CreateThread(function()
            while GetGameTimer() - startTime < duration do
                local remaining = math.ceil((duration - (GetGameTimer() - startTime)) / 1000)
                DrawText2D(0.5, 0.9, ('Inspecting vehicle... %ds'):format(remaining), 0.5)
                Wait(0)
            end
            
            ClearPedTasks(ped)
            print('[TOOLS DEBUG] Inspection complete')
            
            if DoesEntityExist(veh) then
                for i = 0, 7 do
                    SetVehicleDoorShut(veh, i, false)
                end
            end
            
            Wait(500)
            TriggerEvent('pf-mechanicjob:client:openToolsMenu')
        end)
    end
end)

-- Helper: Draw 2D text on screen
function DrawText2D(x, y, text, scale)
    SetTextFont(4)
    SetTextProportional(0)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextDropShadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 255)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
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
        if rule.type == 'oil' then maxItems = 1 end
        if partKey == 'brakes' then maxItems = 4 end
    end

    healthPercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))

    if maxItems <= 0 then return 0 end
    local missingPercent = 100 - healthPercent
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
    tire_new = "Tire"
}

-- Open Mechanic Tools menu (FULL DIAGNOSTICS)
RegisterNetEvent('pf-mechanicjob:client:openToolsMenu', function()
    local veh = getRepairVehicle()
    if not veh then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end

    -- Get vehicle health
    local engineHealth = math.floor(math.max(0, math.min(1000, GetVehicleEngineHealth(veh) or 0)) / 10)
    local bodyHealth = math.floor(math.max(0, math.min(1000, GetVehicleBodyHealth(veh) or 0)) / 10)
    local tankHealth = math.floor(math.max(0, math.min(1000, GetVehiclePetrolTankHealth(veh) or 0)) / 10)
    
    -- Get part damage
    local damage = getVehicleDamage(veh) or {}
    
    -- Calculate health percentages (health = 100 - damage)
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

    local menu = {
        { header = 'Vehicle Diagnostics', txt = GetVehicleNumberPlateText(veh) or 'Unknown', isMenuHeader = true },
        { header = 'Overall Condition', txt = string.format('Engine %d%% • Body %d%% • Tank %d%%', engineHealth, bodyHealth, tankHealth), isMenuHeader = true }
    }

    -- Helper to add part entries
    local function addPartEntry(ruleKey, label, hp)
        hp = math.floor(tonumber(hp) or 0)
        hp = math.max(0, math.min(100, hp))
        
        local needed = partsNeededForRepair(ruleKey, hp)
        needed = math.floor(tonumber(needed) or 0)
        
        menu[#menu+1] = {
            header = string.format('%s — %d%%', label, hp),
            txt = string.format('Health: %d%%  •  Needs: %d parts', hp, needed),
            params = {}
        }
    end

    -- Engine & Body
    addPartEntry('engine_part', DiagnosticLabels.engine_part or 'Engine', health.engine_overall)
    addPartEntry('body_part', DiagnosticLabels.body_part or 'Body', health.body_overall)

    -- Electrical System
    addPartEntry('alternator', DiagnosticLabels.alternator, health.alternator)
    addPartEntry('carbattery', DiagnosticLabels.carbattery, health.carbattery)

    -- Engine Components
    addPartEntry('sparkplugs', DiagnosticLabels.sparkplugs, health.sparkplugs)
    addPartEntry('engine_oil', DiagnosticLabels.engine_oil, health.engine_oil)
    addPartEntry('oil_filter', DiagnosticLabels.oil_filter, health.oil_filter)

    -- Braking System
    addPartEntry('brakes', DiagnosticLabels.brakes, health.brakes)

    -- Suspension / Axle
    addPartEntry('susp_arm', DiagnosticLabels.susp_arm, health.susp_arm)
    addPartEntry('axleparts', DiagnosticLabels.axleparts, health.axleparts)

    -- Tires
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
                txt = 'Health: 0%  •  Needs: 1 tire',
                params = {}
            }
        end
    end

    if burstCount == 0 then
        menu[#menu+1] = {
            header = 'Tires — OK',
            txt = 'No tires need replacement',
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

-- NEW: Clean up clipboard when menu closes
RegisterNetEvent('qb-menu:client:closeMenu', function()
    if currentClipboard and DoesEntityExist(currentClipboard) then
        print('[TOOLS DEBUG] Cleaning up clipboard')
        local ped = PlayerPedId()
        ClearPedTasks(ped)
        DeleteEntity(currentClipboard)
        currentClipboard = nil
    end
end)

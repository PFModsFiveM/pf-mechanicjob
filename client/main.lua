local QBCore = exports['qb-core']:GetCoreObject()

-- ======================================================================
-- STATE
-- ======================================================================
local tabletOpen = false
local JobBlips, SpawnedJobVehs, PoppedWheels = {}, {}, {}

-- ======================================================================
-- CONFIG (client side mirrors)
-- ======================================================================
local POS_Categories = { "Repairs", "Cosmetics", "Performance" } -- UI only; prices come from server

-- ======================================================================
-- ANIM + PTFX
-- ======================================================================
local function startMechanicAnim(ped)
    if Config.UseEmoteCommand then ExecuteCommand('e mechanic2'); return end
    RequestAnimDict(Config.FallbackAnim.dict)
    while not HasAnimDictLoaded(Config.FallbackAnim.dict) do Wait(0) end
    TaskPlayAnim(ped, Config.FallbackAnim.dict, Config.FallbackAnim.name, 8.0, -8.0, -1, Config.FallbackAnim.flag or 49, 0, false, false, false)
end
local function stopMechanicAnim(ped)
    if Config.UseEmoteCommand then ExecuteCommand('e c'); return end
    ClearPedTasks(ped)
end
local function loadPtfx(dict)
    RequestNamedPtfxAsset(dict)
    local tries = 0
    while not HasNamedPtfxAssetLoaded(dict) and tries < 200 do Wait(5) tries = tries + 1 end
    return HasNamedPtfxAssetLoaded(dict)
end
local function playSprayFx(ped)
    local d1 = Config.SprayFx.primary.dict
    local n1 = Config.SprayFx.primary.name
    local s1 = Config.SprayFx.primary.scale or 1.0
    local ok = loadPtfx(d1)
    local dict, name, scale = d1, n1, s1
    if not ok then
        local d2 = Config.SprayFx.backup.dict
        if loadPtfx(d2) then dict = Config.SprayFx.backup.dict name = Config.SprayFx.backup.name scale = Config.SprayFx.backup.scale or 0.8 else return nil end
    end
    UseParticleFxAssetNextCall(dict)
    local hand = GetPedBoneIndex(ped, 57005)
    local fx = StartParticleFxLoopedOnEntityBone(name, ped, 0.18, 0.02, -0.03, 0.0, 0.0, 90.0, hand, scale, false, false, false)
    return fx, dict
end
local function stopSprayFx(fx, dict)
    if fx then StopParticleFxLooped(fx, false) end
    if dict then RemoveNamedPtfxAsset(dict) end
end

-- ======================================================================
-- VEH HELPERS
-- ======================================================================
local WheelBones = { 'wheel_lf','wheel_rf','wheel_lr','wheel_rr' }

local function GetNearbyVehicle(radius)
    local ped = PlayerPedId()
    local pcoords = GetEntityCoords(ped)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and DoesEntityExist(veh) then return veh, 0.0 end
    radius = radius or 6.0
    local candidate = GetClosestVehicle(pcoords.x, pcoords.y, pcoords.z, radius, 0, 70)
    if candidate ~= 0 and DoesEntityExist(candidate) then
        local vcoords = GetEntityCoords(candidate)
        local dist = #(pcoords - vcoords)
        if dist <= radius then return candidate, dist end
    end
    return 0, -1
end

local function isNPCJobVehicle(veh)
    local ent = Entity(veh)
    if not ent or not ent.state then return false end
    return ent.state.pf_jobId and true or false
end

local function wheelCoords(veh)
    local coords = {}
    for idx, b in ipairs(WheelBones) do
        local i = GetEntityBoneIndexByName(veh, b)
        if i ~= -1 then coords[idx-1] = GetWorldPositionOfEntityBone(veh, i) end
    end
    return coords
end

local function nearestWheelIndex(ped, veh)
    local coords = wheelCoords(veh)
    local p = GetEntityCoords(ped)
    local best, bestIdx = 9999, -1
    for idx=0,3 do
        local w = coords[idx]
        if w then
            local d = #(p - w)
            if d < best then best = d; bestIdx = idx end
        end
    end
    return bestIdx, best
end

local function fixVisuals(veh)
    -- hard fix visuals; keeps mod kit intact
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    SetVehicleDirtLevel(veh, 0.0)
    WashDecalsFromVehicle(veh, 1.0)
    SetVehicleUndriveable(veh, false)
end

-- ======================================================================
-- TABLET / NUI
-- ======================================================================
RegisterNetEvent('pf_mech:openTablet', function()
    if tabletOpen then return end
    tabletOpen = true
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end

    QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(data)
        -- also preload POS catalog and business info
        QBCore.Functions.TriggerCallback('pf_mech:pos:getCatalog', function(cat)
            QBCore.Functions.TriggerCallback('pf_mech:biz:getInfo', function(biz)
                SendNUIMessage({ action = 'open', payload = { dash = data or {}, pos = cat or {}, biz = biz or {} } })
            end)
        end)
    end)
end)

RegisterCommand('mechtab', function() TriggerEvent('pf_mech:openTablet') end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    tabletOpen = false
    cb('ok'); SendNUIMessage({ action = 'close' })
end)

-- NUI JOBS
RegisterNUICallback('acceptJob', function(data, cb) TriggerServerEvent('pf_mech:acceptJob', data.id); cb('ok') end)
RegisterNUICallback('startJob',  function(data, cb) TriggerServerEvent('pf_mech:startJob',  data.id); cb('ok') end)
RegisterNUICallback('finishJob', function(data, cb) TriggerServerEvent('pf_mech:finishJob', data.id, data.quality or 80); cb('ok') end)
RegisterNUICallback('orderParts',function(data, cb) TriggerServerEvent('pf_mech:orderParts',data.items or {}); cb('ok') end)
RegisterNUICallback('toggleNPC', function(data, cb) TriggerServerEvent('pf_mech:npc:toggle', data and data.enabled or false); cb('ok') end)

-- NUI POS
RegisterNUICallback('pos:getNearby', function(_, cb)
    local ped = PlayerPedId()
    local myCoords = GetEntityCoords(ped)
    local list = {}
    for _, pid in ipairs(GetActivePlayers()) do
        local src = GetPlayerServerId(pid)
        if src ~= GetPlayerServerId(PlayerId()) then
            local pPed = GetPlayerPed(pid)
            local d = #(GetEntityCoords(pPed) - myCoords)
            if d <= 5.0 then
                local name = GetPlayerName(pid) or ('ID '..src)
                list[#list+1] = { src = src, name = name }
            end
        end
    end
    cb(list)
end)

RegisterNUICallback('pos:requestCharge', function(data, cb)
    -- data: targetSrc, cart (items[], subtotal, tax, total)
    TriggerServerEvent('pf_mech:pos:chargePlayer', data.targetSrc, data.cart)
    cb('ok')
end)

RegisterNetEvent('pf_mech:jobsUpdate', function()
    if not tabletOpen then return end
    QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(data)
        SendNUIMessage({ action = 'jobs:update', payload = { jobsNew = data.jobsNew, jobsActive = data.jobsActive, profile = data.profile, thresholds = data.thresholds } })
    end)
end)

RegisterNetEvent('pf_mech:stockUpdate', function()
    if not tabletOpen then return end
    QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(data)
        SendNUIMessage({ action = 'stock:update', payload = { stock = data.stock } })
    end)
end)

RegisterNetEvent('pf_mech:client:newJob', function(info)
    PlaySoundFrontend(-1, "SELECT", "HUD_FREEMODE_SOUNDSET", true)
    TriggerEvent('QBCore:Notify', ('New NPC work order: %s • %s'):format(string.upper(info.type or ''), info.plate or ''), 'primary')
    TriggerEvent('pf_mech:jobsUpdate')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
        SendNUIMessage({ action = 'close' })
    end
end)

-- ======================================================================
-- CUSTOMER PAYMENT UI
-- ======================================================================
RegisterNetEvent('pf_mech:pos:openPayment', function(invoice)
    -- invoice: id, sellerName, businessName, items[], subtotal, tax, total
    SetNuiFocus(true, true)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({ action = 'pos:payPrompt', payload = invoice })
end)

RegisterNUICallback('pos:customerPay', function(data, cb)
    -- data: invoiceId, method ("cash"/"card"), accept (bool)
    TriggerServerEvent('pf_mech:pos:customerPay', data.invoiceId, data.method, data.accept)
    cb('ok')
    -- Close their UI
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then SetNuiFocusKeepInput(false) end
    SendNUIMessage({ action = 'close' })
end)

-- ======================================================================
-- NPC SPAWN/BLIPS
-- ======================================================================
RegisterNetEvent('pf_mech:client:spawnNPCVeh', function(d)
    local model = joaat(d.model or 'sultan')
    RequestModel(model) while not HasModelLoaded(model) do Wait(0) end
    local veh = CreateVehicle(model, d.coords.x, d.coords.y, d.coords.z, d.coords.h or 0.0, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, d.plate or ('NPC' .. math.random(100, 999)))
    SetEntityAsMissionEntity(veh, true, true)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    SetNetworkIdCanMigrate(netId, true)
    SetVehicleEngineHealth(veh, 700.0)
    local ent = Entity(veh)
    if ent and ent.state then ent.state:set('pf_jobId', d.id, true) end
    local blip = AddBlipForEntity(veh)
    SetBlipSprite(blip, 225); SetBlipScale(blip, 0.85); SetBlipColour(blip, 26)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentString(d.name or 'Work Order'); EndTextCommandSetBlipName(blip)
    JobBlips[d.id] = blip; SpawnedJobVehs[d.id] = veh
    PoppedWheels[d.id] = {}
    if (d.popTires or 0) > 0 then
        local indices = {0,1,4,5}
        local picked = {}
        while #picked < math.min(d.popTires, 2) and #indices > 0 do
            local i = math.random(#indices)
            picked[#picked+1] = table.remove(indices, i)
        end
        for _, idx in ipairs(picked) do
            SetVehicleTyreBurst(veh, idx, true, 1000.0)
            PoppedWheels[d.id][idx] = true
        end
    end
    local x, y, z = table.unpack(GetEntityCoords(veh))
    TriggerServerEvent('pf_mech:npcVehSpawned', { id = d.id, netId = netId, x = x, y = y, z = z, h = d.coords.h or 0.0 })
end)

RegisterNetEvent('pf_mech:client:clearJobBlip', function(jobId)
    local blip = JobBlips[jobId]; if blip and DoesBlipExist(blip) then RemoveBlip(blip) end; JobBlips[jobId] = nil
    local veh = SpawnedJobVehs[jobId]; if veh and DoesEntityExist(veh) then DeleteVehicle(veh) end; SpawnedJobVehs[jobId] = nil
    PoppedWheels[jobId] = nil
end)

RegisterNetEvent('pf_mech:client:fixTire', function(netId, wheelIndex)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh ~= 0 and DoesEntityExist(veh) then SetVehicleTyreFixed(veh, wheelIndex) end
end)

-- ======================================================================
-- NPC PART INSTALL
-- ======================================================================
RegisterNetEvent('pf_mech:client:usePart', function(data)
    local ped = PlayerPedId()
    local veh, _ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify', 'No vehicle nearby', 'error') end

    local jobId = Entity(veh) and Entity(veh).state and Entity(veh).state.pf_jobId or nil
    if not jobId then return TriggerEvent('QBCore:Notify', 'This vehicle is not part of an active job', 'error') end

    local part = data and data.part_id or nil
    if not part then return end

    if part == 'paint_kit' then
        local menu = { { header = 'Select Paint Color', isMenuHeader = true } }
        for key, info in pairs(Config.PaintPalette) do
            menu[#menu + 1] = { header = info.name, txt = ('%d, %d, %d'):format(info.r, info.g, info.b), params = { event = 'pf_mech:client:_paintSelect', args = { jobId = jobId, colorKey = key } } }
        end
        menu[#menu + 1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        exports['qb-menu']:openMenu(menu)
        return
    end

    local label = ({
        oil_filter = 'Installing Oil Filter',
        engine_oil = 'Adding Engine Oil',
        brake_pads = 'Replacing Brake Pads',
        susp_arm   = 'Replacing Suspension Arm',
        tire_new   = 'Mounting New Tire',
    })[part] or 'Working'

    local duration = ({ oil_filter=5000, engine_oil=4000, brake_pads=5500, susp_arm=6500, tire_new=6500 })[part] or 5000

    local okPos = false
    if part == 'oil_filter' or part == 'engine_oil' then
        local bone = GetEntityBoneIndexByName(veh, 'bonnet')
        local front = bone ~= -1 and GetWorldPositionOfEntityBone(veh, bone) or GetOffsetFromEntityInWorldCoords(veh, 0.0, 2.0, 0.8)
        okPos = #(GetEntityCoords(ped) - front) <= 2.2
        if not okPos then return TriggerEvent('QBCore:Notify', 'Move to the front of the car', 'error') end
    elseif part == 'tire_new' then
        local idx, dist = nearestWheelIndex(ped, veh)
        if idx == -1 or dist > 2.0 then return TriggerEvent('QBCore:Notify', 'Move near a wheel', 'error') end
        local jid = Entity(veh).state.pf_jobId; if not (PoppedWheels[jid] and PoppedWheels[jid][idx]) then return TriggerEvent('QBCore:Notify', 'This wheel does not need a tire', 'error') end
    else
        local idx, dist = nearestWheelIndex(ped, veh)
        if idx == -1 or dist > 2.0 then return TriggerEvent('QBCore:Notify', 'Move near a wheel', 'error') end
    end

    startMechanicAnim(ped)
    QBCore.Functions.Progressbar('pf_install_' .. part, label, duration, false, true,
        { disableMovement = true, disableCombat = true, disableCarMovement = true },
        {}, {}, {},
        function()
            stopMechanicAnim(ped)
            if part == 'tire_new' then
                local idx = nearestWheelIndex(ped, veh)
                if idx and idx >= 0 then
                    SetVehicleTyreFixed(veh, idx)
                    local jid = Entity(veh).state.pf_jobId
                    if PoppedWheels[jid] then PoppedWheels[jid][idx] = nil end
                    TriggerServerEvent('pf_mech:server:fixTire', NetworkGetNetworkIdFromEntity(veh), idx)
                end
            end
            TriggerServerEvent('pf_mech:installPart', { id = jobId, part_id = part, netId = NetworkGetNetworkIdFromEntity(veh) })
        end,
        function() stopMechanicAnim(ped); TriggerEvent('QBCore:Notify', 'Cancelled', 'error') end
    )
end)

RegisterNetEvent('pf_mech:client:_paintSelect', function(data)
    local ped = PlayerPedId()
    local veh, _ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify', 'No vehicle nearby', 'error') end
    local jobId = Entity(veh) and Entity(veh).state and Entity(veh).state.pf_jobId or nil
    if not jobId or jobId ~= data.jobId then return TriggerEvent('QBCore:Notify', 'This vehicle is not part of that job', 'error') end
    local color = Config.PaintPalette[data.colorKey]; if not color then return end
    if #(GetEntityCoords(ped) - GetEntityCoords(veh)) > 2.6 then return TriggerEvent('QBCore:Notify', 'Stand closer to the vehicle', 'error') end
    startMechanicAnim(ped)
    local fx, fxDict = playSprayFx(ped)
    QBCore.Functions.Progressbar('pf_paint_job', ('Painting %s'):format(color.name), 6000, false, true, { disableMovement=true, disableCombat=true, disableCarMovement=true }, {}, {}, {},
        function()
            stopSprayFx(fx, fxDict); stopMechanicAnim(ped)
            SetVehicleModKit(veh, 0)
            SetVehicleCustomPrimaryColour(veh, color.r, color.g, color.b)
            SetVehicleCustomSecondaryColour(veh, color.r, color.g, color.b)
            TriggerServerEvent('pf_mech:applyPaint', { id = jobId, colorKey = data.colorKey })
        end,
        function() stopSprayFx(fx, fxDict); stopMechanicAnim(ped); TriggerEvent('QBCore:Notify', 'Cancelled', 'error') end
    )
end)

-- ======================================================================
-- PLAYER TOOLS: scan, toolbox, consumables
-- ======================================================================
local function getPerfLevels(veh)
    SetVehicleModKit(veh, 0)
    local engines = GetVehicleMod(veh, 11) + 1
    local brakes  = GetVehicleMod(veh, 12) + 1
    local trans   = GetVehicleMod(veh, 13) + 1
    local susp    = GetVehicleMod(veh, 15) + 1
    local armor   = GetVehicleMod(veh, 16) + 1
    local turbo   = IsToggleModOn(veh, 18)
    local xenon   = IsToggleModOn(veh, 22)
    local drift   = (GetIsVehicleDriftTyresEnabled and GetIsVehicleDriftTyresEnabled(veh)) or false
    local burst   = not GetVehicleTyresCanBurst(veh)
    return engines, brakes, trans, susp, armor, turbo, xenon, drift, burst
end

local function vehModelName(veh)
    local hash = GetEntityModel(veh)
    local label = GetDisplayNameFromVehicleModel(hash)
    if label and label ~= 'CARNOTFOUND' then
        local txt = GetLabelText(label)
        if txt ~= 'NULL' then return txt end
    end
    return label or ('0x' .. string.format('%X', hash))
end

local function fuelLevel(veh)
    local fuel = nil
    if exports['LegacyFuel'] and exports['LegacyFuel'].GetFuel then
        fuel = exports['LegacyFuel']:GetFuel(veh)
    elseif Entity(veh).state.fuel then
        fuel = Entity(veh).state.fuel
    end
    return fuel and math.floor(fuel) or nil
end

local function showDiagnosticMenu(veh)
    local plate = GetVehicleNumberPlateText(veh)
    local name  = vehModelName(veh)
    local eng   = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh) / 10)))
    local body  = math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh) / 10)))
    local fuel  = fuelLevel(veh)
    local e,b,t,s,a,turbo,xenon,drift,proof = getPerfLevels(veh)

    local menu = {
        { header = name, txt = ('Plate: %s%s'):format(plate or 'N/A', fuel and (' | Fuel: '..fuel..'%') or ''), isMenuHeader = true },
        { header = ('Engine - %d%%'):format(eng),  txt = 'Health' },
        { header = ('Body - %d%%'):format(body),   txt = 'Health' },
        { header = ('Engine Level: %d'):format(math.max(e,0)), txt = '' },
        { header = ('Brakes Level: %d'):format(math.max(b,0)), txt = '' },
        { header = ('Transmission Level: %d'):format(math.max(t,0)), txt = '' },
        { header = ('Suspension Level: %d'):format(math.max(s,0)), txt = '' },
        { header = ('Armor Level: %d'):format(math.max(a,0)), txt = '' },
        { header = ('Turbo: %s'):format(turbo and 'true' or 'false'), txt = '' },
        { header = ('Xenon: %s'):format(xenon and 'true' or 'false'), txt = '' },
        { header = ('Drift Tyres: %s'):format(drift and 'true' or 'false'), txt = '' },
        { header = ('Bulletproof Tyres: %s'):format(proof and 'true' or 'false'), txt = '' },
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('pf_mech:client:mechanicTools', function()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return TriggerEvent('QBCore:Notify','Exit the vehicle first','error') end
    local veh, _ = GetNearbyVehicle(6.0); if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    if isNPCJobVehicle(veh) then return TriggerEvent('QBCore:Notify','Use job parts for NPC vehicles','error') end
    for d=0,5 do SetVehicleDoorOpen(veh, d, false, false) end
    SetVehicleDoorOpen(veh, 4, false, false); SetVehicleDoorOpen(veh, 5, false, false)
    startMechanicAnim(ped)
    QBCore.Functions.Progressbar('pf_mech_inspect', 'Inspecting vehicle', 4000, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
        function() stopMechanicAnim(ped); showDiagnosticMenu(veh) end,
        function() stopMechanicAnim(ped) end
    )
    SetTimeout(15000, function()
        if DoesEntityExist(veh) then for d=0,5 do SetVehicleDoorShut(veh, d, false) end end
    end)
end)

RegisterCommand('scanveh', function()
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    showDiagnosticMenu(veh)
end)

-- Toolbox menu
RegisterNetEvent('pf_mech:client:toolbox', function()
    local ped = PlayerPedId()
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    if isNPCJobVehicle(veh) then return TriggerEvent('QBCore:Notify','Use job parts for NPC vehicles','error') end
    local eng = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
    local body= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
    local function repairAction(label, item, cbApply)
        return { header = label, txt = ('Requires: %s'):format(item), params = { event = 'pf_mech:client:_toolboxRepair', args = { item = item, apply = cbApply } } }
    end
    local menu = {
        { header = 'Toolbox', txt = 'Select system to repair', isMenuHeader = true },
        repairAction(('Engine - %d%%'):format(eng), 'engine_part', function()
            SetVehicleEngineHealth(veh, 1000.0); SetVehiclePetrolTankHealth(veh, 1000.0); fixVisuals(veh)
        end),
        repairAction(('Body - %d%%'):format(body), 'body_part', function()
            SetVehicleBodyHealth(veh, 1000.0); fixVisuals(veh)
        end),
        repairAction('Oil Level', 'newoil', function() SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 850.0)) end),
        repairAction('Spark Plugs', 'sparkplugs', function() SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 900.0)) end),
        repairAction('Car Battery', 'carbattery', function() SetVehicleLights(veh, 0) end),
        repairAction('Axle Shaft', 'axleparts', function() end),
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } },
    }
    exports['qb-menu']:openMenu(menu)
end)

RegisterNetEvent('pf_mech:client:_toolboxRepair', function(data)
    local ped = PlayerPedId()
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    local item = data.item
    QBCore.Functions.TriggerCallback('pf_mech:consumeItem', function(ok)
        if not ok then return TriggerEvent('QBCore:Notify','Missing required item','error') end
        startMechanicAnim(ped)
        QBCore.Functions.Progressbar('pf_fix_'..item, 'Repairing', 3500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
            function()
                stopMechanicAnim(ped)
                if type(data.apply) == 'function' then data.apply() end
                TriggerEvent('QBCore:Notify','Repaired','success')
            end,
            function() stopMechanicAnim(ped) end
        )
    end, item, 1)
end)

-- DIRECT USE of repair consumables
RegisterNetEvent('pf_mech:client:useRepairItem', function(item)
    local ped = PlayerPedId()
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    if isNPCJobVehicle(veh) then return TriggerEvent('QBCore:Notify','Use job parts for NPC vehicles','error') end
    local label = ({
        engine_part='Repairing Engine',
        body_part  ='Repairing Body',
        newoil     ='Adding Oil',
        sparkplugs ='Replacing Spark Plugs',
        carbattery ='Replacing Battery',
        axleparts  ='Repairing Axle'
    })[item] or 'Repairing'
    QBCore.Functions.TriggerCallback('pf_mech:consumeItem', function(ok)
        if not ok then return TriggerEvent('QBCore:Notify','Missing required item','error') end
        startMechanicAnim(ped)
        QBCore.Functions.Progressbar('pf_use_'..item, label, 3500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
            function()
                stopMechanicAnim(ped)
                if item == 'engine_part' then
                    SetVehicleEngineHealth(veh, 1000.0); SetVehiclePetrolTankHealth(veh, 1000.0); fixVisuals(veh)
                elseif item == 'body_part' then
                    SetVehicleBodyHealth(veh, 1000.0); fixVisuals(veh)
                elseif item == 'newoil' then
                    SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 850.0))
                elseif item == 'sparkplugs' then
                    SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 900.0))
                elseif item == 'carbattery' then
                    SetVehicleLights(veh, 0)
                end
                TriggerEvent('QBCore:Notify','Repair complete','success')
            end,
            function() stopMechanicAnim(ped) end
        )
    end, item, 1)
end)

-- ======================================================================
-- COSMETIC/PERFORMANCE (friendly names)
-- ======================================================================
local CosMap = {
    bumper       = {1,2},
    exhaust      = {4},
    externals    = {6,8,9},
    hood         = {7},
    horn         = {14},
    internals    = {27,28,29,30,31,32,33,34,35,36,39,40,41},
    livery       = {48},
    rims         = {23},
    roof         = {10},
    rollcage     = {5},
    seat         = {32},
    skirts       = {3},
    spoiler      = {0},
    tint_supplies= 'tint',
    customplate  = 'plate',
}
local CatNames = {
    bumper = { [1]='Front Bumper', [2]='Rear Bumper' },
    exhaust = { [4]='Exhaust' },
    externals = { [6]='Grille', [8]='Left Fender', [9]='Right Fender' },
    hood = { [7]='Hood' },
    horn = { [14]='Horn' },
    internals = {
        [27]='Trim A', [28]='Ornaments', [29]='Dashboard', [30]='Dials',
        [31]='Door Speakers', [32]='Seats', [33]='Steering Wheel',
        [34]='Shifter', [35]='Plaques', [36]='Speakers',
        [39]='Engine Bay', [40]='Air Filter', [41]='Strut Bar'
    },
    livery = { [48]='Livery' },
    rims   = { [23]='Wheels' },
    roof   = { [10]='Roof' },
    rollcage = { [5]='Roll Cage' },
    seat   = { [32]='Seats' },
    skirts = { [3]='Side Skirts' },
    spoiler= { [0]='Spoiler' },
}

local function setModMenu(veh, modType, catLabel)
    SetVehicleModKit(veh, 0)
    local count = GetNumVehicleMods(veh, modType)
    if count <= 0 then return TriggerEvent('QBCore:Notify','No options for this vehicle','error') end
    local title = catLabel or ('Mod %d'):format(modType)
    local items = {
        { header = title, txt = 'Select option', isMenuHeader = true },
        { header = 'Stock', params = { event='pf_mech:client:_applyMod', args={ veh=VehToNet(veh), t=modType, idx=-1 } } }
    }
    for i=0,count-1 do
        local label = GetModTextLabel(veh, modType, i)
        if label and label ~= '' then label = GetLabelText(label) end
        if not label or label == '' or label == 'NULL' then label = ('Option %d'):format(i+1) end
        items[#items+1] = { header = label, params = { event='pf_mech:client:_applyMod', args={ veh=VehToNet(veh), t=modType, idx=i } } }
    end
    items[#items+1] = { header = 'Close', params = { event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(items)
end

RegisterNetEvent('pf_mech:client:_applyMod', function(d)
    local veh = NetToVeh(d.veh)
    if veh == 0 then return end
    SetVehicleModKit(veh, 0)
    QBCore.Functions.Progressbar('pf_fit_mod', 'Fitting part', 3500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
        function()
            if d.t == 18 or d.t == 22 or d.t == 20 then
                ToggleVehicleMod(veh, d.t, d.idx ~= -1)
            else
                SetVehicleMod(veh, d.t, d.idx, false)
            end
            TriggerEvent('QBCore:Notify','Installed','success')
        end, function() end
    )
end)

RegisterNetEvent('pf_mech:client:cosmeticMenu', function(item)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return TriggerEvent('QBCore:Notify','Exit the vehicle first','error') end
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    if isNPCJobVehicle(veh) then return TriggerEvent('QBCore:Notify','NPC jobs do not allow full cosmetics','error') end
    local map = CosMap[item]; if not map then return TriggerEvent('QBCore:Notify','Unsupported item','error') end

    if map == 'tint' then
        local tints = {
            { idx=0, name='None' }, { idx=1, name='Pure Black' }, { idx=2, name='Dark Smoke' },
            { idx=3, name='Light Smoke' }, { idx=4, name='Stock' }, { idx=5, name='Limo' }, { idx=6, name='Green' }
        }
        local menu = { { header = 'Window Tint', isMenuHeader = true } }
        for _, t in ipairs(tints) do
            menu[#menu+1] = { header = t.name, params = { event='pf_mech:client:_setTint', args={ veh=VehToNet(veh), tint=t.idx } } }
        end
        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
        return exports['qb-menu']:openMenu(menu)
    elseif map == 'plate' then
        if GetResourceState('qb-input') ~= 'started' then return TriggerEvent('QBCore:Notify','qb-input not found','error') end
        local dialog = exports['qb-input']:ShowInput({ header='Custom Plate', submitText='Apply', inputs={ { type='text', isRequired=true, name='plate', text='Plate (max 8)' } } })
        if dialog and dialog.plate then
            local text = string.upper(string.sub(dialog.plate, 1, 8))
            QBCore.Functions.Progressbar('pf_plate', 'Fitting plate', 2500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
                function() SetVehicleNumberPlateText(veh, text); TriggerEvent('QBCore:Notify','Plate applied','success') end, function() end)
        end
        return
    end

    local list = { { header = 'Select Category', isMenuHeader = true } }
    for _, modType in ipairs(map) do
        local friendly = (CatNames[item] and CatNames[item][modType]) or ('Mod %d'):format(modType)
        list[#list+1] = { header = friendly, params = { event='pf_mech:client:_openModType', args={ veh=VehToNet(veh), t=modType, label=friendly } } }
    end
    list[#list+1] = { header = 'Close', params = { event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(list)
end)

RegisterNetEvent('pf_mech:client:_openModType', function(d)
    local veh = NetToVeh(d.veh)
    if veh == 0 then return end
    setModMenu(veh, d.t, d.label)
end)

RegisterNetEvent('pf_mech:client:_setTint', function(d)
    local veh = NetToVeh(d.veh)
    if veh == 0 then return end
    QBCore.Functions.Progressbar('pf_tint', 'Applying tint', 2500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
        function() SetVehicleWindowTint(veh, d.tint or 0) end, function() end
    )
end)

-- Performance
local function applyPerf(veh, name)
    SetVehicleModKit(veh, 0)
    local map = {
        engine1={11,0}, engine2={11,1}, engine3={11,2}, engine4={11,3}, engine5={11,4},
        brakes1={12,0}, brakes2={12,1}, brakes3={12,2},
        transmission1={13,0}, transmission2={13,1}, transmission3={13,2}, transmission4={13,3},
        suspension1={15,0}, suspension2={15,1}, suspension3={15,2}, suspension4={15,3}, suspension5={15,4},
        car_armor={16,4},
        turbo={'toggle',18,true},
        headlights={'toggle',22,true},
        drifttires={'drift',true},
        bprooftires={'bp',true},
    }
    local def = map[name]
    if not def then return false end
    if def[1] == 'toggle' then
        ToggleVehicleMod(veh, def[2], def[3] and true or false)
    elseif def[1] == 'drift' then
        if SetDriftTyresEnabled then SetDriftTyresEnabled(veh, true) end
    elseif def[1] == 'bp' then
        SetVehicleTyresCanBurst(veh, false)
    else
        SetVehicleMod(veh, def[1], def[2], false)
    end
    return true
end

RegisterNetEvent('pf_mech:client:perfApply', function(item)
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return TriggerEvent('QBCore:Notify','Exit the vehicle first','error') end
    local veh,_ = GetNearbyVehicle(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
    if isNPCJobVehicle(veh) then return TriggerEvent('QBCore:Notify','NPC jobs do not allow full upgrades','error') end
    QBCore.Functions.Progressbar('pf_mod_perf', 'Installing performance part', 3500, false, true, { disableMovement=true, disableCombat=true }, {}, {}, {},
        function()
            local ok = applyPerf(veh, item)
            if ok then TriggerEvent('QBCore:Notify','Installed','success') else TriggerEvent('QBCore:Notify','Unsupported','error') end
        end, function() end
    )
end)

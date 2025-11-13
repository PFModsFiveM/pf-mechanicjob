-- pf-mechanicjob • CLIENT (full file)
local QBCore = exports['qb-core']:GetCoreObject()

-- Helper: check if player is a mechanic
local function isPlayerMechanic()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config.IsMechanicJob(PlayerData.job.name)
end

-- Helper: Check if player has toolbox (required for all work)
local function hasToolbox(callback)
    QBCore.Functions.TriggerCallback('pf_mech:hasToolbox', function(has)
        if not has then
            QBCore.Functions.Notify(L('need_toolbox'), 'error')
        end
        callback(has)
    end)
end

local JOB = Config.JobName or 'mechanic'

local UI_OPEN = false
local jobBlips, spawnedNPCVeh = {}

-- Tablet animation variables
local tabletDict = "amb@code_human_in_bus_passenger_idles@female@tablet@idle_a"
local tabletAnim = "idle_a"
local tabletProp = `prop_cs_tablet`
local tabletBone = 60309
local tabletObj = nil

-- NEW: Global clipboard tracker for cleanup
currentClipboard = nil

-- Register useable item
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    QBCore.Functions.TriggerCallback('QBCore:Server:GetObject', function(obj)
        QBCore = obj
        QBCore.Functions.GetPlayerData(function(PlayerData)
            PlayerJob = PlayerData.job
        end)
    end)
end)

-- Register tablet usage event
RegisterNetEvent('pf-mechanicjob:client:useMechTablet', function()
    if isPlayerMechanic() then
        TriggerEvent('pf_mech:openTablet')
    else
        QBCore.Functions.Notify(L('not_mechanic'), 'error')
    end
end)

-- ================== NUI helpers ==================
local function nui(a, p) SendNUIMessage({ action=a, payload=p }) end
local function setFocus(b) SetNuiFocus(b, b); SetNuiFocusKeepInput(false) end
local function openTablet(payload)
    RequestAnimDict(tabletDict)
    while not HasAnimDictLoaded(tabletDict) do Wait(100) end
    
    RequestModel(tabletProp)
    while not HasModelLoaded(tabletProp) do Wait(100) end

    local ped = PlayerPedId()
    tabletObj = CreateObject(tabletProp, 0.0, 0.0, 0.0, true, true, false)
    local bone = GetPedBoneIndex(ped, tabletBone)
    
    AttachEntityToEntity(tabletObj, ped, bone, 0.03, 0.002, -0.0, 10.0, 160.0, 0.0, true, true, false, true, 1, true)
    TaskPlayAnim(ped, tabletDict, tabletAnim, 8.0, -8.0, -1, 50, 0, false, false, false)
    
    UI_OPEN = true
    setFocus(true)
    nui('open', payload or {})
end
local function closeTablet()
    UI_OPEN = false
    setFocus(false)
    nui('close')
    
    local ped = PlayerPedId()
    ClearPedTasks(ped)
    
    if tabletObj then
        DeleteEntity(tabletObj)
        tabletObj = nil
    end
end

-- ================== small helpers ==================
local function nearbyVeh(radius)
  local ped = PlayerPedId()
  local pos = GetEntityCoords(ped)
  local veh = GetClosestVehicle(pos.x, pos.y, pos.z, radius or 6.0, 0, 70)
  if veh ~= 0 and DoesEntityExist(veh) then return veh end
  return 0
end
local function isNPCVeh(veh)
  local ent = Entity(veh)
  return ent and ent.state and ent.state.pf_jobId ~= nil
end

local function resourceActive(name)
  local st = GetResourceState(name)
  return st == 'started' or st == 'starting'
end

-- ================== progress bar (resilient) ==================
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

  -- 1) ox_lib
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

  -- 2) exports['progressbar']:Progress (qb-progressbar export flavor)
  if resourceActive('progressbar') then
    local exp = exports['progressbar']
    if exp and type(exp.Progress) == 'function' then
      local finished, cancelled = false, true
      exp:Progress({
        name = 'pf_mech_prog',
        duration = ms,
        label = label,
        useWhileDead = false,
        canCancel = true,
        controlDisables = { disableMovement=true, disableCarMovement=true, disableMouse=false, disableCombat=true },
        animation = dict and { animDict=dict, anim=anim, flags=49 } or nil,
      }, function(canc)
        cancelled = canc and true or false
        finished = true
      end)
      while not finished do Wait(25) end
      ClearPedTasks(ped)
      return not cancelled
    end
  end

  -- 3) QBCore.Functions.Progressbar (older qb-core flavor)
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

  -- 4) last-resort fallback: simple wait with controls disabled
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

local function timeForAction(action)
  local t = Config.ActionTimes or {}
  return t[action] or 4000
end

-- ================== open / commands ==================
RegisterCommand('mechtab', function() TriggerEvent('pf_mech:openTablet') end)
RegisterCommand('mechreset', function() closeTablet() end)

RegisterNetEvent('pf_mech:openTablet', function()
  if not isPlayerMechanic() then return end

  openTablet({})
  QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(dash)
    if not UI_OPEN or not dash then return end
    nui('jobs:update', {
      jobsNew    = dash.jobsNew or {},
      jobsActive = dash.jobsActive or {},
      profile    = dash.profile or {},
      thresholds = dash.thresholds or {}
    })
    nui('stock:update', { stock = dash.stock or {} })
  end)

  QBCore.Functions.TriggerCallback('pf_mech:pos:getCatalog', function(cat)
    if UI_OPEN and cat then nui('pos:catalog', cat) end
  end)
end)

-- ================== NUI Callbacks ==================
RegisterNUICallback('close', function(_, cb) closeTablet(); cb(true) end)
RegisterNUICallback('toggleNPC', function(data, cb) TriggerServerEvent('pf_mech:npc:toggle', data.enabled and true or false); cb(true) end)
RegisterNUICallback('acceptJob', function(data, cb) TriggerServerEvent('pf_mech:acceptJob', data.id); cb(true) end)
RegisterNUICallback('startJob',  function(data, cb) TriggerServerEvent('pf_mech:startJob', data.id); cb(true) end)
RegisterNUICallback('finishJob', function(data, cb) TriggerServerEvent('pf_mech:finishJob', data.id, data.quality or 80); cb(true) end)
RegisterNUICallback('orderParts',function(data, cb) TriggerServerEvent('pf_mech:orderParts', data.items or {}); cb(true) end)

-- NPC Jobs 

-- state
local npcOn = false
local onDuty = true  -- replace with your real on-duty flag if you have one

-- Called by NUI fetch(".../toggleNPC")
RegisterNUICallback('toggleNPC', function(data, cb)
    local want = data and data.enabled == true

    -- Optional: gate on duty
    if want and not onDuty then
        SendNUIMessage({ action = 'toast', payload = { text = 'You must be on duty to start Local Jobs.' } })
        cb('ok'); return
    end

    npcOn = want
    -- echo state back to UI immediately
    SendNUIMessage({ action = 'pf_mech:npcState', payload = { on = npcOn } })

    -- tell server
    TriggerServerEvent('pf_mech:npc:toggle', npcOn)

    cb('ok')
end)

-- ask server to (re)sync initial state when tablet opens
RegisterNUICallback('jobs:refresh', function(_, cb)
    TriggerServerEvent('pf_mech:npc:refresh')
    cb('ok')
end)

-- Server pushes job lists back
RegisterNetEvent('pf_mech:npc:updateJobs', function(payload)
    SendNUIMessage({ action = 'jobs:update', payload = payload })
end)

-- Optional simple debug hotkey
RegisterCommand('pf_npcdebug', function()
    print('npcOn=', npcOn)
end)

-- POS
RegisterNUICallback('pos:getNearby', function(_, cb)
  local ped = PlayerPedId()
  local my = GetEntityCoords(ped)
  local ids = {}
  for _, pid in ipairs(GetActivePlayers()) do
    local ped2 = GetPlayerPed(pid)
    if ped2 ~= ped then
      local d = #(GetEntityCoords(ped2) - my)
      if d <= 5.5 then ids[#ids+1] = GetPlayerServerId(pid) end
    end
  end
  QBCore.Functions.TriggerCallback('pf_mech:getPlayerNames', function(map)
    local out = {}
    for _, sid in ipairs(ids) do
      out[#out+1] = { src = sid, name = map[tostring(sid)] or ('ID '..sid) }
    end
    cb(out)
  end, ids)
end)
RegisterNUICallback('pos:requestCharge', function(data, cb)
  TriggerServerEvent('pf_mech:pos:chargePlayer', data.targetSrc or 0, data.cart or {})
  cb(true)
end)
RegisterNUICallback('pos:customerPay', function(data, cb)
  TriggerServerEvent('pf_mech:pos:customerPay', data.invoiceId, data.method, data.accept and true or false)
  cb(true)
  nui('pay:close')
end)
RegisterNetEvent('pf_mech:pos:openPayment', function(invoice)
  setFocus(true)
  SendNUIMessage({ action='pos:payPrompt', payload=invoice })
end)
RegisterNetEvent('pf_mech:pos:paid', function(selfCharge)
  if selfCharge then closeTablet() end
end)

-- Live refresh coming from server
RegisterNetEvent('pf_mech:jobsUpdate', function()
  if not UI_OPEN then return end
  QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(d)
    if not d then return end
    nui('jobs:update', {
      jobsNew    = d.jobsNew or {},
      jobsActive = d.jobsActive or {},
      profile    = d.profile or {},
      thresholds = d.thresholds or {}
    })
    nui('stock:update', { stock = d.stock or {} })
  end)
end)
RegisterNetEvent('pf_mech:stockUpdate', function()
  if not UI_OPEN then return end
  QBCore.Functions.TriggerCallback('pf_mech:getDashboard', function(d)
    if d then nui('stock:update', { stock = d.stock or {} }) end
  end)
end)

-- Only toast if it’s a job we can actually take
RegisterNetEvent('pf_mech:client:newJob', function(job)
  if UI_OPEN then
    SendNUIMessage({ action='toast', payload={ text=('NPC request: %s %s'):format(job.type or 'job', job.plate or '') }})
  end
end)

-- ================== NPC spawn/cleanup ==================
RegisterNetEvent('pf_mech:client:spawnNPCVeh', function(d)
  local model = joaat(d.model or 'sultan')
  RequestModel(model) while not HasModelLoaded(model) do Wait(0) end

  local x,y,z,h = d.coords.x, d.coords.y, d.coords.z, d.coords.h or 0.0
  local veh = CreateVehicle(model, x, y, z, h, true, true)
  SetEntityAsMissionEntity(veh, true, true)
  SetVehicleOnGroundProperly(veh)
  SetVehicleNumberPlateText(veh, d.plate or ('NPC'..math.random(100,999)))
  SetVehicleEngineHealth(veh, 700.0)

  local ent = Entity(veh); if ent and ent.state then ent.state:set('pf_jobId', d.id, true) end

  local pop = tonumber(d.popTires or 0) or 0
  if pop > 0 then
    local popped = 0
    for i=0,5 do
      if popped >= pop then break end
      SetVehicleTyreBurst(veh, i, true, 1000.0)
      popped = popped + 1
    end
  end

  local blip = AddBlipForEntity(veh)
  SetBlipSprite(blip, 225); SetBlipScale(blip, .85); SetBlipColour(blip, 26)
  BeginTextCommandSetBlipName('STRING'); AddTextComponentString(d.name or 'Work Order'); EndTextCommandSetBlipName(blip)
  jobBlips[d.id] = blip; spawnedNPCVeh[d.id] = veh

  local nx,ny,nz = table.unpack(GetEntityCoords(veh))
  TriggerServerEvent('pf_mech:npcVehSpawned', { id=d.id, netId=NetworkGetNetworkIdFromEntity(veh), x=nx, y=ny, z=nz, h=h })
end)
RegisterNetEvent('pf_mech:client:clearJobBlip', function(id)
  local blip = jobBlips[id]; if blip and DoesBlipExist(blip) then RemoveBlip(blip) end; jobBlips[id]=nil
  local veh = spawnedNPCVeh[id]; if veh and DoesEntityExist(veh) then DeleteVehicle(veh) end; spawnedNPCVeh[id]=nil
end)

-- ================== /scanveh ==================
local function vehModelName(veh)
  local hash = GetEntityModel(veh)
  local key = GetDisplayNameFromVehicleModel(hash)
  local txt = key and GetLabelText(key)
  if txt and txt ~= 'NULL' then return txt end
  return key or ('0x'..string.format('%X', hash))
end

-- Forward-declare helpers (move here so diagnostics handler can call them)
local function partsNeededForRepair(partKey, healthPercent)
    local rule = (Config.PartRules or {})[partKey] or {}
    local maxItems = tonumber(rule.max_items) or 0

    -- sensible defaults for known types if not declared in config
    if maxItems <= 0 then
        if partKey:match('engine') or rule.type == 'engine' then maxItems = 5 end
        if partKey == 'body_part' or rule.type == 'body' then maxItems = 5 end
        if partKey == 'sparkplugs' or rule.type == 'sparkplugs' then maxItems = 8 end
        if rule.type == 'battery' then maxItems = 1 end
        if rule.type == 'axle' then maxItems = 4 end
        if partKey == 'tire_new' then maxItems = 4 end
        if rule.type == 'oil' then maxItems = 1 end
    end

    -- clamp healthPercent
    healthPercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))

    -- parts needed = ceil( missingPercent * maxItems )
    if maxItems <= 0 then return 0 end
    local missingPercent = 100 - healthPercent
    local needed = math.ceil((missingPercent / 100) * maxItems)
    if needed < 0 then needed = 0 end
    if needed > maxItems then needed = maxItems end
    return needed
end

-- ADD: label for DPF
local DiagnosticLabels = {
    alternator = "Alternator",
    sparkplugs = "Spark Plugs",
    carbattery = "Car Battery",
    engine_oil = "Engine Oil",
    oil_filter = "Oil Filter",
    brakes = "Brake Pads",      -- NEW
    susp_arm = "Suspension Arm",
    axleparts = "Axle Parts",
    engine_part = "Engine Part",
    body_part = "Body Panel",
    tire_new = "Tire",
    dpf = "Diesel Particulate Filter"  -- NEW
}

-- NEW: helper to build DPF menu row
local function buildDPFMenuRow(veh)
    if not Config.IsDieselCandidate(veh) then return nil end
    local plate = GetVehicleNumberPlateText(veh)
    local removed = IsDPFRemoved(veh)
    if not removed then
        return {
            header = 'DPF (Installed)',
            txt = 'Remove to enable rolling coal',
            params = { event='pf_mech:dpf:clientRemove', args={ plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    else
        return {
            header = 'DPF (Removed)',
            txt = 'Install to disable rolling coal',
            params = { event='pf_mech:dpf:clientInstall', args={ plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    end
end

-- ================== diagnostics tool ==================
-- REPLACE diagnostics_tool use handling to show full menu + DPF option
AddEventHandler('QBCore:Client:UseItem', function(item)
    local name = item and item.name
    if not name then return end

    -- NEW: Toolbox handler - shows removable parts menu
    if name == 'mechanic_tools' or name == 'toolbox' then
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
        
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
        local menu = {
            { header = ('Toolbox • %s'):format(plate), isMenuHeader = true }
        }
        
        -- DPF removal option (only show for diesel)
        if Config.IsDieselCandidate(veh) then
            local dpfRemoved = IsDPFRemoved(veh)
            if not dpfRemoved then
                menu[#menu+1] = {
                    header = 'Remove DPF',
                    txt = 'Takes 6 seconds. Enables rolling coal',
                    params = { 
                        event = 'pf_mech:dpf:clientRemove', 
                        args = { plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } 
                    }
                }
            else
                menu[#menu+1] = {
                    header = 'DPF Already Removed',
                    txt = 'Use DPF item to reinstall',
                    params = {}
                }
            end
        else
            menu[#menu+1] = {
                header = 'DPF - Not Applicable',
                txt = 'Vehicle is not diesel',
                params = {}
            }
        end
        
        -- Future: Add more removable parts here (catalytic converter, muffler, etc)
        
        menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        exports['qb-menu']:openMenu(menu)
        return
    end

    if name == 'diagnostics_tool' then
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end

        -- Build basic diagnostics lines (engine/body) + DPF row if diesel
        local plate = GetVehicleNumberPlateText(veh)
        local engPct = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
        local bodyPct= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
        local menu = {
            { header = ('Diagnostics • %s'):format(plate or 'N/A'), isMenuHeader = true },
            { header = ('Engine - %d%%'):format(engPct), txt = 'Health' },
            { header = ('Body - %d%%'):format(bodyPct),  txt = 'Health' },
        }

        local dpfRow = buildDPFMenuRow(veh)
        if dpfRow then menu[#menu+1] = dpfRow end

        menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
        exports['qb-menu']:openMenu(menu)
        return
    end

    if name == Config.DPFItem then
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
        if not Config.IsDieselCandidate(veh) then QBCore.Functions.Notify('Not a diesel vehicle','error'); return end
        if not IsDPFRemoved(veh) then QBCore.Functions.Notify('DPF already installed','error'); return end
        local plate = GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
        TriggerEvent('pf_mech:dpf:clientInstall', { plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) })
        return
    end

    -- cosmetic items (mods)
    if name == "spoiler" or name == "bumper" or name == "skirts" or name == "exhaust"
       or name == "rollcage" or name == "hood" or name == "roof" then
        -- This will be caught by server CreateUseableItem instead
        return
    end
end)

-- NEW: helper to check if player is within radius of a target point
local function playerNear(target, radius)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    return (#(p - target)) <= (radius or 2.5)
end

-- NEW: tint picker and applier
local function openTintPicker(veh)
    if not DoesEntityExist(veh) then return end
    local opts = {
        { idx=0, label='None' },
        { idx=1, label='Pure Black' },
        { idx=2, label='Dark Smoke' },
        { idx=3, label='Light Smoke' },
        { idx=4, label='Stock' },
        { idx=5, label='Limo' },
        { idx=6, label='Green' },
    }
    local menu = { { header='Window Tint', isMenuHeader=true } }
    for _, o in ipairs(opts) do
        menu[#menu+1] = {
            header = o.label,
            txt = ('Apply tint %s'):format(o.label),
            params = {
                event = 'pf_mech:applyTint',
                args = { vehicle = NetworkGetNetworkIdFromEntity(veh), tint = o.idx }
            }
        }
    end
    menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('pf_mech:applyTint', function(args)
    local veh = NetworkGetEntityFromNetworkId(args.vehicle or 0)
    if not DoesEntityExist(veh) then QBCore.Functions.Notify('Vehicle not found', 'error'); return end
    if GetIsVehicleEngineRunning(veh) then QBCore.Functions.Notify('Turn engine off first', 'error'); return end
    
    -- NEW: Check for toolbox
    hasToolbox(function(has)
        if not has then return end

        QBCore.Functions.TriggerCallback('pf-mechanicjob:server:consumeItem', function(ok)
            if not ok then QBCore.Functions.Notify('Missing tint supplies', 'error'); return end
            if not DoProgress('Applying window tint...', timeForAction('paint'), 'amb@world_human_vehicle_mechanic@male@base', 'base') then return end
            SetVehicleWindowTint(veh, tonumber(args.tint) or 0)
            QBCore.Functions.Notify('Window tint applied', 'success')
        end, 'tint_supplies')
    end)
end)

-- Override cosmetic use handler to enforce zones and support tint
RegisterNetEvent('pf-mechanicjob:client:usePart', function(item)
    local name = item and item.name or nil
    if not name then return end
    if name == 'tint_supplies' or name == 'tint' or name == 'window_tint' then
        local vehicle = nearbyVeh(5.0)
        if vehicle == 0 then QBCore.Functions.Notify('No vehicle nearby', 'error'); return end
        openTintPicker(vehicle)
        return
    end

    if not CosmeticItems[name] then return end

    local vehicle = nearbyVeh(3.5)
    if vehicle == 0 then
        QBCore.Functions.Notify('No vehicle nearby', 'error')
        return
    end

    -- Enforce placement zones
    if name == 'bumper' or name == 'vehicle_bumper' then
        local nearF = playerNear(posFront(vehicle), 2.8)
        local nearB = playerNear(posBack(vehicle), 2.8)
        if not (nearF or nearB) then
            QBCore.Functions.Notify('Move to the front or the back of the car to fit a bumper', 'error')
            return
        end
    elseif name == 'hood' then
        local nearF = playerNear(posFront(vehicle), 2.8)
        if not nearF then
            QBCore.Functions.Notify('Move to the front of the car to fit a hood', 'error')
            return
        end
    end
    -- exhaust, rims, spoiler, roof, skirts: anywhere

    SetVehicleModKit(vehicle, 0)
    if ItemToModTypes[name] then
        openModPicker(name, vehicle)
    else
        QBCore.Functions.Notify('Invalid mod type', 'error')
    end
end)

-- ============================================================================
-- ROLLING COAL SYSTEM
-- ============================================================================

-- Track coal delete state per vehicle
local CoalVehicles = {} -- [plate] = true/false

-- Helper: Get normalized plate
local function GetPlate(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- Helper: Check if coal is enabled for vehicle
local function IsCoalEnabled(veh)
    if not Config.RollingCoal.enabled then return false end
    if not Config.IsDieselCandidate(veh) then return false end
    
    local plate = GetPlate(veh)
    if not plate then return false end
    
    return CoalVehicles[plate] == true
end

-- Sync coal state from server
RegisterNetEvent('pf_mech:syncCoalDelete', function(plate, enabled)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    CoalVehicles[plate] = enabled
    
    if Config.Debug then
        print(string.format('[COAL] Synced %s: %s', plate, tostring(enabled)))
    end
end)

-- Load coal state when entering vehicle
CreateThread(function()
    local lastVehicle = 0
    
    while true do
        Wait(1000)
        
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            
            if veh ~= 0 and veh ~= lastVehicle then
                lastVehicle = veh
                local plate = GetPlate(veh)
                
                if plate and CoalVehicles[plate] == nil then
                    -- Load state from server
                    QBCore.Functions.TriggerCallback('pf_mech:getCoalState', function(enabled)
                        CoalVehicles[plate] = enabled
                    end, plate)
                end
            end
        else
            lastVehicle = 0
        end
    end
end)

-- REMOVE events: pf_mech:toggleCoalDelete and pf_mech:toggleCoalDeleteNearby (legacy coal delete)
-- REPLACE their handlers with a notice:

RegisterNetEvent('pf_mech:toggleCoalDelete', function()
  QBCore.Functions.Notify('Use diagnostics tool to remove DPF','primary')
end)
RegisterNetEvent('pf_mech:toggleCoalDeleteNearby', function()
  QBCore.Functions.Notify('Use diagnostics tool near diesel vehicle','primary')
end)

-- ADD simple command to open DPF menu directly (fallback if item not useable):
RegisterCommand('dpf', function()
  local veh = nearbyVeh(6.0)
  if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error') return end
  local plate = GetVehicleNumberPlateText(veh)
  if not Config.IsDieselCandidate(veh) then
    QBCore.Functions.Notify('Not a diesel vehicle','error'); return
  end
  -- reuse existing menu function
  local ok = pcall(function() openDPFMenu(veh) end)
  if not ok then QBCore.Functions.Notify('DPF menu unavailable','error') end
end, false)

-- DPF helper: get plate normalized
local function _GetPlate(veh)
    if not veh or not DoesEntityExist(veh) then return nil end
    return GetVehicleNumberPlateText(veh):gsub('%s+',''):upper()
end

-- DPF state check (CoalVehicles true means DPF removed)
function IsDPFRemoved(veh)
    local plate = _GetPlate(veh)
    if not plate then return false end
    -- FIX: Use correct global variable name
    return CoalVehicles[plate] == true
end

-- Open DPF menu (from diagnostics tool)
local function openDPFMenu(veh)
    if not veh or veh==0 or not DoesEntityExist(veh) then
        QBCore.Functions.Notify('No vehicle nearby','error')
        return
    end
    if not Config.IsDieselCandidate(veh) then
        QBCore.Functions.Notify('Vehicle is not diesel','error')
        return
    end
    local plate = _GetPlate(veh)
    local removed = IsDPFRemoved(veh)
    local rows = {
        { header = ('DPF • %s'):format(plate or 'N/A'), isMenuHeader = true }
    }
    if not removed then
        rows[#rows+1] = {
            header = 'Remove DPF',
            txt = 'Removes the Diesel Particulate Filter (enables rolling coal)',
            params = { event='pf_mech:dpf:clientRemove', args={ plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    else
        rows[#rows+1] = {
            header = 'Install DPF',
            txt = 'Reinstall filter (disables rolling coal)',
            params = { event='pf_mech:dpf:clientInstall', args={ plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
    end
    rows[#rows+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(rows)
end

RegisterNetEvent('pf_mech:dpf:clientRemove', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.veh or 0)
    if not DoesEntityExist(veh) then return end
    if IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already removed','error')
        return
    end
    hasToolbox(function(has)
        if not has then return end
        if not DoProgress('Removing DPF...', Config.DPFRemoveTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
            QBCore.Functions.Notify('Cancelled','error'); return
        end
        TriggerServerEvent('pf_mech:dpf:remove', data.plate)
    end)
end)

RegisterNetEvent('pf_mech:dpf:clientInstall', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.veh or 0)
    if not DoesEntityExist(veh) then return end
    if not IsDPFRemoved(veh) then
        QBCore.Functions.Notify('DPF already installed','error')
        return
    end
    hasToolbox(function(has)
        if not has then return end
        if not DoProgress('Installing DPF...', Config.DPFInstallTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
            QBCore.Functions.Notify('Cancelled','error'); return
        end
        TriggerServerEvent('pf_mech:dpf:install', data.plate)
    end)
end)

-- Hook diagnostics tool item usage to open DPF menu
AddEventHandler('QBCore:Client:UseItem', function(item)
    local name = item and item.name
    if name == 'diagnostics_tool' then
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
        openDPFMenu(veh)
    elseif name == Config.DPFItem then
        -- Allow installing DPF by using the item near the front of a diesel vehicle
        local veh = nearbyVeh(6.0)
        if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
        if not Config.IsDieselCandidate(veh) then QBCore.Functions.Notify('Not a diesel vehicle','error'); return end
        if not IsDPFRemoved(veh) then QBCore.Functions.Notify('DPF already installed','error'); return end
        local plate = _GetPlate(veh)
        TriggerEvent('pf_mech:dpf:clientInstall', { plate = plate, veh = NetworkGetNetworkIdFromEntity(veh) })
    end
end)

-- Feedback from server
RegisterNetEvent('pf_mech:dpf:result', function(action, success, msg, plate, state)
    if msg then QBCore.Functions.Notify(msg, success and 'success' or 'error', 4000) end
    if plate then
        CoalVehicles[plate] = state and true or false
    end
end)

RegisterCommand('scanveh', function()
  local veh = nearbyVeh(6.0); if veh == 0 then return TriggerEvent('QBCore:Notify',L('no_vehicle'),'error') end
  if isNPCVeh(veh) then
    -- NPC vehicle diagnostics
    local id = 0
    pcall(function() id = NetworkGetEntityOwner(veh) end)
    QBCore.Functions.TriggerCallback('pf_mech:job:getInfo', function(job)
      local rows = {
        { header = L('vehicle_info'), txt = '', isMenuHeader = true },
        { header = L('part_engine'), txt = ('%.1f%%'):format(GetVehicleEngineHealth(veh)), params = {} },
        { header = L('part_body'), txt = ('%.1f%%'):format(GetVehicleBodyHealth(veh)), params = {} },
        { header = L('diagnostics_plate'), txt = GetVehicleNumberPlateText(veh), params = {} },
        { header = L('diagnostics_owner'), txt = (GetPlayerName(id) or L('unknown')):gsub('^%s*(.-)%s*$','%1'), params = {} },
      }
      -- NEW: append DPF row for diesel vehicles
      if Config.IsDieselCandidate(veh) then
        local plate = GetVehicleNumberPlateText(veh)
        local dpfRemoved = false
        pcall(function() dpfRemoved = exports['pf-mechanicjob']:IsCoalActiveForVehicle(veh) end)
        rows[#rows+1] = {
          header = dpfRemoved and 'DPF (Removed)' or 'DPF (Installed)',
          txt = dpfRemoved and 'Rolling coal enabled' or 'Remove to enable rolling coal',
          params = { event = dpfRemoved and 'pf_mech:dpf:clientInstall' or 'pf_mech:dpf:clientRemove', args = { plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
        }
      end
      exports['qb-menu']:openMenu(rows)
    end, id)
  else
    -- NORMAL vehicle diagnostics
    local plate = GetVehicleNumberPlateText(veh)
    local name  = vehModelName(veh)
    local eng = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
    local body= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
    local menu = {
      { header = name, txt = (L('diagnostics_plate')..': %s'):format(plate or 'N/A'), isMenuHeader = true, params = {} },
      { header = (L('part_engine')..' - %d%%'):format(eng), txt = L('diagnostics_health'), params = {} },
      { header = (L('part_body')..' - %d%%'):format(body), txt = L('diagnostics_health'), params = {} },
    }
    -- NEW: DPF status row for diesel vehicles
    if Config.IsDieselCandidate(veh) then
      local dpfRemoved = false
      pcall(function() dpfRemoved = exports['pf-mechanicjob']:IsCoalActiveForVehicle(veh) end)
      menu[#menu+1] = {
        header = dpfRemoved and 'DPF - Removed' or 'DPF - Installed',
        txt = dpfRemoved and 'Rolling coal enabled' or 'Remove to enable rolling coal',
        params = { event = dpfRemoved and 'pf_mech:dpf:clientInstall' or 'pf_mech:dpf:clientRemove', args = { plate = plate:gsub('%s+',''):upper(), veh = NetworkGetNetworkIdFromEntity(veh) } }
      }
    end
    menu[#menu+1] = { header = L('menu_close'), params = { event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(menu)
  end
end)

-- Ensure single diagnostics hook (remove other AddEventHandler('QBCore:Client:UseItem') blocks above this)
local function _NormPlate(veh)
  return (veh and DoesEntityExist(veh)) and GetVehicleNumberPlateText(veh):gsub('%s+',''):upper() or nil
end
local function _DPFRemoved(veh) return veh and CoalVehicles[_NormPlate(veh)] == true end

AddEventHandler('QBCore:Client:UseItem', function(item)
  local name = item and item.name
  if not name then return end

  if name == 'diagnostics_tool' then
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
    local plate = _NormPlate(veh) or 'UNKNOWN'
    local engPct = math.floor(math.max(0, math.min(100, GetVehicleEngineHealth(veh)/10)))
    local bodyPct= math.floor(math.max(0, math.min(100, GetVehicleBodyHealth(veh)/10)))
    local diesel = Config.IsDieselCandidate(veh)
    local removed = _DPFRemoved(veh)

    local menu = {
      { header = ('Diagnostics • %s'):format(plate), isMenuHeader = true },
      { header = ('Engine - %d%%'):format(engPct),  txt = 'Health' },
      { header = ('Body - %d%%'):format(bodyPct),    txt = 'Health' },
    }

    -- Always show DPF status row
    menu[#menu+1] = removed and {
      header = 'DPF (Removed)',
      txt = diesel and 'Rolling coal enabled' or 'Non-diesel vehicle',
      params = { event='pf_mech:dpf:clientInstall', args={ plate=plate, veh=NetworkGetNetworkIdFromEntity(veh) } }
    } or {
      header = 'DPF (Installed)',
      txt = diesel and 'Remove to enable rolling coal' or 'Non-diesel vehicle',
      params = { event='pf_mech:dpf:clientRemove', args={ plate=plate, veh=NetworkGetNetworkIdFromEntity(veh) } }
    }

    menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
    exports['qb-menu']:openMenu(menu)
    return
  end

  if name == Config.DPFItem then
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby','error'); return end
    if not _DPFRemoved(veh) then QBCore.Functions.Notify('DPF already installed','error'); return end
    TriggerEvent('pf_mech:dpf:clientInstall', { plate=_NormPlate(veh), veh=NetworkGetNetworkIdFromEntity(veh) })
    return
  end

  -- cosmetic items (mods)
  if name == "spoiler" or name == "bumper" or name == "skirts" or name == "exhaust"
     or name == "rollcage" or name == "hood" or name == "roof" then
      -- This will be caught by server CreateUseableItem instead
      return
  end
end)

-- Fallback manual command
RegisterCommand('dpfmenu', function()
  local veh = nearbyVeh(6.0)
  if veh == 0 then QBCore.Functions.Notify('No vehicle','error'); return end
  TriggerEvent('QBCore:Client:UseItem', { name='diagnostics_tool' })
end, false)

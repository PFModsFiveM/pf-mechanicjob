-- pf-mechanicjob • CLIENT (full file)
local QBCore = exports['qb-core']:GetCoreObject()

-- Helper: check if player is a mechanic
local function isPlayerMechanic()
    local PlayerData = QBCore.Functions.GetPlayerData()
    if not PlayerData or not PlayerData.job then return false end
    return Config.IsMechanicJob(PlayerData.job.name)
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
        QBCore.Functions.Notify('You are not a mechanic!', 'error')
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
    tire_new = "Tire"
}

RegisterCommand('scanveh', function()
  local veh = nearbyVeh(6.0); if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end
  if isNPCVeh(veh) then
    local id = Entity(veh).state.pf_jobId
    QBCore.Functions.TriggerCallback('pf_mech:job:getInfo', function(job)
      if not job then return TriggerEvent('QBCore:Notify','No job info','error') end
      local rows = {}
      for _, p in ipairs(job.required_parts or {}) do
        local done = tonumber((job.installed_parts or {})[p.id] or 0)
        local need = math.max(0, (tonumber(p.qty) or 1) - done)
        local tag = need <= 0 and '✓' or ('x'..need)
        rows[#rows+1] = { header = (p.id:gsub('_',' '):gsub('%f[%w].', string.upper)), txt = ('Need: %s  •  Installed: %d'):format(tag, done), params = {} }
      end
      if job.paint_req then rows[#rows+1] = { header = 'Paint', txt = ('Color: %s'):format(job.paint_req), params = {} } end
      rows[#rows+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
      table.insert(rows, 1, { header = ('NPC Job • %s'):format(job.plate or 'Unknown'), isMenuHeader=true, params = {} })
      exports['qb-menu']:openMenu(rows)
    end, id)
  else
    local plate = GetVehicleNumberPlateText(veh)
    local name  = vehModelName(veh)
    local eng = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
    local body= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
    local menu = {
      { header = name, txt = ('Plate: %s'):format(plate or 'N/A'), isMenuHeader = true, params = {} },
      { header = ('Engine - %d%%'):format(eng), txt = 'Health', params = {} },
      { header = ('Body - %d%%'):format(body), txt = 'Health', params = {} },
      { header = 'Close', params = { event='qb-menu:client:closeMenu' } }
    }
    exports['qb-menu']:openMenu(menu)
  end
end)

-- ================== Part usage ==================
local function posFront(veh) return GetOffsetFromEntityInWorldCoords(veh, 0.0, 1.8, 0.2) end
local function posUnder(veh) return GetOffsetFromEntityInWorldCoords(veh, 0.0, -0.3, -0.6) end
local function nearestWheelPos(veh)
  local bones = { 'wheel_lf','wheel_rf','wheel_lr','wheel_rr','wheel_lm1','wheel_rm1' }
  local ply = PlayerPedId(); local p = GetEntityCoords(ply)
  local best, bestDist
  for _, b in ipairs(bones) do
    local id = GetEntityBoneIndexByName(veh, b)
    if id ~= -1 then
      local c = GetWorldPositionOfEntityBone(veh, id)
      local d = #(p - c)
      if not bestDist or d < bestDist then bestDist = d; best = c end
    end
  end
  return best or GetOffsetFromEntityInWorldCoords(veh, 0.6, 0.9, 0.2)
end

local function zoneOK(rule, veh)
  local ped = PlayerPedId(); local p = GetEntityCoords(ped)
  local target
  if rule.zone == 'front' then target = posFront(veh)
  elseif rule.zone == 'under' then target = posUnder(veh)
  elseif rule.zone == 'exterior' then target = GetOffsetFromEntityInWorldCoords(veh, 0.0, 0.5, 0.4)
  elseif rule.zone == 'wheel' then target = nearestWheelPos(veh) end
  if not target then return true end
  local r = tonumber(rule.radius or 3.0) or 3.0
  return (#(p - target) <= r)
end

-- cosmetic/performance picker UI
local ModTypeNames = {
  [0]='Spoiler', [1]='Front Bumper', [2]='Rear Bumper', [3]='Side Skirt',
  [4]='Exhaust', [6]='Grille', [7]='Hood', [10]='Roof'
}
local ItemToModTypes = Config.ItemModMap or {
  bumper   = {1,2},
  vehicle_bumper = {1,2},
  exhaust  = {4},
  hood     = {7},
  roof     = {10},
  skirts   = {3},
  spoiler  = {0},
}

local function openModPicker(itemName, veh)
  if not DoesEntityExist(veh) then return end
  
  SetVehicleModKit(veh, 0)
  local opts = {}
  local types = ItemToModTypes[itemName] or {}
  for _, mtype in ipairs(types) do
    local count = GetNumVehicleMods(veh, mtype)
    if count and count > 0 then
      opts[#opts+1] = { 
        header = (ModTypeNames[mtype] or ('Mod '..mtype)), 
        txt = ('%d options'):format(count), 
        params = { 
          event = 'pf_mech:openModPickerLevel2', 
          args = { 
            item = itemName, 
            modType = mtype,                      -- changed key name here
            vehicle = NetworkGetNetworkIdFromEntity(veh) -- use consistent net id
          }
        } 
      }
    end
  end
  
  if #opts == 0 then
    return QBCore.Functions.Notify('No available mods for this vehicle', 'error')
  end

  local menu = { { header='Select Category', isMenuHeader = true } }
  for _, o in ipairs(opts) do
    menu[#menu+1] = o
  end
  menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
  exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('pf_mech:openModPickerLevel2', function(args)
  local veh = NetworkGetEntityFromNetworkId(args.vehicle)
  if not DoesEntityExist(veh) then return end

  SetVehicleModKit(veh, 0)
  local count = GetNumVehicleMods(veh, args.modType) or 0         -- use args.modType
  local menu = { { header = (ModTypeNames[args.modType] or ('Mod '..args.modType)), isMenuHeader=true } }
  
  for i=0,count-1 do
    local lbl = GetModTextLabel(veh, args.modType, i)
    local nm  = (lbl and GetLabelText(lbl) ~= 'NULL') and GetLabelText(lbl) or ('Option '..(i+1))
    menu[#menu+1] = {
      header = nm, txt=('Apply'),
      params = { 
        event = 'pf_mech:confirmModApply', 
        args = { 
          item = args.item, 
          modType = args.modType,    -- ensure modType flows down
          modIndex = i,
          vehicle = args.vehicle 
        }
      }
    }
  end
  menu[#menu+1] = { header='Back', params={ event='pf_mech:openModPickerRoot', args={ item=args.item, vehicle=args.vehicle } } }
  exports['qb-menu']:openMenu(menu)
end)

-- Update root picker to handle vehicle parameter
RegisterNetEvent('pf_mech:openModPickerRoot', function(args)
  local veh = NetworkGetEntityFromNetworkId(args.vehicle)
  if not DoesEntityExist(veh) then return end
  openModPicker(args.item, veh)
end)

RegisterNetEvent('pf_mech:confirmModApply', function(args)
    local veh = NetworkGetEntityFromNetworkId(args.vehicle)
    if not DoesEntityExist(veh) then 
        QBCore.Functions.Notify('Vehicle not found', 'error')
        return 
    end

    -- Start installation
    if not DoProgress('Installing part...', timeForAction('setMod'), 'amb@world_human_vehicle_mechanic@male@base', 'base') then 
        return 
    end

    -- Send to server for item removal and authoritative sync
    TriggerServerEvent('pf_mech:server:applyMod', {
        vehicle = args.vehicle,
        item = args.item,
        modType = args.modType,
        modIndex = args.modIndex
    })
end)

-- Add new handler for server confirmation
RegisterNetEvent('pf_mech:client:modApplied', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.vehicle)
    if not DoesEntityExist(veh) then return end
    
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, tonumber(data.modType) or data.modType, tonumber(data.modIndex) or data.modIndex, false)
    
    QBCore.Functions.Notify('Modification installed', 'success')
end)

-- main part entry
local installTimes = {
    -- Performance parts
    engine1 = 12000,
    engine2 = 15000,
    engine3 = 18000,
    engine4 = 20000,
    engine5 = 25000,
    brakes1 = 8000,
    brakes2 = 10000,
    brakes3 = 12000,
    transmission1 = 10000,
    transmission2 = 12000,
    transmission3 = 15000,
    suspension1 = 8000,
    suspension2 = 10000,
    suspension3 = 12000,
    suspension4 = 15000,
    turbo = 20000,
    -- Basic repairs
    repair_kit = 5000,
    tire_repair = 3000,
    body_part = 8000,
}

RegisterNetEvent('pf_mech:tryUsePart', function(itemName)
    if itemName == 'oilfilter' then itemName = 'oil_filter' end
    local rule = (Config.PartRules or {})[itemName]
    if not rule then return TriggerEvent('QBCore:Notify', 'Invalid part', 'error') end

    local veh = nearbyVeh(6.0)
    if veh == 0 then return TriggerEvent('QBCore:Notify', 'No vehicle nearby', 'error') end

    -- Get installation time based on part complexity
    local installTime = installTimes[itemName] or 5000

    if not DoProgress('Installing '..itemName:gsub('_', ' ')..'...', installTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then 
        return TriggerEvent('QBCore:Notify', 'Installation cancelled', 'error')
    end

    local px, py, pz = table.unpack(GetEntityCoords(PlayerPedId()))
    TriggerServerEvent('pf_mech:usePart', itemName, NetworkGetNetworkIdFromEntity(veh), nil, px, py, pz, nil)
end)

-- apply the effect; progress already completed
RegisterNetEvent('pf_mech:applyPart', function(data)
    local veh = NetworkGetEntityFromNetworkId(data.net or 0)
    if veh == 0 or not DoesEntityExist(veh) then return end
    local qty = tonumber(data.qty) or 1
    local state = Entity(veh).state
    local partDamage = state.partDamage or {}
    if data.action == 'repair' then
        if data.type == 'body' then
            -- FIX: body_part ONLY repairs body (NOT engine)
            local newHealth = math.min(1000.0, GetVehicleBodyHealth(veh) + (200.0 * qty))
            SetVehicleBodyHealth(veh, newHealth)
            
            -- Clear visual damage when fully repaired
            if newHealth >= 1000.0 then
                SetVehicleDeformationFixed(veh)
                SetVehicleFixed(veh)
                SetVehicleDirtLevel(veh, 0.0)
            end
            
            partDamage.body = math.max(0, (partDamage.body or 0) - (20 * qty))
            
        elseif data.type == 'engine' then
            -- FIX: engine_part ONLY repairs engine (NOT body)
            local newHealth = GetVehicleEngineHealth(veh) + (150 * qty)
            SetVehicleEngineHealth(veh, math.min(1000.0, newHealth))
            partDamage.engine = math.max(0, (partDamage.engine or 0) - (15 * qty))
            
        elseif data.type == 'battery' then
            state:set('batteryDamage', 0, true)
            SetVehicleEngineOn(veh, true, false, false)
            partDamage.carbattery = 0
            
        elseif data.type == 'sparkplugs' then
            SetVehicleEngineHealth(veh, math.min(1000.0, GetVehicleEngineHealth(veh) + (50 * qty)))
            partDamage.sparkplugs = math.max(0, (partDamage.sparkplugs or 0) - (20 * qty))
            
        elseif data.type == 'oil' or data.type == 'engine_oil' then
            SetVehicleEngineHealth(veh, math.min(1000.0, GetVehicleEngineHealth(veh) + (150 * qty)))
            partDamage.oil = math.max(0, (partDamage.oil or 0) - (100 * qty))
            
        elseif data.type == 'alternator' then
            partDamage.alternator = 0
            
        elseif data.type == 'oil_filter' then
            partDamage.oil_filter = 0
            
        elseif data.type == 'brakes' then
            partDamage.brakes = math.max(0, (partDamage.brakes or 0) - (25 * qty))
            
        elseif data.type == 'suspension' then
            local cur = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax') or 1.0
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', cur + (0.05 * qty))
            partDamage.suspension = math.max(0, (partDamage.suspension or 0) - (25 * qty))
            
        elseif data.type == 'axle' then
            local cur = GetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax') or 1.0
            SetVehicleHandlingFloat(veh, 'CHandlingData', 'fTractionCurveMax', cur + (0.05 * qty))
            partDamage.axle = math.max(0, (partDamage.axle or 0) - (25 * qty))
        elseif data.type == 'radiator' then
            partDamage.radiator = 0
        elseif data.type == 'fuel_injector' then
            partDamage.fuel_injector = math.max(0, (partDamage.fuel_injector or 0) - (25 * qty))
        elseif data.type == 'powersteeringpump' then
            partDamage.powersteeringpump = 0
        elseif data.type == 'power_steering_fluid' then
            partDamage.power_steering_fluid = 0
        elseif data.type == 'transmissionfluid' then
            partDamage.transmissionfluid = 0
        elseif data.type == 'brakefluid' then
            partDamage.brakefluid = 0
        elseif data.type == 'coolant' then
            partDamage.coolant = 0
        end
    elseif data.action == 'tire' then
        -- fix up to qty burst tyres
        local fixed = 0
        for i=0,5 do
            if fixed >= qty then break end
            if IsVehicleTyreBurst(veh, i, false) then
                SetVehicleTyreFixed(veh, i)
                partDamage.tires = partDamage.tires or {}
                local key = ({[0]='lf',[1]='rf',[2]='lr',[3]='rr',[4]='lm',[5]='rm'})[i] or tostring(i)
                partDamage.tires[key] = 0
                fixed = fixed + 1
            end
        end
        
    elseif data.action == 'upgrade' then
        SetVehicleModKit(veh, 0)
        if data.type == 'brakes' and data.level then
            SetVehicleMod(veh, 12, data.level - 1, false)
        end
        -- ...existing upgrade handlers...
    end

    -- persist any updates to partDamage back to entity state
    SafeStateSet(veh, 'partDamage', partDamage)

    if data.toast then
        TriggerEvent('QBCore:Notify', data.toast, 'success')
    end
end)

-- Mechanics job tablet
-- RegisterNetEvent('pf-mechanicjob:client:useMechanicTools', function()
--     print('[TOOLS DEBUG] useMechanicTools event received')
--     TriggerEvent('pf-mechanicjob:client:inspectVehicle')
-- end)

-- REPLACE old pf-mechanicjob:client:openRepairSuggest handler with this updated version
RegisterNetEvent('pf-mechanicjob:client:openRepairSuggest', function(data)
    local vehicle = data.vehicle
    local part = data.part
    local needed = tonumber(data.needed) or 1
    local wheel = data.wheel -- optional

    if not DoesEntityExist(vehicle) then return end

    local label = DiagnosticLabels[part] or part

    -- helper to pick a sensible progress action
    local function progForPart(p)
        if p:find('tire') then return 'tire' end
        if p:find('oil') then return 'oil' end
        if p:find('spark') then return 'engine' end
        if p:find('engine') then return 'engine' end
        if p:find('carbattery') or p:find('battery') then return 'engine' end
        if p:find('susp') then return 'susp' end
        if p:find('axle') then return 'susp' end
        return 'engine'
    end

    local progressAction = progForPart(part)
    local progTime = timeForAction(progressAction) or 4000

    local menu = {
        { header = label, isMenuHeader = true, params = {} },
        { header = ("Repair using items (%d)"):format(needed), txt = "Consumes required item(s) from your inventory.", params = {
            event = "pf-mechanicjob:client:doRepairWithItems",
            args = { vehicle = vehicle, part = part, needed = needed, wheel = wheel, progTime = progTime }
        }},
        { header = "Close", params = { event = "qb-menu:client:closeMenu" } }
    }
    exports['qb-menu']:openMenu(menu)
end)

-- New handler: perform progress then call server to consume items & apply repair
RegisterNetEvent('pf-mechanicjob:client:doRepairWithItems', function(data)
    local vehicle = data.vehicle
    local part = data.part
    local needed = tonumber(data.needed) or 1
    local wheel = data.wheel
    local progTime = tonumber(data.progTime) or timeForAction('engine')

    if not DoesEntityExist(vehicle) then
        QBCore.Functions.Notify('Vehicle not found', 'error'); return
    end

    -- run progress; if cancelled, abort
    if not DoProgress('Repairing '..(part:gsub('_',' '))..'...', progTime, 'amb@world_human_vehicle_mechanic@male@base', 'base') then
        QBCore.Functions.Notify('Repair cancelled', 'error'); return
    end

    -- ask server to remove items and perform repair
    QBCore.Functions.TriggerCallback('pf_mech:server:attemptRepair', function(success, msg)
        if success then
            QBCore.Functions.Notify(msg or 'Repair successful', 'success')
            -- server will trigger pf_mech:applyPart to update the vehicle; nothing else required here
        else
            QBCore.Functions.Notify(msg or 'Missing required parts or failed', 'error')
        end
    end, NetworkGetNetworkIdFromEntity(vehicle), part, needed, wheel)
end)

-- Fix the QBCore:Client:UseItem handler - restore proper routing
RegisterNetEvent('QBCore:Client:UseItem', function(item)
    local name = item and item.name or nil
    if not name then return end

    -- Note: paint_kit and tint_supplies are handled via server CreateUseableItem
    -- This handler only catches items that weren't registered server-side
    
    -- cosmetic items (mods)
    if name == "spoiler" or name == "bumper" or name == "skirts" or name == "exhaust"
       or name == "rollcage" or name == "hood" or name == "roof" then
        -- This will be caught by server CreateUseableItem instead
        return
    end
end)

-- Add these near the top with other local variables (SINGLE DEFINITION ONLY)
local CosmeticItems = {
    spoiler = true,
    bumper = true,
    skirts = true,
    exhaust = true,
    rollcage = true,
    hood = true,
    roof = true
}

RegisterNetEvent('pf-mechanicjob:client:usePart', function(item)
    local name = item and item.name or nil
    if not name then return end
    
    if CosmeticItems[name] then
        local vehicle = nearbyVeh(3.0)
        if vehicle == 0 then
            QBCore.Functions.Notify('No vehicle nearby', 'error')
            return
        end
        
        SetVehicleModKit(vehicle, 0)
        
        if ItemToModTypes[name] then
            openModPicker(name, vehicle)
        else
            QBCore.Functions.Notify('Invalid mod type', 'error')
        end
    end
end)

-- Simple keyboard input fallback
local function TextInput(title, maxLen)
    AddTextEntry('PF_INPUT', title or 'Enter text')
    DisplayOnscreenKeyboard(1, 'PF_INPUT', '', '', '', '', '', maxLen or 120)
    while UpdateOnscreenKeyboard() == 0 do Wait(0) end
    if GetOnscreenKeyboardResult() then
        local r = GetOnscreenKeyboardResult()
        if r and r ~= '' then return r end
    end
    return nil
end

-- Use service book: show menu with Add Entry / View History
RegisterNetEvent('pf-mechanicjob:client:use:service_book', function()
    local veh = nearbyVeh(6.0)
    if veh == 0 then QBCore.Functions.Notify('No vehicle nearby', 'error'); return end
    local plate = GetVehicleNumberPlateText(veh) or 'UNKNOWN'
    plate = plate:gsub('%s+', ''):upper()

    local menu = {
        { header = ('Service Book • %s'):format(plate), isMenuHeader = true },
        { 
            header = 'Add Service Entry', 
            txt = 'Record new maintenance or repair note', 
            params = { event = 'pf_mech:service:addEntryPrompt', args = { plate = plate } } 
        },
        { 
            header = 'View Service History', 
            txt = 'Browse past entries', 
            params = { event = 'pf_mech:service:viewHistory', args = { plate = plate } } 
        },
        { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
    }
    exports['qb-menu']:openMenu(menu)
end)

-- Add entry: prompt for text input
RegisterNetEvent('pf_mech:service:addEntryPrompt', function(args)
    local plate = args.plate
    local note = TextInput(('Service note for %s'):format(plate), 500)
    if not note then QBCore.Functions.Notify('Cancelled', 'error'); return end
    TriggerServerEvent('pf_mech:service:addEntry', plate, note)
    QBCore.Functions.Notify('Service entry saved', 'success')
end)

-- View history
RegisterNetEvent('pf_mech:service:viewHistory', function(args)
    local plate = args.plate
    QBCore.Functions.TriggerCallback('pf_mech:service:get', function(rows)
        local menu = { { header = ('Service History • %s'):format(plate), isMenuHeader = true } }
        if #rows == 0 then
            menu[#menu+1] = { header = 'No entries found', txt = '', params = {} }
        else
            for _, r in ipairs(rows) do
                menu[#menu+1] = { 
                    header = (r.author or 'Unknown') .. ' • ' .. (r.at or ''), 
                    txt = r.note or '', 
                    params = {} 
                }
            end
        end
        menu[#menu+1] = { header = 'Close', params = { event = 'qb-menu:client:closeMenu' } }
        exports['qb-menu']:openMenu(menu)
    end, plate)
end)

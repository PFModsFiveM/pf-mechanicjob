-- pf-mechanicjob • CLIENT (full file)
local QBCore = exports['qb-core']:GetCoreObject()
local JOB = Config.JobName or 'mechanic'

local UI_OPEN = false
local jobBlips, spawnedNPCVeh = {}, {}

-- ================== NUI helpers ==================
local function nui(a, p) SendNUIMessage({ action=a, payload=p }) end
local function setFocus(b) SetNuiFocus(b, b); SetNuiFocusKeepInput(false) end
local function openTablet(payload) UI_OPEN=true; setFocus(true); nui('open', payload or {}) end
local function closeTablet() UI_OPEN=false; setFocus(false); nui('close') end

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
  local p = QBCore.Functions.GetPlayerData()
  if not p or not p.job or p.job.name ~= JOB then return end

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
        rows[#rows+1] = { header = (p.id:gsub('_',' '):gsub('%f[%w].', string.upper)), txt = ('Need: %s  •  Installed: %d'):format(tag, done) }
      end
      if job.paint_req then rows[#rows+1] = { header = 'Paint', txt = ('Color: %s'):format(job.paint_req) } end
      rows[#rows+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
      table.insert(rows, 1, { header = ('NPC Job • %s'):format(job.plate or 'Unknown'), isMenuHeader=true })
      exports['qb-menu']:openMenu(rows)
    end, id)
  else
    local plate = GetVehicleNumberPlateText(veh)
    local name  = vehModelName(veh)
    local eng = math.max(0, math.min(100, math.floor(GetVehicleEngineHealth(veh)/10)))
    local body= math.max(0, math.min(100, math.floor(GetVehicleBodyHealth(veh)/10)))
    local menu = {
      { header = name, txt = ('Plate: %s'):format(plate or 'N/A'), isMenuHeader = true },
      { header = ('Engine - %d%%'):format(eng), txt = 'Health' },
      { header = ('Body - %d%%'):format(body), txt = 'Health' },
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
  SetVehicleModKit(veh, 0)
  local opts = {}
  local types = ItemToModTypes[itemName] or {}
  for _, mtype in ipairs(types) do
    local count = GetNumVehicleMods(veh, mtype)
    if count and count > 0 then
      opts[#opts+1] = { header = (ModTypeNames[mtype] or ('Mod '..mtype)), txt = ('%d options'):format(count), params = { isParent = true, mtype = mtype } }
    end
  end
  if #opts == 0 then
    return TriggerEvent('QBCore:Notify', 'No available mods for this vehicle', 'error')
  end

  local menu = { { header='Select Category', isMenuHeader = true } }
  for _, o in ipairs(opts) do
    menu[#menu+1] = {
      header = o.header, txt = o.txt,
      params = { event = 'pf_mech:openModPickerLevel2', args = { item = itemName, mtype = o.params.mtype } }
    }
  end
  menu[#menu+1] = { header='Close', params={ event='qb-menu:client:closeMenu' } }
  exports['qb-menu']:openMenu(menu)
end

RegisterNetEvent('pf_mech:openModPickerLevel2', function(args)
  local item = args.item; local mtype = tonumber(args.mtype)
  local veh = nearbyVeh(6.0); if veh == 0 then return end
  SetVehicleModKit(veh, 0)
  local count = GetNumVehicleMods(veh, mtype) or 0
  local menu = { { header = (ModTypeNames[mtype] or ('Mod '..mtype)), isMenuHeader=true } }
  for i=0,count-1 do
    local lbl = GetModTextLabel(veh, mtype, i)
    local nm  = (lbl and GetLabelText(lbl) ~= 'NULL') and GetLabelText(lbl) or ('Option '..(i+1))
    menu[#menu+1] = {
      header = nm, txt=('Apply'),
      params = { event = 'pf_mech:confirmModApply', args = { item=item, mtype=mtype, modIndex=i } }
    }
  end
  menu[#menu+1] = { header='Back', params={ event='pf_mech:openModPickerRoot', args={ item=item } } }
  exports['qb-menu']:openMenu(menu)
end)
RegisterNetEvent('pf_mech:openModPickerRoot', function(args)
  local veh = nearbyVeh(6.0); if veh == 0 then return end
  openModPicker(args.item, veh)
end)
RegisterNetEvent('pf_mech:confirmModApply', function(args)
  local veh = nearbyVeh(6.0); if veh == 0 then return end
  if not DoProgress('Installing part...', timeForAction('setMod'), 'amb@world_human_vehicle_mechanic@male@base', 'base') then return end
  local px,py,pz = table.unpack(GetEntityCoords(PlayerPedId()))
  TriggerServerEvent('pf_mech:usePart', args.item, NetworkGetNetworkIdFromEntity(veh), nil, px,py,pz, { modType=args.mtype, modIndex=args.modIndex })
end)

-- main part entry
RegisterNetEvent('pf_mech:tryUsePart', function(itemName)
  if itemName == 'oilfilter' then itemName = 'oil_filter' end
  local rule = (Config.PartRules or {})[itemName]
  if not rule then return TriggerEvent('QBCore:Notify','Invalid part', 'error') end

  local veh = nearbyVeh(6.0); if veh == 0 then return TriggerEvent('QBCore:Notify','No vehicle nearby','error') end

  if rule.action == 'setMod' then
    if not zoneOK(rule, veh) then return TriggerEvent('QBCore:Notify','Move closer to the exterior of the vehicle', 'error') end
    return openModPicker(itemName, veh)
  end

  if not zoneOK(rule, veh) then
    local hint = ({front='at the FRONT of the car', wheel='near a WHEEL', exterior='near the EXTERIOR', under='near the UNDERCARRIAGE'})[rule.zone] or 'at the correct spot'
    return TriggerEvent('QBCore:Notify','Move to the correct spot: '..hint, 'error')
  end

  local jobId = nil
  if rule.npcOnly then
    if not isNPCVeh(veh) then return TriggerEvent('QBCore:Notify','This part is for work orders only', 'error') end
    jobId = Entity(veh).state.pf_jobId
  end

  -- progress FIRST, then tell server
  if not DoProgress('Working...', timeForAction(rule.action), 'amb@world_human_vehicle_mechanic@male@base', 'base') then return end

  local px,py,pz = table.unpack(GetEntityCoords(PlayerPedId()))
  TriggerServerEvent('pf_mech:usePart', itemName, NetworkGetNetworkIdFromEntity(veh), jobId, px, py, pz, nil)
end)

-- apply the effect; progress already completed
RegisterNetEvent('pf_mech:applyPart', function(data)
  local veh = NetworkGetEntityFromNetworkId(data.net or 0)
  if veh == 0 or not DoesEntityExist(veh) then return end

  if data.action == 'setMod' then
    SetVehicleModKit(veh, 0)
    SetVehicleMod(veh, tonumber(data.modType or 0), tonumber(data.modIndex or 0), false)
  elseif data.action == 'tire' then
    for i=0,5 do
      if IsVehicleTyreBurst(veh, i, false) then SetVehicleTyreFixed(veh, i) break end
    end
  elseif data.action == 'paint' then
    local p = (Config.PaintPalette or {})[tostring(data.color or '')]
    if p then
      SetVehicleCustomPrimaryColour(veh, p.r, p.g, p.b)
      SetVehicleCustomSecondaryColour(veh, p.r, p.g, p.b)
    end
  elseif data.action == 'brake' or data.action == 'susp' then
    SetVehicleEngineHealth(veh, math.max(GetVehicleEngineHealth(veh), 900.0))
  elseif data.action == 'oil' or data.action == 'engine' then
    SetVehicleEngineHealth(veh, 1000.0)
  elseif data.action == 'body' then
    SetVehicleFixed(veh); SetVehicleDirtLevel(veh, 0.0)
  end

  if data.toast then TriggerEvent('QBCore:Notify', data.toast, 'success') end
end)

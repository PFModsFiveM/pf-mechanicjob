-- pf-mechanicjob • SERVER
local QBCore = exports['qb-core']:GetCoreObject()

local JOB     = Config.JobName or 'mechanic'
local SOCIETY = Config.Society or 'mechanic'

local function enc(t) return json.encode(t or {}) end
local function J(s) if not s or s == '' then return {} end return json.decode(s) end

-- =========================
-- Rank helpers
-- =========================
local RANKS = Config.RankXP or {
  { rank=1, need=0,    payMult=1.00 },
  { rank=2, need=200,  payMult=1.10 },
  { rank=3, need=600,  payMult=1.20 },
  { rank=4, need=1200, payMult=1.35 },
}
local function rankForXP(xp)
  local r, mult = 1, 1.0
  for _, v in ipairs(RANKS) do if xp >= v.need then r=v.rank; mult=v.payMult end end
  return r, mult
end
local function thresholds() local t={}; for _,v in ipairs(RANKS) do t[#t+1]=v.need end; return t end
local function minRankForParts(parts)
  local req = 1
  for _, p in ipairs(parts or {}) do
    if p.id == 'paint_kit' then req = math.max(req, 2) end
    if p.id == 'susp_arm'  then req = math.max(req, 3) end
    if p.id == 'tire_new'  then req = math.max(req, 4) end
  end
  return req
end

local function getSrcByCitizen(cid)
  for _, P in pairs(QBCore.Functions.GetQBPlayers()) do
    if P.PlayerData.citizenid == cid then return P.PlayerData.source end
  end
  return nil
end

-- =========================
-- Usables
-- =========================
for _, name in ipairs(Config.TabletItems or {'mech_tablet'}) do
  QBCore.Functions.CreateUseableItem(name, function(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P or P.PlayerData.job.name ~= JOB then
      return TriggerClientEvent('QBCore:Notify', src, 'You must be a mechanic to use this', 'error')
    end
    TriggerClientEvent('pf_mech:openTablet', src)
  end)
end

for partName, _ in pairs(Config.PartRules or {}) do
  if QBCore.Shared.Items[partName] then
    QBCore.Functions.CreateUseableItem(partName, function(src)
      local P = QBCore.Functions.GetPlayer(src)
      if not P or P.PlayerData.job.name ~= JOB then
        return TriggerClientEvent('QBCore:Notify', src, 'Mechanics only', 'error')
      end
      TriggerClientEvent('pf_mech:tryUsePart', src, partName)
    end)
  end
end
if QBCore.Shared.Items['oilfilter'] and not QBCore.Shared.Items['oil_filter'] then
  QBCore.Functions.CreateUseableItem('oilfilter', function(src)
    local P = QBCore.Functions.GetPlayer(src)
    if not P or P.PlayerData.job.name ~= JOB then
      return TriggerClientEvent('QBCore:Notify', src, 'Mechanics only', 'error')
    end
    TriggerClientEvent('pf_mech:tryUsePart', src, 'oilfilter')
  end)
end

-- =========================
-- Dashboard / Data
-- =========================
QBCore.Functions.CreateCallback('pf_mech:getDashboard', function(src, cb)
  local P = QBCore.Functions.GetPlayer(src); if not P then return cb(false) end
  local cid = P.PlayerData.citizenid

  local prof = MySQL.single.await('SELECT xp,rank FROM pf_mech_profiles WHERE citizenid=?', { cid })
  if not prof then
    MySQL.insert.await('INSERT INTO pf_mech_profiles (citizenid,xp,rank,jobs_done,total_earnings) VALUES (?,?,?,?,?)', { cid, 0, 1, 0, 0 })
    prof = { xp = 0, rank = 1 }
  end
  local myRank = rankForXP(prof.xp or 0)

  local stock = MySQL.query.await('SELECT part_id, qty FROM pf_parts_stock WHERE society=?', { SOCIETY }) or {}

  -- purge ancient stuck jobs assigned to this character
  MySQL.update.await([[ UPDATE pf_work_orders
                         SET status='cancelled'
                         WHERE assigned_to=? AND status IN ('accepted','in_progress')
                           AND TIMESTAMPDIFF(HOUR, updated_at, NOW()) > 12 ]], { cid })

  local jobsNew = MySQL.query.await([[
    SELECT id,type,plate,veh_model,deadline_at,min_rank,status
    FROM pf_work_orders
    WHERE status='new' AND (min_rank IS NULL OR min_rank <= ?)
    ORDER BY created_at ASC
    LIMIT 20
  ]], { myRank }) or {}

  local jobsActive = MySQL.query.await([[
    SELECT id,type,plate,status
    FROM pf_work_orders
    WHERE status IN ('accepted','in_progress','awaiting_parts')
      AND assigned_to=?
    ORDER BY updated_at DESC
    LIMIT 20
  ]], { cid }) or {}

  cb({
    profile = { xp = prof.xp or 0, rank = myRank },
    stock = stock,
    jobsNew = jobsNew,
    jobsActive = jobsActive,
    thresholds = thresholds()
  })
end)

QBCore.Functions.CreateCallback('pf_mech:getPlayerNames', function(_, cb, idList)
  local map = {}
  for _, sid in ipairs(idList or {}) do
    local P = QBCore.Functions.GetPlayer(tonumber(sid))
    if P then
      local n = P.PlayerData.charinfo
      map[tostring(sid)] = (n and (n.firstname .. ' ' .. n.lastname)) or ('ID '..sid)
    end
  end
  cb(map)
end)

QBCore.Functions.CreateCallback('pf_mech:pos:getCatalog', function(_, cb)
  cb(Config.POSCatalog or {})
end)

QBCore.Functions.CreateCallback('pf_mech:job:getInfo', function(src, cb, workId)
  local row = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { workId })
  if not row then return cb(false) end
  row.required_parts = J(row.required_parts)
  row.installed_parts = J(row.installed_parts)
  cb(row)
end)

-- =========================
-- POS / Receipts
-- =========================
local Invoices = {}
local function newInvoiceId() return ('INV-%d-%04d'):format(os.time() % 100000, math.random(0,9999)) end
local function chooseReceiptItem()
  for _, name in ipairs(Config.ReceiptItems or {'receipt'}) do
    if QBCore.Shared.Items[name] then return name end
  end
  return nil
end

RegisterNetEvent('pf_mech:pos:chargePlayer', function(targetSrc, cart)
  local src = source
  local seller = QBCore.Functions.GetPlayer(src); if not seller or seller.PlayerData.job.name ~= JOB then return end
  local items = cart.items or {}
  local subtotal = 0.0
  for _, it in ipairs(items) do subtotal = subtotal + ((tonumber(it.price) or 0) * (tonumber(it.qty) or 1)) end
  local tax = tonumber(cart.tax or (subtotal * 0.085)) or 0
  local total = tonumber(cart.total or (subtotal + tax)) or 0

  local biz = MySQL.single.await('SELECT name FROM pf_business WHERE business=?', { SOCIETY })
  local invoiceId = newInvoiceId()
  local buyerSrc = (targetSrc and targetSrc ~= 0) and targetSrc or src

  Invoices[invoiceId] = {
    id = invoiceId,
    businessName = (biz and biz.name) or 'Mechanic Shop',
    sellerSrc = src, buyerSrc = buyerSrc,
    items = items, subtotal = subtotal, tax = tax, total = total
  }
  TriggerClientEvent('pf_mech:pos:openPayment', buyerSrc, {
    id = invoiceId,
    businessName = Invoices[invoiceId].businessName,
    sellerName = (seller.PlayerData.charinfo.firstname .. ' ' .. seller.PlayerData.charinfo.lastname),
    items = items, subtotal = subtotal, tax = tax, total = total
  })
end)

RegisterNetEvent('pf_mech:pos:customerPay', function(invId, method, accept)
  local src = source
  local inv = Invoices[invId]; if not inv then return end
  if src ~= inv.buyerSrc then return end
  if not accept then Invoices[invId] = nil; return TriggerClientEvent('QBCore:Notify', src, 'Payment declined', 'error') end

  local buyer = QBCore.Functions.GetPlayer(src); if not buyer then return end
  local amt = math.max(0, math.floor(inv.total + 0.5))
  local ok = false
  if method == 'cash' then ok = buyer.Functions.RemoveMoney('cash', amt, 'mechanic-pos') else ok = buyer.Functions.RemoveMoney('bank', amt, 'mechanic-pos') end
  if not ok then return TriggerClientEvent('QBCore:Notify', src, 'Insufficient funds', 'error') end

  local rItem = chooseReceiptItem()
  if rItem then
    buyer.Functions.AddItem(rItem, 1, false, { amount=amt, invoice=inv.id, business=inv.businessName, when=os.time() })
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[rItem], 'add')
  end

  TriggerClientEvent('QBCore:Notify', src, 'Payment successful', 'success')
  TriggerClientEvent('pf_mech:pos:paid', inv.sellerSrc, (src == inv.sellerSrc))
  TriggerClientEvent('pf_mech:pos:paid', src, true)
  Invoices[invId] = nil
end)

-- =========================
-- NPC jobs (feed + expiry)
-- =========================
local NPCOn, NPCThread = false, nil

RegisterNetEvent('pf_mech:npc:toggle', function(enable)
  local src = source
  local P = QBCore.Functions.GetPlayer(src); if not P or P.PlayerData.job.name ~= JOB then return end
  NPCOn = enable and true or false
  TriggerClientEvent('QBCore:Notify', src, NPCOn and 'NPC jobs enabled' or 'NPC jobs disabled', 'primary')

  local function spawnOnce()
    local kind = ({'basic','paint','susp','tires'})[math.random(4)]
    local parts, typ, paintKey
    if kind == 'basic' then
      local arr = { { {id='engine_oil',qty=1} }, { {id='oil_filter',qty=1} }, { {id='brake_pads',qty=1} } }
      parts = arr[math.random(#arr)]; typ = 'engine'
    elseif kind == 'paint' then
      parts = { {id='paint_kit',qty=1} }; typ='cosmetic'; paintKey='red'
    elseif kind == 'susp' then
      parts = { {id='susp_arm',qty=2} }; typ='suspension'
    else
      parts = { {id='tire_new',qty=math.random(1,2)} }; typ='service'
    end

    local plate = ('NPC%03d'):format(math.random(0,999))
    local model = (Config.NPCModels or {'sultan'})[math.random(#(Config.NPCModels or {'sultan'}))]
    local sec = math.random(30,60)
    local minRank = minRankForParts(parts)

    local id = MySQL.insert.await([[
      INSERT INTO pf_work_orders
        (type,source,requester_name,plate,veh_model,notes,required_parts,paint_req,deadline_at,status,min_rank)
      VALUES (?,?,?,?,?,?,?,?, DATE_ADD(NOW(), INTERVAL ? SECOND), 'new', ?)
    ]], { typ, 'npc', 'Local', plate, model, 'Auto-generated', enc(parts), paintKey, sec, minRank })

    -- Only notify players who can actually take this job
    for _, ply in pairs(QBCore.Functions.GetQBPlayers()) do
      if ply.PlayerData.job and ply.PlayerData.job.name == JOB then
        local prof = MySQL.single.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { ply.PlayerData.citizenid })
        local r = rankForXP((prof and prof.xp) or 0)
        if r >= (minRank or 1) then
          TriggerClientEvent('pf_mech:client:newJob', ply.PlayerData.source, { id=id, type=typ, plate=plate })
        end
        TriggerClientEvent('pf_mech:jobsUpdate', ply.PlayerData.source)
      end
    end
  end

  if NPCOn and not NPCThread then
    spawnOnce()
    NPCThread = true
    CreateThread(function()
      while NPCOn do
        Wait(math.random(30,60) * 1000)
        if not NPCOn then break end
        spawnOnce()
      end
      NPCThread = nil
    end)
  end
end)

CreateThread(function()
  while true do
    Wait(2000)
    local changed = MySQL.update.await("UPDATE pf_work_orders SET status='expired' WHERE status='new' AND deadline_at IS NOT NULL AND deadline_at < NOW()")
    if changed and changed > 0 then TriggerClientEvent('pf_mech:jobsUpdate', -1) end
  end
end)

-- =========================
-- Job flow
-- =========================
RegisterNetEvent('pf_mech:acceptJob', function(id)
  local src = source
  local P = QBCore.Functions.GetPlayer(src); if not P or P.PlayerData.job.name ~= JOB then return end
  local cid = P.PlayerData.citizenid

  local wo = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { id })
  if not wo or wo.status ~= 'new' then return end

  local xp = MySQL.scalar.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { cid }) or 0
  local myRank = select(1, rankForXP(xp))
  if myRank < (wo.min_rank or 1) then
    return TriggerClientEvent('QBCore:Notify', src, 'Your rank is too low for this job', 'error')
  end

  local ok = MySQL.update.await("UPDATE pf_work_orders SET status='accepted', assigned_to=? WHERE id=? AND status='new'", { cid, id })
  if not ok or ok < 1 then return end
  MySQL.update.await("UPDATE pf_work_orders SET status='in_progress', updated_at=NOW() WHERE id=?", { id })

  local sp = Config.NPCSpawns and Config.NPCSpawns[1]
  if sp then
    local tires = 0; for _, p in ipairs(J(wo.required_parts) or {}) do if p.id == 'tire_new' then tires = tires + (p.qty or 1) end end
    TriggerClientEvent('pf_mech:client:spawnNPCVeh', src, {
      id=id, model=wo.veh_model, plate=wo.plate,
      coords={ x=sp.coords.x, y=sp.coords.y, z=sp.coords.z, h=sp.h },
      name=string.upper(wo.type) .. ' • ' .. wo.plate,
      popTires=tires
    })
  end

  TriggerClientEvent('pf_mech:jobsUpdate', src)
end)

RegisterNetEvent('pf_mech:startJob', function(id)
  local src = source
  local P = QBCore.Functions.GetPlayer(src); if not P or P.PlayerData.job.name ~= JOB then return end
  MySQL.update.await("UPDATE pf_work_orders SET status='in_progress', updated_at=NOW() WHERE id=? AND assigned_to=?", { id, P.PlayerData.citizenid })
  TriggerClientEvent('pf_mech:jobsUpdate', src)
end)

local function payForJob(wo, quality)
  local q = quality or 80
  local base = (Config.JobTypes[wo.type] or { basePay = 600 }).basePay
  local xp = MySQL.scalar.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { wo.assigned_to }) or 0
  local _, mult = rankForXP(xp)
  local pay = math.floor(base * mult * (0.5 + q / 100))

  local targetSrc = getSrcByCitizen(wo.assigned_to)
  if targetSrc then
    local P = QBCore.Functions.GetPlayer(targetSrc)
    if P then
      P.Functions.AddMoney('bank', pay, 'mechanic-workorder')
      TriggerClientEvent('QBCore:Notify', targetSrc, ('Job complete. Paid $%d'):format(pay), 'success')
      TriggerClientEvent('pf_mech:client:clearJobBlip', targetSrc, wo.id)
    end
  end

  MySQL.update.await('UPDATE pf_mech_profiles SET xp = xp + ?, jobs_done = jobs_done + 1, total_earnings = total_earnings + ? WHERE citizenid=?',
    { math.floor(20 + q / 2), math.max(0, pay), wo.assigned_to })
end

RegisterNetEvent('pf_mech:finishJob', function(id, q)
  local src = source
  local P = QBCore.Functions.GetPlayer(src); if not P or P.PlayerData.job.name ~= JOB then return end
  local wo = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { id })
  if not wo or wo.status ~= 'in_progress' or wo.assigned_to ~= P.PlayerData.citizenid then
    return TriggerClientEvent('QBCore:Notify', src, 'Wrong job state', 'error')
  end

  local need = {}; for _, p in ipairs(J(wo.required_parts) or {}) do need[p.id] = (need[p.id] or 0) + (p.qty or 1) end
  local have = J(wo.installed_parts)
  for idp, qn in pairs(need) do if (have[idp] or 0) < qn then return TriggerClientEvent('QBCore:Notify', src, 'Missing required parts', 'error') end end

  MySQL.update.await("UPDATE pf_work_orders SET status='complete', quality=?, updated_at=NOW() WHERE id=? AND status='in_progress'", { q or 80, id })
  payForJob(wo, q or 80)
  TriggerClientEvent('pf_mech:jobsUpdate', src)
end)

RegisterNetEvent('pf_mech:npcVehSpawned', function(d)
  local src = source
  local P = QBCore.Functions.GetPlayer(src); if not P then return end
  MySQL.update.await([[ UPDATE pf_work_orders
                         SET veh_netid=?, veh_x=?, veh_y=?, veh_z=?, veh_h=?, updated_at=NOW()
                       WHERE id=? AND assigned_to=? ]],
    { d.netId, d.x, d.y, d.z, d.h, d.id, P.PlayerData.citizenid })
end)

-- =========================
-- Parts usage
-- =========================
RegisterNetEvent('pf_mech:orderParts', function(_items)
  TriggerClientEvent('pf_mech:stockUpdate', source)
end)

RegisterNetEvent('pf_mech:usePart', function(partName, vehNet, jobId, px, py, pz, meta)
  local src = source
  local P = QBCore.Functions.GetPlayer(src)
  if not P or P.PlayerData.job.name ~= JOB then return end

  if partName == 'oilfilter' then partName = 'oil_filter' end
  local rule = (Config.PartRules or {})[partName]
  if not rule then return end

  local apply = { net = vehNet, action = rule.action }
  local toast

  if rule.npcOnly then
    if not jobId then return TriggerClientEvent('QBCore:Notify', src, 'This part is for work orders only', 'error') end
    local row = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { jobId })
    if not row or row.status ~= 'in_progress' or row.assigned_to ~= P.PlayerData.citizenid then
      return TriggerClientEvent('QBCore:Notify', src, 'Not your job or wrong state', 'error')
    end

    local req = J(row.required_parts); local need = 0
    for _,p in ipairs(req or {}) do if p.id == partName then need = need + (p.qty or 1) end end
    if need <= 0 then return TriggerClientEvent('QBCore:Notify', src, 'This job does not require that part', 'error') end

    local inst = J(row.installed_parts); local have = tonumber(inst[partName] or 0)
    if have >= need then return TriggerClientEvent('QBCore:Notify', src, 'Already installed', 'error') end

    if not P.Functions.RemoveItem(partName, 1) then
      return TriggerClientEvent('QBCore:Notify', src, 'You do not have that part', 'error')
    end

    inst[partName] = have + 1
    MySQL.update.await('UPDATE pf_work_orders SET installed_parts=?, updated_at=NOW() WHERE id=?', { enc(inst), row.id })

    if partName == 'paint_kit' then apply.color = row.paint_req end
    toast = ('Installed %s (%d/%d)'):format(partName:gsub('_',' '), inst[partName], need)
  else
    if not P.Functions.RemoveItem(partName, 1) then
      return TriggerClientEvent('QBCore:Notify', src, 'You do not have that part', 'error')
    end
    if rule.action == 'setMod' and meta then
      apply.action = 'setMod'
      apply.modType  = tonumber(meta.modType)
      apply.modIndex = tonumber(meta.modIndex)
      toast = 'Modification applied'
    else
      toast = ('Used %s'):format(partName:gsub('_',' '))
    end
  end

  apply.toast = toast
  TriggerClientEvent('pf_mech:applyPart', src, apply)
end)

-- =========================
-- Dev helper to clear stuck jobs
-- =========================
QBCore.Commands.Add('mechclear', 'Clear your assigned mechanic jobs (dev)', {}, false, function(src)
  local P = QBCore.Functions.GetPlayer(src); if not P then return end
  local cid = P.PlayerData.citizenid
  local list = MySQL.query.await('SELECT id FROM pf_work_orders WHERE assigned_to=? AND status IN ("accepted","in_progress")', { cid }) or {}
  MySQL.update.await('UPDATE pf_work_orders SET status="cancelled", updated_at=NOW() WHERE assigned_to=? AND status IN ("accepted","in_progress")', { cid })
  for _, row in ipairs(list) do TriggerClientEvent('pf_mech:client:clearJobBlip', src, row.id) end
  TriggerClientEvent('pf_mech:jobsUpdate', src)
  TriggerClientEvent('QBCore:Notify', src, 'Cleared your active jobs', 'success')
end, 'admin')

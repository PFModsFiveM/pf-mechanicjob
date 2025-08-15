local QBCore = exports['qb-core']:GetCoreObject()

-- ============================================================
-- HELPERS / RANK
-- ============================================================
local function rankForXP(xp)
    local r, mult = 1, 1.0
    for _, v in ipairs(Config.RankXP or {}) do
        if xp >= v.need then r = v.rank; mult = v.payMult end
    end
    return r, mult
end
local function nextNeedForXP(xp)
    for _, v in ipairs(Config.RankXP or {}) do if xp < v.need then return v.need end end
    return nil
end
local function decodeJSON(s) return s and s ~= '' and json.decode(s) or nil end
local function encodeJSON(t) return json.encode(t or {}) end
local function getPlayerSourceByCitizen(citizenid)
    for _, ply in pairs(QBCore.Functions.GetQBPlayers()) do
        if ply.PlayerData and ply.PlayerData.citizenid == citizenid then return ply.PlayerData.source end
    end
    return nil
end
local function minRankForParts(parts)
    local need = 1
    for _, p in ipairs(parts or {}) do
        if p.id == 'paint_kit' then need = math.max(need, 2) end
        if p.id == 'susp_arm'  then need = math.max(need, 3) end
        if p.id == 'tire_new'  then need = math.max(need, 4) end
    end
    return need
end

-- ============================================================
-- DASHBOARD
-- ============================================================
QBCore.Functions.CreateCallback('pf_mech:getDashboard', function(src, cb)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.JobName then return cb(false) end

    local cid = Player.PlayerData.citizenid
    local prof = MySQL.single.await('SELECT * FROM pf_mech_profiles WHERE citizenid = ?', { cid })
    if not prof then
        MySQL.insert.await('INSERT INTO pf_mech_profiles (citizenid) VALUES (?)', { cid })
        prof = { citizenid = cid, xp = 0, rank = 1, total_earnings = 0, jobs_done = 0, rating_avg = 0 }
    end
    local r = rankForXP(prof.xp or 0)
    local nextNeed = nextNeedForXP(prof.xp or 0)

    local stock = MySQL.query.await('SELECT part_id, qty FROM pf_parts_stock WHERE society = ?', { Config.Society }) or {}
    local jobsNew = MySQL.query.await("SELECT * FROM pf_work_orders WHERE status = 'new' ORDER BY created_at ASC LIMIT 30", {}) or {}
    local jobsActive = MySQL.query.await("SELECT * FROM pf_work_orders WHERE status IN ('accepted','in_progress','awaiting_parts') ORDER BY updated_at DESC LIMIT 30", {}) or {}
    local history = MySQL.query.await('SELECT * FROM pf_job_history WHERE citizenid = ? ORDER BY created_at DESC LIMIT 30', { cid }) or {}

    for _, j in ipairs(jobsNew) do
        local req = decodeJSON(j.required_parts) or {}
        j.min_rank = minRankForParts(req)
    end
    for _, j in ipairs(jobsActive) do
        local req = decodeJSON(j.required_parts) or {}
        j.min_rank = minRankForParts(req)
    end

    local thresholds = {}
    for _, v in ipairs(Config.RankXP or {}) do thresholds[#thresholds+1] = v.need end

    cb({
        profile = { xp = prof.xp or 0, rank = r, next_need = nextNeed },
        thresholds = thresholds,
        stock = stock, jobsNew = jobsNew, jobsActive = jobsActive, history = history
    })
end)

-- ============================================================
-- NPC JOB FEED + EXPIRY  (unchanged)
-- ============================================================
local NPCFeedEnabled, NPCFeedThread = false, nil

RegisterNetEvent('pf_mech:npc:toggle', function(enabled)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.JobName then return end

    NPCFeedEnabled = enabled and true or false
    TriggerClientEvent('QBCore:Notify', src, NPCFeedEnabled and 'NPC jobs enabled' or 'NPC jobs disabled', 'primary')

    if NPCFeedEnabled and not NPCFeedThread then
        NPCFeedThread = true
        CreateThread(function()
            while NPCFeedEnabled do
                local waitMs = math.random(30, 60) * 1000 -- testing window
                Wait(waitMs)
                if not NPCFeedEnabled then break end

                local kinds = { 'basic', 'paint', 'susp', 'tires' }
                local kind = kinds[math.random(#kinds)]
                local parts
                local typeEnum = 'service'
                local paintReq = nil
                if kind == 'basic' then
                    local basics = {
                        { { id='engine_oil', qty=1 } },
                        { { id='oil_filter', qty=1 } },
                        { { id='brake_pads', qty=1 } },
                    }
                    parts = basics[math.random(#basics)]
                    typeEnum = 'engine'
                elseif kind == 'paint' then
                    parts = { { id='paint_kit', qty=1 } }
                    typeEnum = 'cosmetic'
                    local keys = {} for k,_ in pairs(Config.PaintPalette) do keys[#keys+1] = k end
                    paintReq = keys[math.random(#keys)]
                elseif kind == 'susp' then
                    parts = { { id='susp_arm', qty=2 } }
                    typeEnum = 'suspension'
                else
                    local qty = math.random(1,2)
                    parts = { { id='tire_new', qty=qty } }
                    typeEnum = 'service'
                end

                local plate = ('NPC%03d'):format(math.random(0, 999))
                local model = (Config.NPCModels or { 'sultan' })[math.random(#(Config.NPCModels or { 'sultan' }))]

                local seconds = math.random(30, 60)
                local newId = MySQL.insert.await([[
                    INSERT INTO pf_work_orders (type,source,requester_name,plate,veh_model,notes,required_parts,paint_req,deadline_at,status)
                    VALUES (?,?,?,?,?,?,?,?, DATE_ADD(NOW(), INTERVAL ? SECOND), 'new')
                ]], { typeEnum, 'npc', 'Local', plate, model, 'Auto-generated', json.encode(parts), paintReq, seconds })

                for _, ply in pairs(QBCore.Functions.GetQBPlayers()) do
                    if ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name == Config.JobName then
                        TriggerClientEvent('pf_mech:client:newJob', ply.PlayerData.source, { id = newId, type = typeEnum, plate = plate })
                    end
                end
                TriggerClientEvent('pf_mech:jobsUpdate', -1)
            end
            NPCFeedThread = nil
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(2000)
        local changed = MySQL.update.await("UPDATE pf_work_orders SET status='expired' WHERE status='new' AND deadline_at IS NOT NULL AND deadline_at < NOW()", {})
        if changed and changed > 0 then TriggerClientEvent('pf_mech:jobsUpdate', -1) end
    end
end)

-- ============================================================
-- ACCEPT / START / FINISH  (unchanged)
-- ============================================================
RegisterNetEvent('pf_mech:acceptJob', function(id)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.JobName then return end
    local prof = MySQL.single.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { Player.PlayerData.citizenid }) or { xp = 0 }
    local myRank = select(1, rankForXP(prof.xp or 0))
    local wo = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { id })
    if not wo or wo.status ~= 'new' then return end
    local req = decodeJSON(wo.required_parts) or {}
    local minRank = minRankForParts(req)
    if myRank < minRank then
        return TriggerClientEvent('QBCore:Notify', src, ('Rank %d required for this job.'):format(minRank), 'error')
    end
    local changed = MySQL.update.await("UPDATE pf_work_orders SET status='accepted', assigned_to=? WHERE id=? AND status='new'", { Player.PlayerData.citizenid, id })
    if not changed or changed < 1 then return end

    MySQL.update.await("UPDATE pf_work_orders SET status='in_progress' WHERE id=?", { id })

    local sp = Config.NPCSpawns and Config.NPCSpawns[1]
    if sp then
        local tireCount = 0
        for _, p in ipairs(req) do if p.id == 'tire_new' then tireCount = p.qty or 1 end end
        TriggerClientEvent('pf_mech:client:spawnNPCVeh', src, {
            id = id, model = wo.veh_model, plate = wo.plate,
            coords = { x = sp.coords.x, y = sp.coords.y, z = sp.coords.z, h = sp.h },
            name = string.upper(wo.type) .. ' • ' .. wo.plate, popTires = tireCount
        })
    end
    TriggerClientEvent('pf_mech:jobsUpdate', -1)
end)

RegisterNetEvent('pf_mech:startJob', function(id)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.JobName then return end
    MySQL.update.await("UPDATE pf_work_orders SET status='in_progress' WHERE id=? AND assigned_to=?", { id, Player.PlayerData.citizenid })
end)

local function CompleteJobFinal(jobId, quality, payoutOverride)
    local wo = MySQL.single.await('SELECT * FROM pf_work_orders WHERE id=?', { jobId })
    if not wo or wo.status ~= 'in_progress' then return false, 'bad_state' end
    local q = quality or 80
    local payout = payoutOverride
    if payout == nil then
        local cfg = Config.JobTypes[wo.type]
        local base = cfg and cfg.basePay or 600
        local profXP = MySQL.scalar.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { wo.assigned_to }) or 0
        local _, mult = rankForXP(profXP)
        payout = math.floor(base * mult * (0.5 + q / 100))
    end
    local changed = MySQL.update.await("UPDATE pf_work_orders SET status='complete', quality=?, payout=? WHERE id=? AND status='in_progress'", { q, payout, jobId })
    if not changed or changed < 1 then return false, 'raced' end
    local targetSrc = getPlayerSourceByCitizen(wo.assigned_to)
    if targetSrc then
        local Player = QBCore.Functions.GetPlayer(targetSrc)
        if Player then
            if payout >= 0 then
                Player.Functions.AddMoney('bank', payout, 'mechanic-workorder')
                TriggerClientEvent('QBCore:Notify', targetSrc, ('Job complete. Quality %d. Paid $%d'):format(q, payout), 'success')
            else
                local penalty = math.abs(payout)
                local left = penalty
                if Player.Functions.RemoveMoney('bank', left, 'mechanic-wrong-work') then left = 0 end
                if left > 0 then if Player.Functions.RemoveMoney('cash', left, 'mechanic-wrong-work') then left = 0 end end
                TriggerClientEvent('QBCore:Notify', targetSrc, ('Wrong work. You were fined $%d.'):format(penalty - left), 'error')
            end
            TriggerClientEvent('pf_mech:client:clearJobBlip', targetSrc, jobId)
        end
    end
    MySQL.insert.await('INSERT INTO pf_job_history (work_order_id,citizenid,plate,type,quality,payout) VALUES (?,?,?,?,?,?)',
        { jobId, wo.assigned_to, wo.plate, wo.type, q, payout })
    local xpGain = payout >= 0 and math.floor(20 + q / 2) or 0
    MySQL.update.await('UPDATE pf_mech_profiles SET xp = xp + ?, jobs_done = jobs_done + 1, total_earnings = total_earnings + ? WHERE citizenid=?',
        { xpGain, math.max(0, payout), wo.assigned_to })
    TriggerClientEvent('pf_mech:jobsUpdate', -1)
    return true
end

RegisterNetEvent('pf_mech:finishJob', function(id, quality)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    local wo = MySQL.single.await('SELECT required_parts, installed_parts, status FROM pf_work_orders WHERE id=?', { id })
    if not wo or wo.status ~= 'in_progress' then return TriggerClientEvent('QBCore:Notify', src, 'Already finished or not started.', 'error') end
    local req = decodeJSON(wo.required_parts) or {}
    local inst = decodeJSON(wo.installed_parts) or {}
    local count = {}; for _, p in ipairs(req) do count[p.id] = (count[p.id] or 0) + (p.qty or 1) end
    for idp, qty in pairs(count) do
        if (inst[idp] or 0) < qty then return TriggerClientEvent('QBCore:Notify', src, 'Cannot finish. Required parts not installed.', 'error') end
    end
    CompleteJobFinal(id, quality or 80)
end)

RegisterNetEvent('pf_mech:npcVehSpawned', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    MySQL.update.await([[
        UPDATE pf_work_orders
           SET veh_netid=?, veh_x=?, veh_y=?, veh_z=?, veh_h=?
         WHERE id=? AND assigned_to=?
    ]], { data.netId, data.x, data.y, data.z, data.h, data.id, Player.PlayerData.citizenid })
end)

RegisterNetEvent('pf_mech:server:fixTire', function(netId, wheelIndex)
    TriggerClientEvent('pf_mech:client:fixTire', -1, netId, wheelIndex)
end)

-- ============================================================
-- SUPPLIER (unchanged)
-- ============================================================
RegisterNetEvent('pf_mech:orderParts', function(items)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.JobName then return end
    for _, it in ipairs(items or {}) do
        local cat = MySQL.single.await('SELECT base_cost, lead_minutes FROM pf_parts_catalog WHERE part_id=?', { it.part_id })
        if cat then
            local eta = os.time() + (cat.lead_minutes * 60)
            MySQL.insert.await('INSERT INTO pf_supplier_orders (society,part_id,qty,unit_cost,eta_at) VALUES (?,?,?,?,FROM_UNIXTIME(?))',
                { Config.Society, it.part_id, it.qty, cat.base_cost, eta })
            SetTimeout(cat.lead_minutes * 60 * 1000, function()
                MySQL.update.await('UPDATE pf_supplier_orders SET status="delivered" WHERE society=? AND part_id=? AND status="pending" ORDER BY id DESC LIMIT 1',
                    { Config.Society, it.part_id })
                MySQL.execute('INSERT INTO pf_parts_stock (society,part_id,qty) VALUES (?,?,?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)',
                    { Config.Society, it.part_id, it.qty })
                TriggerClientEvent('pf_mech:stockUpdate', -1)
            end)
        end
    end
end)

-- ============================================================
-- USABLES (unchanged from last drop)
-- ============================================================
QBCore.Functions.CreateCallback('pf_mech:consumeItem', function(src, cb, item, count)
    count = tonumber(count or 1)
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return cb(false) end
    local ok = false
    if GetResourceState('ox_inventory') == 'started' then
        ok = exports.ox_inventory:RemoveItem(src, item, count)
    else
        ok = Player.Functions.RemoveItem(item, count)
        if ok and QBCore.Shared.Items[item] then TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], 'remove') end
    end
    cb(ok and true or false)
end)

local function regUsable(name, fn)
    QBCore.Functions.CreateUseableItem(name, fn)
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:RegisterUsableItem(name, fn)
    end
end

for _, name in ipairs({ 'oil_filter','engine_oil','brake_pads','susp_arm','tire_new','paint_kit' }) do
    regUsable(name, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player or Player.PlayerData.job.name ~= Config.JobName then return TriggerClientEvent('QBCore:Notify', source, 'Mechanic only', 'error') end
        TriggerClientEvent('pf_mech:client:usePart', source, { part_id = name })
    end)
end

for _, name in ipairs({ 'scan_tablet','mech_wrench','mechanic_tools','toolbox','paintcan' }) do
    regUsable(name, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player or Player.PlayerData.job.name ~= Config.JobName then return TriggerClientEvent('QBCore:Notify', source, 'Mechanic only', 'error') end
        if name == 'scan_tablet' then TriggerClientEvent('pf_mech:openTablet', source)
        elseif name == 'mech_wrench' then TriggerClientEvent('pf_mech:client:wrench', source)
        elseif name == 'mechanic_tools' then TriggerClientEvent('pf_mech:client:mechanicTools', source)
        elseif name == 'toolbox' then TriggerClientEvent('pf_mech:client:toolbox', source)
        elseif name == 'paintcan' then TriggerClientEvent('pf_mech:client:playerPaint', source) end
    end)
end

for _, name in ipairs({ 'engine_part','body_part','newoil','sparkplugs','carbattery','axleparts' }) do
    regUsable(name, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player or Player.PlayerData.job.name ~= Config.JobName then return TriggerClientEvent('QBCore:Notify', source, 'Mechanic only', 'error') end
        TriggerClientEvent('pf_mech:client:useRepairItem', source, name)
    end)
end

for _, name in ipairs({ 'bumper','exhaust','externals','hood','horn','internals','livery','customplate','rims','roof','rollcage','seat','skirts','spoiler','tint_supplies' }) do
    regUsable(name, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player or Player.PlayerData.job.name ~= Config.JobName then return TriggerClientEvent('QBCore:Notify', source, 'Mechanic only', 'error') end
        TriggerClientEvent('pf_mech:client:cosmeticMenu', source, name)
    end)
end

for _, name in ipairs({ 'car_armor','brakes1','brakes2','brakes3','engine1','engine2','engine3','engine4','engine5','suspension1','suspension2','suspension3','suspension4','suspension5','transmission1','transmission2','transmission3','transmission4','drifttires','bprooftires','turbo','headlights' }) do
    regUsable(name, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if not Player or Player.PlayerData.job.name ~= Config.JobName then return TriggerClientEvent('QBCore:Notify', source, 'Mechanic only', 'error') end
        TriggerClientEvent('pf_mech:client:perfApply', source, name)
    end)
end

-- ============================================================
-- POS / CASH REGISTER (FIXED)
-- ============================================================
local Invoices = {} -- [invoiceId] = { sellerSrc, buyerSrc, cart }
local function nextInvoiceId() return ('POS-%d'):format(math.random(100000,999999)) end

QBCore.Functions.CreateCallback('pf_mech:pos:getCatalog', function(src, cb)
    local rows = MySQL.query.await('SELECT category,item_id,label,price FROM pf_pos_items WHERE business=?', { Config.BusinessKey }) or {}
    if not rows or #rows == 0 then
        cb({
            Repairs = {
                { id="rep_engine",   label="Engine Repair",  price=500 },
                { id="rep_body",     label="Body Repair",    price=400 },
                { id="rep_brakes",   label="Brake Service",  price=250 },
                { id="rep_oil",      label="Oil Change",     price=150 },
            },
            Cosmetics = {
                { id="cos_paint",    label="Paint / Respray", price=1200 },
                { id="cos_rims",     label="Rims Install",    price=600 },
                { id="cos_tint",     label="Window Tint",     price=300 },
            },
            Performance = {
                { id="per_engine",   label="Engine Upgrade", price=1800 },
                { id="per_brakes",   label="Brake Upgrade",  price=900 },
                { id="per_trans",    label="Transmission",   price=1200 },
                { id="per_susp",     label="Suspension",     price=800 },
                { id="per_turbo",    label="Turbo",          price=2000 },
            }
        }); return
    end
    local cat = { Repairs = {}, Cosmetics = {}, Performance = {} }
    for _, r in ipairs(rows) do
        if not cat[r.category] then cat[r.category] = {} end
        cat[r.category][#cat[r.category]+1] = { id = r.item_id, label = r.label, price = r.price }
    end
    cb(cat)
end)

RegisterNetEvent('pf_mech:pos:chargePlayer', function(targetSrc, cart)
    local src = source
    local seller = QBCore.Functions.GetPlayer(src)
    if not seller or seller.PlayerData.job.name ~= Config.JobName then return end

    -- Support "charge myself" from UI (targetSrc <= 0)
    if not tonumber(targetSrc) or tonumber(targetSrc) <= 0 then
        targetSrc = src
    end

    local buyer  = QBCore.Functions.GetPlayer(tonumber(targetSrc))
    if not buyer then
        TriggerClientEvent('QBCore:Notify', src, 'Target not available.', 'error')
        return
    end

    local invId = nextInvoiceId()
    Invoices[invId] = { sellerSrc = src, buyerSrc = targetSrc, cart = cart }

    local payload = {
        id = invId,
        sellerName = seller.PlayerData.charinfo.firstname .. ' ' .. seller.PlayerData.charinfo.lastname,
        businessName = Config.BusinessName,
        items = cart.items or {},
        subtotal = cart.subtotal or 0,
        tax = cart.tax or 0,
        total = cart.total or 0
    }
    TriggerClientEvent('pf_mech:pos:openPayment', targetSrc, payload)
    TriggerClientEvent('QBCore:Notify', src, 'Payment request sent.', 'primary')
end)

RegisterNetEvent('pf_mech:pos:customerPay', function(invoiceId, method, accept)
    local src = source
    local inv = Invoices[invoiceId]; if not inv then return end
    if tonumber(src) ~= tonumber(inv.buyerSrc) then return end

    local buyer = QBCore.Functions.GetPlayer(src)
    local seller = QBCore.Functions.GetPlayer(inv.sellerSrc)
    if not buyer or not seller then Invoices[invoiceId] = nil return end

    if not accept then
        TriggerClientEvent('QBCore:Notify', inv.sellerSrc, 'Customer declined payment.', 'error')
        Invoices[invoiceId] = nil
        return
    end

    local total = inv.cart.total or 0
    local paid = false
    if method == 'cash' then
        paid = buyer.Functions.RemoveMoney('cash', total, 'mechanic-pos')
    else
        paid = buyer.Functions.RemoveMoney('bank', total, 'mechanic-pos')
    end

    if not paid then
        TriggerClientEvent('QBCore:Notify', inv.sellerSrc, 'Customer lacks funds.', 'error')
        TriggerClientEvent('QBCore:Notify', src, 'Insufficient funds.', 'error')
        Invoices[invoiceId] = nil
        return
    end

    if Config.PayToSociety then
        exports['qb-management']:AddMoney(Config.Society, total)
    else
        seller.Functions.AddMoney('bank', total, 'mechanic-pos')
    end

    local receiptData = {
        business = Config.BusinessName,
        total = total,
        method = method,
        items = inv.cart.items or {},
        ts = os.time()
    }

    local itemName = 'mech_receipt'
    if GetResourceState('ox_inventory') == 'started' then
        exports.ox_inventory:AddItem(src, itemName, 1, receiptData)
    else
        buyer.Functions.AddItem(itemName, 1, false, receiptData)
        if QBCore.Shared.Items[itemName] then TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add') end
    end

    TriggerClientEvent('QBCore:Notify', inv.sellerSrc, ('Payment received: $%d'):format(total), 'success')
    TriggerClientEvent('QBCore:Notify', src, ('Paid $%d by %s'):format(total, method == 'cash' and 'Cash' or 'Card'), 'success')
    Invoices[invoiceId] = nil
end)

-- ============================================================
-- BUSINESS MANAGEMENT (with backticked columns)
-- ============================================================
QBCore.Functions.CreateCallback('pf_mech:biz:getInfo', function(src, cb)
    local data = MySQL.single.await('SELECT * FROM pf_business WHERE business=?', { Config.BusinessKey })
    if not data then
        cb({
            name = Config.BusinessName,
            primary = '#0BA378',
            secondary = '#0B2E44',
            logo = '',
            open = 1,
            prices = {},
            employees = {}
        }); return
    end

    local prices = {}
    local rows = MySQL.query.await('SELECT category,item_id,label,price FROM pf_pos_items WHERE business=?', { Config.BusinessKey }) or {}
    for _, r in ipairs(rows) do
        if not prices[r.category] then prices[r.category] = {} end
        prices[r.category][#prices[r.category]+1] = { id=r.item_id, label=r.label, price=r.price }
    end

    local emps = {}
    for _, p in pairs(QBCore.Functions.GetQBPlayers()) do
        if p.PlayerData.job.name == Config.JobName then
            emps[#emps+1] = {
                cid = p.PlayerData.citizenid,
                name = p.PlayerData.charinfo.firstname .. ' ' .. p.PlayerData.charinfo.lastname,
                grade = p.PlayerData.job.grade.level or 0,
                online = true
            }
        end
    end

    cb({
        name = data.name or Config.BusinessName,
        primary = data.primary or '#0BA378',
        secondary = data.secondary or '#0B2E44',
        logo = data.logo or '',
        open = (data.open or 1),
        prices = next(prices) and prices or {},
        employees = emps
    })
end)

RegisterNetEvent('pf_mech:biz:updateBasics', function(basics)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    local cid = Player.PlayerData.citizenid
    local prof = MySQL.single.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { cid }) or { xp = 0 }
    local rank = select(1, rankForXP(prof.xp or 0))
    if rank < 4 then return TriggerClientEvent('QBCore:Notify', src, 'Boss app is Rank 4.', 'error') end

    MySQL.execute([[
        INSERT INTO pf_business (business,name,`primary`,`secondary`,logo,`open`)
        VALUES (?,?,?,?,?,?)
        ON DUPLICATE KEY UPDATE
          name=VALUES(name),
          `primary`=VALUES(`primary`),
          `secondary`=VALUES(`secondary`),
          logo=VALUES(logo),
          `open`=VALUES(`open`)
    ]], { Config.BusinessKey, basics.name or Config.BusinessName, basics.primary or '#0BA378', basics.secondary or '#0B2E44', basics.logo or '', basics.open and 1 or 0 })

    TriggerClientEvent('QBCore:Notify', src, 'Business settings saved.', 'success')
end)

RegisterNetEvent('pf_mech:biz:updatePrice', function(category, item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src); if not Player then return end
    local cid = Player.PlayerData.citizenid
    local prof = MySQL.single.await('SELECT xp FROM pf_mech_profiles WHERE citizenid=?', { cid }) or { xp = 0 }
    local rank = select(1, rankForXP(prof.xp or 0))
    if rank < 4 then return TriggerClientEvent('QBCore:Notify', src, 'Boss app is Rank 4.', 'error') end

    MySQL.execute([[
        INSERT INTO pf_pos_items (business,category,item_id,label,price)
        VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE label=VALUES(label), price=VALUES(price)
    ]], { Config.BusinessKey, category, item.id, item.label, item.price })

    TriggerClientEvent('QBCore:Notify', src, 'Price updated.', 'success')
end)

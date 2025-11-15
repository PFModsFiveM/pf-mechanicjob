-- server/main.lua
-- PF Mechanic Job – Server
-- Framework: QBCore + oxmysql

local QBCore = exports['qb-core']:GetCoreObject()
local CoalState = CoalState or {} -- [plate] = true if DPF removed

QBCore.Functions.CreateCallback('pf_mech:getCoalState', function(src, cb, plate)
  plate = tostring(plate or ''):gsub('%s+',''):upper()
  cb(CoalState[plate] == true)
end)

RegisterNetEvent('pf_mech:dpf:remove', function(plate)
    local src = source
    plate = tostring(plate or ''):gsub('%s+',''):upper()
    if plate == '' then return end
    if CoalState[plate] == true then
        TriggerClientEvent('pf_mech:dpf:result', src, 'remove', false, 'DPF already removed', plate, true)
        return
    end
    local ply = QBCore.Functions.GetPlayer(src); if not ply then return end
    CoalState[plate] = true
    ply.Functions.AddItem(Config.DPFItem, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.DPFItem], 'add')
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, true)
    TriggerClientEvent('pf_mech:dpf:result', src, 'remove', true, 'DPF removed - rolling coal enabled', plate, true)
    
    -- NEW: Debug
    if Config.Debug then
        print(string.format('[DPF SERVER] Removed DPF for %s, broadcasting to all clients', plate))
    end
end)

RegisterNetEvent('pf_mech:dpf:install', function(plate)
  local src = source
  plate = tostring(plate or ''):gsub('%s+',''):upper()
  if plate == '' then return end
  if CoalState[plate] ~= true then
    TriggerClientEvent('pf_mech:dpf:result', src, 'install', false, 'DPF already installed', plate, false)
    return
  end
  local ply = QBCore.Functions.GetPlayer(src); if not ply then return end
  if not ply.Functions.GetItemByName('dpf') then
    TriggerClientEvent('pf_mech:dpf:result', src, 'install', false, 'Missing DPF item', plate, true)
    return
  end
  ply.Functions.RemoveItem('dpf', 1)
  TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items['dpf'], 'remove')
  CoalState[plate] = false
  TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, false)
  TriggerClientEvent('pf_mech:dpf:result', src, 'install', true, 'DPF installed - rolling coal disabled', plate, false)
end)

RegisterNetEvent('pf_mech:coal:syncStart', function(netId)
  if not Config.RollingCoal.enabled then return end
  TriggerClientEvent('pf_mech:coal:startParticles', -1, netId)
end)
RegisterNetEvent('pf_mech:coal:syncStop', function(netId)
  TriggerClientEvent('pf_mech:coal:stopParticles', -1, netId)
end)

local resource = GetCurrentResourceName()

---@type table<string, boolean>
local BossGrades = Config.BossGrades or {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function json_ok(s)
    if not s or s == '' then return nil end
    local ok, t = pcall(function() return json.decode(s) end)
    if ok then return t end
    return nil
end

local function getNameFromPlayersTable(citizenid)
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then return ('%s'):format(citizenid:sub(1, 6)) end
    local ci = json_ok(row.charinfo) or {}
    local first, last = (ci.firstname or ''), (ci.lastname or '')
    local name = (first ~= '' or last ~= '') and (first .. ' ' .. last) or (ci.firstname or citizenid:sub(1, 6))
    return name
end

-- REPLACE isBoss to respect any allowed mechanic job
local function isBoss(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end
    local jobData = Player.PlayerData.job
    local jobName = jobData.name
    if not Config.IsMechanicJob(jobName) then return false end
    if jobData.isboss then return true end
    local grade = tostring(jobData.grade and jobData.grade.level or jobData.grade or 0)
    return BossGrades[grade] == true
end

-- ADD: dynamic business key lookup (used throughout)
local function getPlayerBusiness(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return nil end
    local jobName = Player.PlayerData.job.name
    if not Config.IsMechanicJob(jobName) then return nil end
    return Config.GetBusinessKey(jobName)
end

local function ensureBusiness()
    local bkey = (Config.DEFAULT_BRANDING and Config.DEFAULT_BRANDING.business) or (Config.Job or 'mechanic')
    local row = MySQL.single.await('SELECT business FROM pf_business WHERE business = ? LIMIT 1', { bkey })
    if not row then
        local d = Config.DEFAULT_BRANDING or {}
        MySQL.insert.await(
            'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { bkey, d.name or 'Mechanic Shop', d.primary_color or '#0BA378', d.secondary_color or '#0B2E44', d.logo or '', d.open or 1, d.tax or 0.05 }
        )
    end
end

-- Call this once on resource start (or before first read of pf_business)
local function ensureBusinessRow(business)
    local row = MySQL.single.await('SELECT * FROM pf_business WHERE business = ?', { business })
    if not row then
        MySQL.insert.await(
            'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, tax, open) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { business, DEFAULT_BRANDING.name, DEFAULT_BRANDING.primary_color, DEFAULT_BRANDING.secondary_color, DEFAULT_BRANDING.logo, DEFAULT_BRANDING.tax, DEFAULT_BRANDING.open }
        )
    end
end

-- REMOVE / COMMENT OUT old single-row seeding handler
--[[  (deprecated single business seed)
AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    ensureBusinessRow('mechanic')
end)
]]

-- Transform flat pf_pos_items to { [category] = { {id,label,price}, ... } }
local function buildCatalog(rows)
    local out = {}
    for _, r in ipairs(rows or {}) do
        local cat = r.category or 'General'
        out[cat] = out[cat] or {}
        out[cat][#out[cat] + 1] = { id = r.item_id, label = r.label, price = tonumber(r.price) or 0 }
    end
    return out
end

-- ============================================================================
-- Boot / Seed
-- ============================================================================

AddEventHandler('onResourceStart', function(res)
    if res ~= resource then return end
    ensureAllBusinesses()                 -- now seeds all configured shops
    -- Seed POS items per business if empty
    for key, branding in pairs(Config.BusinessBranding or {}) do
        local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pf_pos_items WHERE business = ?', { branding.business }) or 0
        if cnt == 0 and Config.CatalogSeed then
            for _, it in ipairs(Config.CatalogSeed) do
                MySQL.insert.await(
                    'INSERT INTO pf_pos_items (business, item_id, category, label, price) VALUES (?, ?, ?, ?, ?)',
                    { branding.business, it.id, it.category, it.label, it.price }
                )
            end
        end
    end
end)

-- NEW: ensure all businesses (moved up so it exists before onResourceStart handler)
local function ensureAllBusinesses()
    for _, branding in pairs(Config.BusinessBranding or {}) do
        local row = MySQL.single.await(
            'SELECT business FROM pf_business WHERE business = ? LIMIT 1',
            { branding.business }
        )
        if not row then
            MySQL.insert.await(
                'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',

                {
                    branding.business,
                    branding.name,
                    branding.primary_color,
                    branding.secondary_color,
                    branding.logo or '',
                    branding.open or 1,
                    branding.tax or 0.05
                }
            )
        end
    end
end

-- ============================================================================
-- Management: GET payload
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:get', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    
    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not a mechanic.' })
        return
    end

    -- Branding
    local brand = MySQL.single.await(
        'SELECT name, primary_color, secondary_color, logo, open, tax FROM pf_business WHERE business = ? LIMIT 1',
        { businessKey }
    ) or {}

    -- POS Catalog
    local posRows = MySQL.query.await(
        'SELECT item_id, category, label, price FROM pf_pos_items WHERE business = ? ORDER BY category, label',
        { businessKey }
    ) or {}
    local catalog = buildCatalog(posRows)

    -- Employees list (pf_employees is the roster; online + onduty pulled from framework)
    local empRows = MySQL.query.await(
        'SELECT citizenid, grade, salary, avatar FROM pf_employees WHERE business = ? ORDER BY grade DESC',
        { businessKey }
    ) or {}

    local onlinePlayers = QBCore.Functions.GetQBPlayers()
    local onlineIndex = {}
    for _, p in pairs(onlinePlayers) do
        local pd = p.PlayerData
        if pd and pd.citizenid then onlineIndex[pd.citizenid] = p end
    end

    local employees, onDuty, total = {}, 0, 0
    for _, e in ipairs(empRows) do
        total = total + 1
        local name = getNameFromPlayersTable(e.citizenid)
        local p = onlineIndex[e.citizenid]
        local online = p ~= nil
        local duty = online and p.PlayerData.job and (p.PlayerData.job.onduty == true) or false
        if duty then onDuty = onDuty + 1 end

        employees[#employees + 1] = {
            cid = e.citizenid,
            name = name,
            grade = tonumber(e.grade) or 0,
            salary = tonumber(e.salary) or 0,
            avatar = e.avatar or '',
            online = online,
            duty = duty
        }
    end

    -- Metrics
    local today = MySQL.single.await(
        [[SELECT COALESCE(SUM(amount),0) AS amt, COUNT(*) AS cnt
          FROM pf_sales WHERE business = ? AND DATE(created_at) = CURDATE()]],
        { businessKey }
    ) or { amt = 0, cnt = 0 }

    local month = MySQL.single.await(
        [[SELECT COALESCE(SUM(amount),0) AS amt
          FROM pf_sales WHERE business = ? AND DATE_FORMAT(created_at, '%Y-%m') = DATE_FORMAT(CURDATE(), '%Y-%m')]],
        { businessKey }
    ) or { amt = 0 }

    local weekBars = MySQL.query.await(
        [[SELECT DATE(created_at) AS day, COALESCE(SUM(amount),0) AS total
            FROM pf_sales
            WHERE business = ? AND created_at >= DATE_SUB(CURDATE(), INTERVAL 6 DAY)
            GROUP BY DATE(created_at)
            ORDER BY day ASC]],
        { businessKey }
    ) or {}

    local canEdit = isBoss(Player)

    TriggerClientEvent('pf_mech:mgmt:get:resp', src, {
        canEdit   = canEdit,
        branding  = {
            name = brand.name or Config.DEFAULT_BRANDING.name,
            primary = brand.primary_color or Config.DEFAULT_BRANDING.primary_color,
            secondary = brand.secondary_color or Config.DEFAULT_BRANDING.secondary_color,
            logo = brand.logo or '',
            open = tonumber(brand.open or 1),
            tax = tonumber(brand.tax or Config.DEFAULT_BRANDING.tax or 0.05)
        },
        catalog   = catalog,
        employees = employees,
        headcount = { on = onDuty, total = total },
        npcOn     = false, -- client overrides with personal toggle
        metrics   = {
            todayTotal  = tonumber(today.amt) or 0,
            todayOrders = tonumber(today.cnt) or 0,
            monthTotal  = tonumber(month.amt) or 0,
            weeklyBars  = weekBars
        }
    })
end)


-- ── Safe defaults (in case Config.DEFAULT_BRANDING is missing) ────────────────
local DEFAULT_BRANDING = (Config and Config.DEFAULT_BRANDING) or {
    name = 'Mechanic Shop',
    primary_color   = '#0BA378',
    secondary_color = '#0B2E44',
    logo = '',
    tax  = 5,   -- percent
    open = 1
}

-- ============================================================================
-- Management: Save Branding
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:saveBranding', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then return end

    local branding = Config.BusinessBranding[businessKey] or {}
    local name  = (data and data.name) or branding.name
    local prim  = (data and data.primary_color) or branding.primary_color
    local sec   = (data and data.secondary_color) or branding.secondary_color
    local logo  = (data and data.logo) or ''
    local open  = (data and data.open) and 1 or 0
    local tax   = tonumber(data and data.tax) or (branding.tax or 0.05)

    MySQL.execute.await(
        [[INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            name = VALUES(name), primary_color = VALUES(primary_color), secondary_color = VALUES(secondary_color),
            logo = VALUES(logo), open = VALUES(open), tax = VALUES(tax)]],
        { businessKey, name, prim, sec, logo, open, tax }
    )

    TriggerClientEvent('pf_mech:toast', src, { text = 'Branding saved.' })
    -- Re-send payload so UI updates
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- Management: Update Catalog Price
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:updatePrice', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Invalid job.' })
        return
    end

    local itemId = payload and payload.item_id
    local label  = payload and payload.label or ''
    local price  = tonumber(payload and payload.price) or 0
    if not itemId or itemId == '' then return end

    local row = MySQL.single.await(
        'SELECT item_id FROM pf_pos_items WHERE business = ? AND item_id = ? LIMIT 1',
        { businessKey, itemId }
    )

    if row then
        MySQL.update.await(
            'UPDATE pf_pos_items SET label = ?, price = ? WHERE business = ? AND item_id = ?',
            { label, price, businessKey, itemId }
        )
    else
        MySQL.insert.await(
            'INSERT INTO pf_pos_items (business, item_id, category, label, price) VALUES (?, ?, ?, ?, ?)',
            { businessKey, itemId, 'General', label, price }
        )
    end

    TriggerClientEvent('pf_mech:toast', src, { text = ('Price updated: %s'):format(label) })
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- Management: Update Employee (grade/salary/avatar)
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:updateEmployee', function(p)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not isBoss(Player) then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Not allowed.' })
        return
    end
    if not p or not p.cid then return end

    local businessKey = getPlayerBusiness(Player)
    if not businessKey then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Invalid job.' })
        return
    end

    local grade  = tonumber(p.grade) or 0
    local salary = tonumber(p.salary) or 0
    local avatar = p.avatar or ''

    MySQL.execute.await(
        [[INSERT INTO pf_employees (citizenid, business, grade, salary, avatar)
            VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE grade = VALUES(grade), salary = VALUES(salary), avatar = VALUES(avatar)]],
        { p.cid, businessKey, grade, salary, avatar }
    )

    local Target = QBCore.Functions.GetPlayerByCitizenId(p.cid)
    if Target and Target.PlayerData and Target.PlayerData.job
        and Config.IsMechanicJob(Target.PlayerData.job.name) then
        Target.Functions.SetJob(Target.PlayerData.job.name, grade)
    end

    TriggerClientEvent('pf_mech:toast', src, { text = 'Employee saved.' })
    TriggerClientEvent('pf_mech:mgmt:get', src)
end)

-- ============================================================================
-- POS: request charge / pay
-- ============================================================================

-- Ask a target to pay (shows NUI payment modal on their client)
RegisterNetEvent('pos:requestCharge', function(data)
    local src = source
    local targetSrc = tonumber(data and data.targetSrc) or 0
    if targetSrc <= 0 then targetSrc = src end

    local items = (data and data.cart and data.cart.items) or {}
    local subtotal = 0
    for _, it in ipairs(items) do
        subtotal = subtotal + ((tonumber(it.price) or 0) * (tonumber(it.qty) or 1))
    end

    local seller = QBCore.Functions.GetPlayer(src)
    local businessKey = getPlayerBusiness(seller) or (Config.DEFAULT_BRANDING.business)
    local brand = MySQL.single.await(
        'SELECT tax FROM pf_business WHERE business = ? LIMIT 1',
        { businessKey }
    ) or {}
    local taxRate = tonumber(brand.tax or Config.DEFAULT_BRANDING.tax or 0.05)
    local tax = math.floor((subtotal * taxRate) + 0.5)
    local total = subtotal + tax

    local invoice = {
        id = ('%s-%d-%d'):format(businessKey, src, os.time()),
        business = businessKey,
        from = src,
        to = targetSrc,
        items = items,
        subtotal = subtotal,
        tax = tax,
        total = total
    }
    TriggerClientEvent('pos:payPrompt', targetSrc, invoice)
end)

-- Customer accepts/declines & payment method
RegisterNetEvent('pos:customerPay', function(data)
    local src = source
    local invoiceId = data and data.invoiceId
    local accept = data and data.accept
    local method = data and data.method or 'cash'
    if not invoiceId then return end

    local inv = data -- the client sends back the same structure
    if not inv or not accept then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Payment declined.' })
        return
    end

    local payer = QBCore.Functions.GetPlayer(src)
    local seller = QBCore.Functions.GetPlayer(inv.from)
    if not payer then return end

    if method == 'cash' then
        if not payer.Functions.RemoveMoney('cash', inv.total, 'mechanic-pos') then
            TriggerClientEvent('pf_mech:toast', src, { text = 'Not enough cash.' })
            return
        end
        if seller then seller.Functions.AddMoney('cash', inv.total, 'mechanic-pos') end
    else
        if not payer.Functions.RemoveMoney('bank', inv.total, 'mechanic-pos') then
            TriggerClientEvent('pf_mech:toast', src, { text = 'Card declined.' })
            return
        end
        if seller then seller.Functions.AddMoney('bank', inv.total, 'mechanic-pos') end
    end

    local businessKey = inv.business or (seller and getPlayerBusiness(seller)) or Config.DEFAULT_BRANDING.business
    MySQL.insert.await(
        'INSERT INTO pf_sales (business, src, target, amount, tax, total, created_at) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        { businessKey, inv.from or 0, inv.to or src, inv.subtotal or 0, inv.tax or 0, inv.total or 0 }
    )

    TriggerClientEvent('pf_mech:toast', src, { text = 'Paid ' .. tostring(inv.total) })
    if inv.from then TriggerClientEvent('pf_mech:toast', inv.from, { text = 'Payment received.' }) end
    TriggerClientEvent('pay:close', src)
    if inv.from then TriggerClientEvent('pay:close', inv.from) end
end)

-- ============================================================================
-- Employee personal earnings (for the “Earnings” app)
-- ============================================================================

RegisterNetEvent('pf_mech:earnings:get', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local cid = Player.PlayerData.citizenid
    -- NPC/local jobs & player jobs should be written to pf_job_history by your job logic.
    -- We aggregate by created_at date.
    local rows = MySQL.query.await(
        [[SELECT DATE(created_at) AS day,
                 COALESCE(SUM(CASE WHEN type='npc' THEN amount ELSE 0 END),0)  AS npc_total,
                 COALESCE(SUM(CASE WHEN type='player' THEN amount ELSE 0 END),0) AS cust_total
            FROM pf_job_history
           WHERE citizenid = ?
           GROUP BY DATE(created_at)
           ORDER BY day ASC
           LIMIT 14]],
        { cid }
    ) or {}

    local today = 0
    local week  = 0
    local month = 0
    local bars  = {}

    for _, r in ipairs(rows) do
        local dayTotal = (tonumber(r.npc_total) or 0) + (tonumber(r.cust_total) or 0)
        bars[#bars+1] = { day = r.day, total = dayTotal }
        -- naive sums (you may want proper date ranges)
        today = dayTotal -- last row assumed latest day
        week  = week + dayTotal
        month = month + dayTotal
    end

    TriggerClientEvent('pf_mech:earnings:resp', src, {
        today = today or 0,
        week  = week  or 0,
        month = month or 0,
        bars  = bars
    })
end)

local function serverClock()
    local h = tonumber(os.date('%H'))
    local m = tonumber(os.date('%M'))
    return h, m
end

local npcEnabled = {}  -- [src] = true/false

RegisterNetEvent('pf_mech:npc:toggle', function(on)
    local src = source
    npcEnabled[src] = on and true or false
    print(('[pf-mech] %d npcEnabled=%s'):format(src, tostring(npcEnabled[src])))

    if npcEnabled[src] then
        -- kick a tick for this player
        startNpcFeedFor(src)
    else
        stopNpcFeedFor(src)
    end

    -- (optional) echo state to their UI
    TriggerClientEvent('pf_mech:npc:updateJobs', src, {
        jobsNew = {}, jobsActive = {}, profile = { xp = 0, rank = 1 }, thresholds = { 0, 200, 450, 800 }
    })
end)

RegisterNetEvent('pf_mech:npc:refresh', function()
    local src = source
    -- send current jobs/state
    TriggerClientEvent('pf_mech:npc:updateJobs', src, {
        jobsNew = {}, jobsActive = {}, profile = { xp = 0, rank = 1 }, thresholds = { 0, 200, 450, 800 }
    })
end)

-- Stubbed helpers (replace with your real job logic)
function startNpcFeedFor(src)
    -- TODO: create/assign jobs and push with pf_mech:npc:updateJobs
end
function stopNpcFeedFor(src)
    -- TODO: clear timers / pending jobs
end

AddEventHandler('playerDropped', function(_, src)
    npcEnabled[src] = nil
    stopNpcFeedFor(src)
end)

-- Register performance parts
local performanceParts = {
    "engine1", "engine2", "engine3", "engine4", "engine5",
    "brakes1", "brakes2", "brakes3",
    "transmission1", "transmission2", "transmission3",
    "suspension1", "suspension2", "suspension3", "suspension4",
    "armor1", "armor2", "armor3", "armor4", "armor5",
    "turbo"
}

for _, item in ipairs(performanceParts) do
    QBCore.Functions.CreateUseableItem(item, function(source)
        local Player = QBCore.Functions.GetPlayer(source)
        if Player.PlayerData.job.name == "mechanic" then
            -- This will trigger the client-side event to handle the part installation
            TriggerClientEvent('pf_mech:tryUsePart', source, item)
        else
            TriggerClientEvent('QBCore:Notify', source, 'You are not a mechanic!', 'error')
        end
    end)
end

RegisterNetEvent('pf_mech:usePart', function(itemName, vehNetId, jobId, px, py, pz, extra)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Check if player has the item
    local item = Player.Functions.GetItemByName(itemName)
    if not item then 
        TriggerClientEvent('QBCore:Notify', src, 'Missing required part', 'error')
        return 
    end

    -- Remove item after successful installation
    if Player.Functions.RemoveItem(itemName, 1) then
        -- Apply the part effect
        TriggerClientEvent('pf_mech:applyPart', -1, {
            net = vehNetId,
            action = Config.PartRules[itemName].action,
            toast = 'Successfully installed ' .. itemName:gsub('_', ' ')
        })

        -- Add experience/job data here if needed
    else
        TriggerClientEvent('QBCore:Notify', src, 'Failed to install part', 'error')
    end
end)

-- map partKey -> item name used in inventory (ADD MISSING ENTRIES)
local PartToItem = {
  engine_part = 'engine_part',
  body_part   = 'body_part',
  sparkplugs  = 'sparkplugs',
  carbattery  = 'carbattery',
  alternator  = 'alternator',
  engine_oil  = 'engine_oil',
  oil_filter  = 'oil_filter',
  susp_arm    = 'susp_arm',
  axleparts   = 'axleparts',
  tire_new    = 'tire_new',
  brakes      = 'brake_pads',       -- FIX: brakes uses brake_pads item
  fuel_injector = 'fuel_injector',  -- NEW
  powersteeringpump = 'powersteeringpump', -- NEW
  radiator    = 'radiator',         -- NEW
  power_steering_fluid = 'power_steering_fluid', -- NEW
  transmissionfluid = 'transmissionfluid', -- NEW
  brakefluid  = 'brakefluid',       -- NEW
  coolant     = 'coolant',          -- NEW
}

-- map partKey -> data used when applying repair to clients (ADD MISSING ENTRIES)
local PartApplyInfo = {
  engine_part = { action = 'repair', type = 'engine' },
  body_part   = { action = 'repair', type = 'body' },
  sparkplugs  = { action = 'repair', type = 'sparkplugs' },
  carbattery  = { action = 'repair', type = 'battery' },
  alternator  = { action = 'repair', type = 'alternator' },
  engine_oil  = { action = 'repair', type = 'oil' },
  oil_filter  = { action = 'repair', type = 'oil_filter' },
  susp_arm    = { action = 'repair', type = 'suspension' },
  axleparts   = { action = 'repair', type = 'axle' },
  tire_new    = { action = 'tire',   type = 'tire' },
  brakes      = { action = 'repair', type = 'brakes' },       -- NEW
  fuel_injector = { action = 'repair', type = 'fuel_injector' }, -- NEW
  powersteeringpump = { action = 'repair', type = 'powersteeringpump' }, -- NEW
  radiator    = { action = 'repair', type = 'radiator' },     -- NEW
  power_steering_fluid = { action = 'repair', type = 'power_steering_fluid' }, -- NEW
  transmissionfluid = { action = 'repair', type = 'transmissionfluid' }, -- NEW
  brakefluid  = { action = 'repair', type = 'brakefluid' },   -- NEW
  coolant     = { action = 'repair', type = 'coolant' },      -- NEW
}

-- callback used by client to attempt a repair (consumes items and broadcasts apply)
QBCore.Functions.CreateCallback('pf_mech:server:attemptRepair', function(source, cb, vehNetId, partKey, needed, wheel)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then cb(false, 'Player not found'); return end

    local itemName = PartToItem[partKey] or partKey
    local count = tonumber(needed) or 1

    local item = Player.Functions.GetItemByName(itemName)
    if not item or (item.amount or 0) < count then
        cb(false, 'You do not have enough items')
        return
    end

    local removed = Player.Functions.RemoveItem(itemName, count)
    if not removed then
        cb(false, 'Failed to remove items')
        return
    end

    -- NEW: Get the vehicle entity and update partDamage directly on server
    local veh = NetworkGetEntityFromNetworkId(vehNetId)
    if veh and DoesEntityExist(veh) then
        local state = Entity(veh).state
        local damage = state.partDamage or {}
        
        -- Repair the specific part
        if partKey == 'alternator' then
            damage.alternator = 0
        elseif partKey == 'engine_oil' or partKey == 'oil' then
            damage.oil = 0
        elseif partKey == 'oil_filter' then
            damage.oil_filter = 0
        elseif partKey == 'carbattery' then
            damage.carbattery = 0
        elseif partKey == 'sparkplugs' then
            damage.sparkplugs = math.max(0, (damage.sparkplugs or 0) - (20 * count))
        elseif partKey == 'brakes' or partKey == 'brake_pads' then
            damage.brakes = math.max(0, (damage.brakes or 0) - (25 * count))
        elseif partKey == 'susp_arm' then
            damage.suspension = math.max(0, (damage.suspension or 0) - (25 * count))
        elseif partKey == 'axleparts' then
            damage.axle = math.max(0, (damage.axle or 0) - (25 * count))
        elseif partKey == 'fuel_injector' then
            damage.fuel_injector = math.max(0, (damage.fuel_injector or 0) - (25 * count))
        elseif partKey == 'powersteeringpump' then
            damage.powersteeringpump = 0
        elseif partKey == 'radiator' then
            damage.radiator = 0
        elseif partKey == 'power_steering_fluid' then
            damage.power_steering_fluid = 0
        elseif partKey == 'transmissionfluid' then
            damage.transmissionfluid = 0
        elseif partKey == 'brakefluid' then
            damage.brakefluid = 0
        elseif partKey == 'coolant' then
            damage.coolant = 0
        elseif partKey == 'engine_part' then
            -- Engine part reduces engine damage (not body)
            damage.engine = math.max(0, (damage.engine or 0) - (15 * count))
        elseif partKey == 'body_part' then
            -- Body part reduces body damage (not engine)
            damage.body = math.max(0, (damage.body or 0) - (20 * count))
        end
        
        -- Update the state
        state:set('partDamage', damage, true)
    end

    local info = PartApplyInfo[partKey] or { action = 'repair', type = partKey }
    local toast = ('%s x%d used'):format(item.label or itemName, count)
    local payload = { net = vehNetId, action = info.action, type = info.type, toast = toast, wheel = wheel, qty = count }

    TriggerClientEvent('pf_mech:applyPart', -1, payload)

    cb(true, 'Repair completed')
end)

-- Register useable items
local function RegisterItems()
    local cosmeticItems = {
        'spoiler',
        'bumper',
        'skirts',
        'exhaust',
        'rollcage',
        'hood',
        'roof'
    }
    
    local paintItems = {
        'paint_kit',
        'tint_supplies'
    }
    
    local wheelItems = {
        'rims'
    }
    
    -- CHANGED: require toolbox for all
    for _, item in ipairs(cosmeticItems) do
        QBCore.Functions.CreateUseableItem(item, function(source, itemInfo)
            if not playerHasToolbox(source) then
                TriggerClientEvent('QBCore:Notify', source, 'You need a toolbox to do mechanic work', 'error')
                return
            end
            TriggerClientEvent('pf-mechanicjob:client:usePart', source, itemInfo)
        end)
    end
    
    for _, item in ipairs(paintItems) do
        QBCore.Functions.CreateUseableItem(item, function(source, itemInfo)
            if not playerHasToolbox(source) then
                TriggerClientEvent('QBCore:Notify', source, 'You need a toolbox to do mechanic work', 'error')
                return
            end
            if item == 'paint_kit' then
                TriggerClientEvent('pf-mechanicjob:client:usePaint', source, item)
            else
                TriggerClientEvent('pf-mechanicjob:client:usePart', source, itemInfo)
            end
        end)
    end
    
    for _, item in ipairs(wheelItems) do
        QBCore.Functions.CreateUseableItem(item, function(source, itemInfo)
            if not playerHasToolbox(source) then
                TriggerClientEvent('QBCore:Notify', source, 'You need a toolbox to do mechanic work', 'error')
                return
            end
            TriggerClientEvent('pf-mechanicjob:client:useWheels', source, item)
        end)
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RegisterItems()
    end
end)

RegisterNetEvent('pf_mech:server:removeMod', function(item)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    Player.Functions.RemoveItem(item, 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[item], "remove")
end)

-- Server-side: apply cosmetic mod (called from client after progress completes)
RegisterNetEvent('pf_mech:server:applyMod', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not data then return end

    local itemName = data.item
    local modType  = data.modType
    local modIndex = data.modIndex
    local vehicleNet = data.vehicle

    -- verify item exists in inventory
    local item = Player.Functions.GetItemByName(itemName)
    if not item then
        TriggerClientEvent('QBCore:Notify', src, 'Missing required item: ' .. tostring(itemName), 'error')
        return
    end

    -- remove 1 item
    local removed = Player.Functions.RemoveItem(itemName, 1)
    if not removed then
        TriggerClientEvent('QBCore:Notify', src, 'Failed to remove item: ' .. tostring(itemName), 'error')
        return
    end

    -- Broadcast to all clients to apply the mod (keeps visuals in sync)
    TriggerClientEvent('pf_mech:client:modApplied', -1, {
        vehicle = vehicleNet,
        modType = modType,
        modIndex = modIndex
    })

    -- Show item box to user who used the item
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

-- Server: apply paint/tint (consumes 1 paint_kit or tint_supplies)
RegisterNetEvent('pf_mech:server:applyPaint', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not payload or not payload.item then return end

    local itemName = payload.item
    local it = Player.Functions.GetItemByName(itemName)
    if not it then
        TriggerClientEvent('QBCore:Notify', src, 'Missing required item: '..tostring(itemName), 'error')
        return
    end

    local removed = Player.Functions.RemoveItem(itemName, 1)
    if not removed then
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume '..tostring(itemName), 'error')
        return
    end

    -- Broadcast to all clients
    TriggerClientEvent('pf_mech:client:paintApplied', -1, {
        vehicle = payload.vehicle,
        item = itemName,
        category = payload.category,
        rgb = payload.rgb,
        preset = payload.preset,
        tintLevel = payload.tintLevel
    })

    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

-- Server: apply wheel mod
RegisterNetEvent('pf_mech:server:applyWheels', function(payload)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not payload or not payload.item then return end

    local itemName = payload.item
    local it = Player.Functions.GetItemByName(itemName)
    if not it then
        TriggerClientEvent('QBCore:Notify', src, 'Missing required item: '..tostring(itemName), 'error')
        return
    end

    local removed = Player.Functions.RemoveItem(itemName, 1)
    if not removed then
        TriggerClientEvent('QBCore:Notify', src, 'Failed to consume '..tostring(itemName), 'error')
        return
    end

    -- Broadcast to all clients
    TriggerClientEvent('pf_mech:client:wheelsApplied', -1, {
        vehicle = payload.vehicle,
        wheelType = payload.wheelType,
        wheelIndex = payload.wheelIndex,
        wheelColor = payload.wheelColor
    })

    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], "remove")
end)

-- Service Book: add entry
RegisterNetEvent('pf_mech:service:addEntry', function(plate, note)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    plate = tostring(plate or ''):upper():gsub('%s+', '')
    note = tostring(note or ''):sub(1, 500)
    if plate == '' or note == '' then
        TriggerClientEvent('pf_mech:toast', src, { text = 'Missing plate or note.' })
        return
    end
    local cid = Player.PlayerData.citizenid
    local author = getNameFromPlayersTable(cid)

    MySQL.insert.await(
        'INSERT INTO pf_service_log (plate, citizenid, author, note, created_at) VALUES (?, ?, ?, ?, NOW())',
        { plate, cid, author, note }
    )
    TriggerClientEvent('pf_mech:toast', src, { text = 'Service entry saved.' })
end)

-- Service Book: get entries
QBCore.Functions.CreateCallback('pf_mech:service:get', function(source, cb, plate)
    plate = tostring(plate or ''):upper():gsub('%s+', '')
    if plate == '' then cb({}) return end
    local rows = MySQL.query.await(
        'SELECT author, note, DATE_FORMAT(created_at,"%Y-%m-%d %H:%i") AS at FROM pf_service_log WHERE plate = ? ORDER BY created_at DESC LIMIT 20',
        { plate }
    ) or {}
    cb(rows)
end)

-- Helper: ensure all businesses exist in database
local function ensureAllBusinesses()
    for jobName, branding in pairs(Config.BusinessBranding or {}) do
        local row = MySQL.single.await('SELECT business FROM pf_business WHERE business = ? LIMIT 1', { branding.business })
        if not row then
            MySQL.insert.await(
                'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',
                {
                    branding.business,
                    branding.name,
                    branding.primary_color,
                    branding.secondary_color,
                    branding.logo or '',
                    branding.open or 1,
                    branding.tax or 0.05
                }
            )
        end
    end
end

-- END OF FILE

-- Allow clients to request a server-side statebag write (fallback for older artifacts)
RegisterNetEvent('pf_mech:server:setState', function(netId, key, value)
    local src = source
    if not netId or not key then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return end

    -- Optional: only allow driver/nearby or owner – kept simple here.
    local st = Entity(ent).state
    if st and st.set then
        st:set(tostring(key), value, true)
    end
end)

-- Relay welding VFX start/stop to all clients (sync prop net id)
RegisterNetEvent('pf_mech:weld:start', function(netId)
    if not netId then return end
    -- Broadcast to all clients
    TriggerClientEvent('pf_mech:weld:start', -1, netId)
end)

RegisterNetEvent('pf_mech:weld:stop', function(netId)
    if not netId then return end
    TriggerClientEvent('pf_mech:weld:stop', -1, netId)
end)

RegisterNetEvent('pf_mech:vfx:oneshot', function(data)
    -- Optionally validate payload here
    TriggerClientEvent('pf_mech:vfx:oneshot', -1, data)
end)

-- NEW: Check if player has toolbox in inventory
QBCore.Functions.CreateCallback('pf_mech:hasToolbox', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false); return end
    
    local item = Player.Functions.GetItemByName('toolbox')
    cb(item ~= nil)
end)

-- =========================
-- PREVIEW RECEIPT GENERATION
-- =========================
RegisterNetEvent('pf_mech:server:generatePreviewReceipt', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Build description from modifications
    local desc = 'Vehicle Preview Modifications:\n\n'
    if data.modifications and #data.modifications > 0 then
        for _, mod in ipairs(data.modifications) do
            desc = desc .. string.format('• %s: %s\n', mod.category or 'Unknown', mod.value or 'None')
        end
    else
        desc = desc .. 'No modifications previewed.\n'
    end
    
    desc = desc .. string.format('\nVehicle: %s\nPlate: %s\n', data.vehicleModel or 'Unknown', data.plate or 'Unknown')
    desc = desc .. string.format('Previewed by: %s [%s]\nDate: %s', 
        Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname,
        Player.PlayerData.citizenid,
        os.date('%Y-%m-%d %H:%M:%S')
    )

    -- Give receipt item if enabled and item exists
    if Config.PreviewReceipt.enabled and Config.PreviewReceipt.itemName then
        local info = {
            description = desc,
            modifications = data.modifications or {},
            vehicle = data.vehicleModel or 'Unknown',
            plate = data.plate or 'Unknown',
            timestamp = os.time()
        }
        Player.Functions.AddItem(Config.PreviewReceipt.itemName, 1, false, info)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.PreviewReceipt.itemName], 'add', 1)
    end

    -- Send Discord webhook if configured
    if Config.PreviewReceipt.webhookURL and Config.PreviewReceipt.webhookURL ~= '' then
        local embed = {
            {
                ['title'] = Config.PreviewReceipt.webhookTitle or '🔧 Vehicle Preview Receipt',
                ['color'] = Config.PreviewReceipt.webhookColor or 3447003,
                ['description'] = desc,
                ['footer'] = {
                    ['text'] = Config.PreviewReceipt.webhookFooter or 'Preview System'
                },
                ['timestamp'] = os.date('!%Y-%m-%dT%H:%M:%S')
            }
        }
        
        PerformHttpRequest(Config.PreviewReceipt.webhookURL, function(err, text, headers) end, 'POST', json.encode({
            username = 'Mechanic Preview System',
            embeds = embed
        }), { ['Content-Type'] = 'application/json' })
    end
end)

RegisterNetEvent('pf_mech:givePreviewReceipt', function(receiptData)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not receiptData then return end
    
    -- Build description from changes
    local desc = string.format('Preview Session - %s (%s)\n', 
        receiptData.vehicle or 'Unknown', 
        receiptData.plate or 'N/A'
    )
    desc = desc .. string.format('Date: %s\n', os.date('%Y-%m-%d %H:%M:%S', receiptData.timestamp))
    desc = desc .. string.format('Changes Made: %d\n\n', receiptData.changeCount)
    
    for i, change in ipairs(receiptData.changes) do
        desc = desc .. string.format('%d. %s\n', i, change.name)
        desc = desc .. string.format('   From: %s\n', change.from)
        desc = desc .. string.format('   To: %s\n', change.to)
    end
    
    -- Give receipt item with metadata
    local info = {
        description = desc,
        vehicle = receiptData.vehicle,
        plate = receiptData.plate,
        timestamp = receiptData.timestamp,
        changes = receiptData.changeCount
    }
    
    Player.Functions.AddItem(Config.PreviewReceipt.itemName, 1, false, info)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.PreviewReceipt.itemName], 'add')
    
    -- Optional: Discord webhook
    if Config.PreviewReceipt.webhookURL and Config.PreviewReceipt.webhookURL ~= '' then
        local embed = {
            {
                ['title'] = Config.PreviewReceipt.webhookTitle,
                ['color'] = Config.PreviewReceipt.webhookColor,
                ['footer'] = {['text'] = Config.PreviewReceipt.webhookFooter},
                ['description'] = desc,
                ['fields'] = {
                    {['name']='Player', ['value']=GetPlayerName(src), ['inline']=true},
                    {['name']='ID', ['value']=tostring(src), ['inline']=true},
                    {['name']='Changes', ['value']=tostring(receiptData.changeCount), ['inline']=true},
                }
            }
        }
        PerformHttpRequest(Config.PreviewReceipt.webhookURL, function() end, 'POST', 
            json.encode({embeds = embed}), {['Content-Type'] = 'application/json'})
    end
end)

-- Give modification sheet / preview receipt
RegisterNetEvent('pf_mech:giveModificationSheet', function(data)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Use item name from config, default to 'preview_receipt'
    local itemName = (Config.PreviewReceipt and Config.PreviewReceipt.itemName) or 'preview_receipt'
    
    local info = {
        vehicle = data.vehicle or "Unknown Vehicle",
        plate = data.plate or "N/A",
        description = data.description or "No changes recorded",
        timestamp = os.time()
    }

    -- Add the item with metadata
    Player.Functions.AddItem(itemName, 1, false, info)
    TriggerClientEvent('QBCore:Notify', src, 'Preview Receipt added to your inventory.', 'success')
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add', 1)
end)

-- ============================================================================
-- ROLLING COAL SYSTEM
-- ============================================================================

-- Set coal delete state for a vehicle
RegisterNetEvent('pf_mech:setCoalDelete', function(plate, enabled)
    local src = source
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    -- Verify player owns this vehicle
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local result = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not result or result.citizenid ~= Player.PlayerData.citizenid then
        TriggerClientEvent('QBCore:Notify', src, 'You do not own this vehicle', 'error')
        return
    end
    
    -- Update database (store in mods JSON)
    MySQL.update.await([[
        UPDATE player_vehicles 
        SET mods = JSON_SET(COALESCE(mods, '{}'), '$.coalDelete', ?)
        WHERE plate = ?
    ]], { enabled and true or false, plate })
    
    -- Broadcast to all clients (so they see the smoke)
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, enabled)
    
    if Config.Debug then
        print(string.format('[COAL] %s coal delete %s for %s', 
            Player.PlayerData.name, 
            enabled and 'enabled' or 'disabled', 
            plate))
    end
end)

-- Load coal delete state on vehicle spawn
QBCore.Functions.CreateCallback('pf_mech:getCoalState', function(source, cb, plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then cb(false); return end
    
    local result = MySQL.single.await('SELECT mods FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    
    if result and result.mods then
        local mods = json.decode(result.mods)
        cb(mods and mods.coalDelete or false)
    else
        cb(false)
    end
end)

-- ============================================================================
-- ROLLING COAL SYSTEM (SERVER SYNC)
-- ============================================================================

-- Sync coal particles to all clients
RegisterNetEvent('pf_mech:coal:syncStart', function(netId)
    if not (Config.RollingCoal and Config.RollingCoal.enabled) then return end
    TriggerClientEvent('pf_mech:coal:startParticles', -1, netId)
end)

RegisterNetEvent('pf_mech:coal:syncStop', function(netId)
    TriggerClientEvent('pf_mech:coal:stopParticles', -1, netId)
end)

-- Set coal delete state for a vehicle
RegisterNetEvent('pf_mech:setCoalDelete', function(plate, enabled)
    local src = source
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then return end
    
    -- Verify player owns this vehicle
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    
    local result = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    if not result or result.citizenid ~= Player.PlayerData.citizenid then
        TriggerClientEvent('QBCore:Notify', src, 'You do not own this vehicle', 'error')
        return
    end
    
    -- Update database (store in mods JSON)
    MySQL.update.await([[
        UPDATE player_vehicles 
        SET mods = JSON_SET(COALESCE(mods, '{}'), '$.coalDelete', ?)
        WHERE plate = ?
    ]], { enabled and true or false, plate })
    
    -- Broadcast to all clients (so they see the smoke)
    TriggerClientEvent('pf_mech:syncCoalDelete', -1, plate, enabled)
    
    if Config.Debug then
        print(string.format('[COAL] %s coal delete %s for %s', 
            Player.PlayerData.name, 
            enabled and 'enabled' or 'disabled', 
            plate))
    end
end)

-- Load coal delete state on vehicle spawn
QBCore.Functions.CreateCallback('pf_mech:getCoalState', function(source, cb, plate)
    plate = tostring(plate or ''):gsub('%s+', ''):upper()
    if plate == '' then cb(false); return end
    
    local result = MySQL.single.await('SELECT mods FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
    
    if result and result.mods then
        local mods = json.decode(result.mods)
        cb(mods and mods.coalDelete or false)
    else
        cb(false)
    end
end)

RegisterServerEvent("Smoke:SyncStartParticles")
AddEventHandler("Smoke:SyncStartParticles", function(carid)
    TriggerClientEvent("Smoke:StartParticles", -1, carid)
end)

RegisterServerEvent("Smoke:SyncStopParticles")
AddEventHandler("Smoke:SyncStopParticles", function(carid)
    TriggerClientEvent("Smoke:StopParticles", -1, carid)
end)

-- Rolling coal particle relays
RegisterNetEvent('pf_mech:coal:syncStart', function(netId)
    if not Config.RollingCoal.enabled then return end
    
    -- NEW: Debug
    if Config.Debug then
        print(string.format('[COAL SERVER] Broadcasting start for netId: %s from source: %d', tostring(netId), source))
    end
    
    TriggerClientEvent('pf_mech:coal:startParticles', -1, netId)
end)
RegisterNetEvent('pf_mech:coal:syncStop', function(netId)
    -- NEW: Debug
    if Config.Debug then
        print(string.format('[COAL SERVER] Broadcasting stop for netId: %s', tostring(netId)))
    end
    
    TriggerClientEvent('pf_mech:coal:stopParticles', -1, netId)
end)

-- No diagnostics modifications needed (DPF & coal remain).

QBCore.Functions.CreateCallback('pf_mech:hasDPFItem', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then cb(false) return end
    local item = Player.Functions.GetItemByName(Config.DPFItem)
    cb(item ~= nil)
end)


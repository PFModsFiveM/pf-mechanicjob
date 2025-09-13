-- server/main.lua
-- PF Mechanic Job – Server
-- Framework: QBCore + oxmysql

local QBCore = exports['qb-core']:GetCoreObject()
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

local function isBoss(Player)
    if not Player or not Player.PlayerData or not Player.PlayerData.job then return false end
    local job = Player.PlayerData.job
    if job.name ~= (Config.Job or 'mechanic') then return false end
    if job.isboss then return true end
    local grade = tostring(job.grade and job.grade.level or job.grade or 0)
    return BossGrades[grade] == true
end

local function ensureBusiness()
    local bkey = (Config.DefaultBranding and Config.DefaultBranding.business) or (Config.Job or 'mechanic')
    local row = MySQL.single.await('SELECT business FROM pf_business WHERE business = ? LIMIT 1', { bkey })
    if not row then
        local d = Config.DefaultBranding or {}
        MySQL.insert.await(
            'INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { bkey, d.name or 'Mechanic Shop', d.primary_color or '#0BA378', d.secondary_color or '#0B2E44', d.logo or '', d.open or 1, d.tax or 0.05 }
        )
    end
end

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
    ensureBusiness()

    -- Seed POS items if empty
    local cnt = MySQL.scalar.await('SELECT COUNT(*) FROM pf_pos_items WHERE business = ?', { Config.DefaultBranding.business or (Config.Job or 'mechanic') }) or 0
    if cnt == 0 and Config.CatalogSeed then
        for _, it in ipairs(Config.CatalogSeed) do
            MySQL.insert.await(
                'INSERT INTO pf_pos_items (business, item_id, category, label, price) VALUES (?, ?, ?, ?, ?)',
                { Config.DefaultBranding.business or (Config.Job or 'mechanic'), it.id, it.category, it.label, it.price }
            )
        end
    end
end)

-- ============================================================================
-- Management: GET payload
-- ============================================================================

RegisterNetEvent('pf_mech:mgmt:get', function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    ensureBusiness()

    local businessKey = Config.DefaultBranding.business or (Config.Job or 'mechanic')

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
            name = brand.name or Config.DefaultBranding.name,
            primary = brand.primary_color or Config.DefaultBranding.primary_color,
            secondary = brand.secondary_color or Config.DefaultBranding.secondary_color,
            logo = brand.logo or '',
            open = tonumber(brand.open or 1),
            tax = tonumber(brand.tax or Config.DefaultBranding.tax or 0.05)
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

    ensureBusiness()
    local bkey = Config.DefaultBranding.business or (Config.Job or 'mechanic')

    local name  = (data and data.name) or Config.DefaultBranding.name
    local prim  = (data and data.primary_color) or Config.DefaultBranding.primary_color
    local sec   = (data and data.secondary_color) or Config.DefaultBranding.secondary_color
    local logo  = (data and data.logo) or ''
    local open  = (data and data.open) and 1 or 0
    local tax   = tonumber(data and data.tax) or (Config.DefaultBranding.tax or 0.05)

    MySQL.execute.await(
        [[INSERT INTO pf_business (business, name, primary_color, secondary_color, logo, open, tax)
            VALUES (?, ?, ?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE
            name = VALUES(name), primary_color = VALUES(primary_color), secondary_color = VALUES(secondary_color),
            logo = VALUES(logo), open = VALUES(open), tax = VALUES(tax)]],
        { bkey, name, prim, sec, logo, open, tax }
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
    local itemId = payload and payload.item_id
    local label  = payload and payload.label or ''
    local price  = tonumber(payload and payload.price) or 0
    if not itemId or itemId == '' then return end

    ensureBusiness()
    local bkey = Config.DefaultBranding.business or (Config.Job or 'mechanic')

    -- Find existing row
    local row = MySQL.single.await(
        'SELECT item_id FROM pf_pos_items WHERE business = ? AND item_id = ? LIMIT 1',
        { bkey, itemId }
    )

    if row then
        MySQL.update.await(
            'UPDATE pf_pos_items SET label = ?, price = ? WHERE business = ? AND item_id = ?',
            { label, price, bkey, itemId }
        )
    else
        -- Unknown item id -> insert under "General"
        MySQL.insert.await(
            'INSERT INTO pf_pos_items (business, item_id, category, label, price) VALUES (?, ?, ?, ?, ?)',
            { bkey, itemId, 'General', label, price }
        )
    end

    TriggerClientEvent('pf_mech:toast', src, { text = ('Price updated: %s'):format(label) })
    -- Refresh management + POS
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

    local bkey = Config.DefaultBranding.business or (Config.Job or 'mechanic')
    local grade  = tonumber(p.grade) or 0
    local salary = tonumber(p.salary) or 0
    local avatar = p.avatar or ''

    MySQL.execute.await(
        [[INSERT INTO pf_employees (citizenid, business, grade, salary, avatar)
            VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE grade = VALUES(grade), salary = VALUES(salary), avatar = VALUES(avatar)]],
        { p.cid, bkey, grade, salary, avatar }
    )

    -- If the player is online, also update their job grade (optional; comment if not desired)
    local Target = QBCore.Functions.GetPlayerByCitizenId(p.cid)
    if Target and Target.PlayerData and Target.PlayerData.job and Target.PlayerData.job.name == (Config.Job or 'mechanic') then
        Target.Functions.SetJob(Config.Job or 'mechanic', grade)
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

    local bkey = Config.DefaultBranding.business or (Config.Job or 'mechanic')
    local brand = MySQL.single.await('SELECT tax FROM pf_business WHERE business = ? LIMIT 1', { bkey }) or {}
    local taxRate = tonumber(brand.tax or Config.DefaultBranding.tax or 0.05)
    local tax = math.floor((subtotal * taxRate) + 0.5)
    local total = subtotal + tax

    local invoice = {
        id = ('%s-%d-%d'):format(bkey, src, os.time()),
        business = bkey,
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

    -- Simple money handling (adapt to your economy)
    if method == 'cash' then
        if payer.Functions.RemoveMoney('cash', inv.total, 'mechanic-pos') then
            if seller then seller.Functions.AddMoney('cash', inv.total, 'mechanic-pos') end
        else
            TriggerClientEvent('pf_mech:toast', src, { text = 'Not enough cash.' })
            return
        end
    else -- card/bank
        if payer.Functions.RemoveMoney('bank', inv.total, 'mechanic-pos') then
            if seller then seller.Functions.AddMoney('bank', inv.total, 'mechanic-pos') end
        else
            TriggerClientEvent('pf_mech:toast', src, { text = 'Card declined.' })
            return
        end
    end

    -- Record sale
    MySQL.insert.await(
        'INSERT INTO pf_sales (business, src, target, amount, tax, total, created_at) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        { inv.business or (Config.DefaultBranding.business or (Config.Job or 'mechanic')), inv.from or 0, inv.to or src, inv.subtotal or 0, inv.tax or 0, inv.total or 0 }
    )

    TriggerClientEvent('pf_mech:toast', src,    { text = 'Paid ' .. tostring(inv.total) })
    TriggerClientEvent('pf_mech:toast', inv.from or 0, { text = 'Payment received.' })

    -- Close modal on both ends
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

-- ============================================================================
-- Small utilities for client
-- ============================================================================

-- Send in-game time every 1s to client who has tablet open (client asks for it)
CreateThread(function()
    while true do
        Wait(1000)
        for _, src in ipairs(GetPlayers()) do
            local h = GetClockHours()
            local m = GetClockMinutes()
            TriggerClientEvent('clock', tonumber(src), { h = h, m = m })
        end
    end
end)

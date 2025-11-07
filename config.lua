Config = Config or {}

-- ============================================================================
-- DEBUG (ALWAYS ON TOP)
-- ============================================================================
Config.Debug = true -- Set to true to see all debug notifications and console logs

-- ============================================================================
-- GARAGE SYSTEM COMPATIBILITY & GENERAL SETTINGS
-- ============================================================================
-- Supported values:
--   'qb-garages'  = QBCore's default garage system (default)
--   'cd_garages'  = Codesign's cd_garages (https://docs.codesign.pro/paid-scripts/garage)
-- Add more supported garage scripts here as needed.
Config.GarageSystem = 'cd_garages' -- or 'cd_garages'
Config.MenuSystem   = 'qb-menu'          -- 'qb-menu' or 'ox_lib'

-- Jobs allowed to use mechanic items (in addition to 'mechanic')
Config.AllowedJobs = {
    'mechanic',
    'mechanic2',
    'mechanic3',
    'bennys',
    'beeker',
    -- Add more jobs here as needed
}

-- Items that ANYONE can use (no job requirement)
Config.PublicItems = {
    'repair_kit',
}

-- ============================================================================
-- WEAR RATE TUNING
-- ============================================================================
Config.WearRates = {
    -- Brake wear multipliers
    brakes = {
        baselineRandomMin = 0.01,      -- Minimum random wear per tick when moving
        baselineRandomMax = 0.05,      -- Maximum random wear per tick when moving
        speedExtraStartMPH = 40,       -- Speed threshold where extra wear begins
        speedExtraScale = 0.004,       -- Wear per MPH above threshold
        sustainedBrakeInterval = 5000, -- MS holding brake for bonus wear
        sustainedBonus = 0.40,         -- Extra wear for sustained braking
        steeringAngleWearStart = 12.0, -- Degrees where cornering wear begins
        steeringAngleScale = 0.02,     -- Wear per degree above threshold
        handbrakePerTick = 0.35,       -- Wear per tick when handbrake is held
        burnoutExtra = 2.50,           -- Extra wear during burnouts (W+S)
        heatIncreasePerWear = 14,      -- Heat units gained per 1% wear
        heatDecayPerTick = 18,         -- Heat units lost per tick when not braking
        heatWearScale = 0.0009,        -- Extra wear = heat * scale
        downhillDecelThreshold = -0.65, -- Forward deceleration threshold
        downhillBonus = 0.30,          -- Extra wear on steep downhills
    },
    
    -- Radiator wear
    radiator = {
        bodyDamageScale = 0.08,        -- Wear per tick when body < 80%
        collisionDamage = 1.2,         -- Damage per collision at speed
        waterIngestionRate = 0.6,      -- Damage per tick in water
    },
    
    -- Coolant consumption
    coolant = {
        speedThreshold = 80.0,         -- MPH where loss begins
        speedLossBase = 0.05,          -- Base loss above threshold
        speedLossScale = 0.008,        -- Extra loss per MPH
        tempThreshold = 110.0,         -- Engine temp where loss accelerates
        tempLossScale = 0.04,          -- Loss per degree above threshold
        radiatorDamageThreshold = 40,  -- Radiator % where loss accelerates
        radiatorLossScale = 0.02,      -- Loss based on radiator damage
        waterContamination = 0.30,     -- Loss per tick in water
    },
    
    -- Suspension & Axle
    suspension = {
        airtimeSpeedThreshold = 15.0,  -- Speed when airborne causes damage
        airtimeScale = 0.80,           -- Damage per tick airborne (scaled by speed)
        suspensionAirtimeScale = 0.60, -- Suspension-specific airtime damage
        highSpeedWear = 0.08,          -- Wear per tick above 60 MPH
        mudWear = 0.35,                -- Wear per tick in mud
    },
    
    axle = {
        mudWear = 0.25,                -- Wear per tick in mud
    },
    
    -- Spark plugs
    sparkplugs = {
        mileagePerPercent = 250.0,     -- Miles needed for 1% damage
        overheatingTempThreshold = 120.0, -- Temp where damage begins
        overheatingScale = 0.03,       -- Damage per degree above threshold
        fireDamage = 3.5,              -- Damage per tick when on fire
        misfireThreshold = 50,         -- Damage % where misfires cause extra wear
        misfireChance = 8,             -- % chance per tick to misfire
        misfireDamage = 0.50,          -- Extra damage per misfire
        oilLeakThreshold = 30,         -- Oil health % where plugs suffer
        oilLeakScale = 0.02,           -- Damage based on low oil
    },
}

-- ============================================================================
-- JOB / SOCIETY (DYNAMIC)
-- ============================================================================
-- Helper function to check if a job is a mechanic job
function Config.IsMechanicJob(jobName)
    for _, j in ipairs(Config.AllowedJobs) do if j == jobName then return true end end
    return false
end
-- Get business key for a specific job (used for database lookups)
function Config.GetBusinessKey(jobName)
    local map = { mechanic='mechanic', mechanic2='mechanic2', mechanic3='mechanic3', bennys='bennys', beeker='beeker' }
    return map[jobName] or jobName
end

-- Default branding per business (used for initial seed)
Config.BusinessBranding = {
  mechanic = { business='mechanic', name='LS Customs', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  mechanic2= { business='mechanic2', name='LS Customs #2', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  mechanic3= { business='mechanic3', name='LS Customs #3', primary_color='#0BA378', secondary_color='#0B2E44', logo='', tax=0.05, open=1 },
  bennys   = { business='bennys',   name="Benny's Original Motor Works", primary_color='#8B0000', secondary_color='#2E0000', logo='', tax=0.05, open=1 },
  beeker   = { business='beeker',   name="Beeker's Garage", primary_color='#FF8C00', secondary_color='#3D2000', logo='', tax=0.05, open=1 },
}
Config.JobName = 'mechanic'
Config.Society = 'mechanic'
Config.DEFAULT_BRANDING = Config.BusinessBranding.mechanic

-- Tablet item(s)
Config.TabletItems = { 'mech_tablet', 'mechanic_tablet' }

-- Rank thresholds
Config.RankXP = {
  { rank=1, need=0,    payMult=1.00 },
  { rank=2, need=200,  payMult=1.10 },
  { rank=3, need=600,  payMult=1.20 },
  { rank=4, need=1200, payMult=1.35 },
}

-- Base pay by job type
Config.JobTypes = {
  engine     = { basePay = 450 },
  cosmetic   = { basePay = 520 },
  suspension = { basePay = 550 },
  service    = { basePay = 480 },
}

-- NPC spawns/models
Config.NPCModels = { 'sultan', 'buffalo', 'tailgater2' }
Config.NPCSpawns = {
  { coords = vector3(-372.9257, -111.5709, 38.6816), h = 69.1205 }
}

-- POS catalog
Config.POSCatalog = {
  Repairs = {
    { id='engine_part', label='Engine Repair', value='engine', price=250 },
    { id='body_part',   label='Body Repair',   value='body',   price=175 },
    { id='sparkplugs',  label='Spark Plugs',   value='engine', price=90  },
    { id='carbattery',  label='Car Battery',   value='engine', price=140 },
    { id='axleparts',   label='Axle Service',  value='susp',   price=220 },
    { id='engine_oil',  label='Oil Change',    value='oil',    price=80  },
  },
  Cosmetics = {
    { id='paint_job',   label='Paint Job',     price=500 },
    { id='livery',      label='Livery Install',price=350 },
    { id='tint',        label='Window Tint',   price=120 },
  },
  Performance = {
    { id='engine2',     label='Engine Upgrade',   price=750 },
    { id='transmission',label='Transmission Mod', price=600 },
    { id='suspension',  label='Suspension Kit',   price=450 },
    { id='brakes',      label='Brake Upgrade',    price=350 },
    { id='turbo',       label='Turbo',            price=900 },
  }
}

-- Receipt item(s)
Config.ReceiptItems = { 'receipt', 'paper_receipt' }

-- Paint colors
Config.PaintPalette = {
  red   = { r=200, g=20,  b=20  },
  blue  = { r=20,  g=60,  b=200 },
  green = { r=20,  g=150, b=80  },
}

-- Minimal Item->mod mapping used by client/main.lua
Config.ItemModMap = {
  bumper={1,2}, vehicle_bumper={1,2}, exhaust={4}, hood={7}, roof={10}, skirts={3}, spoiler={0},
}

-- Deduped PartRules (unique keys only)
Config.PartRules = {
  -- Repairs
  engine_part = { action='repair', type='engine',      zone='front',  max_items=5 },
  carbattery  = { action='repair', type='battery',     zone='front',  max_items=1 },
  sparkplugs  = { action='repair', type='sparkplugs',  zone='front',  max_items=8 },
  engine_oil  = { action='repair', type='oil',         zone='front',  radius=4.0, max_items=1 },
  oil_filter  = { action='repair', type='oil_filter',  zone='front',  radius=4.0, max_items=1 },
  brake_pads  = { action='repair', type='brakes',      zone='wheel',  max_items=4 },
  susp_arm    = { action='repair', type='suspension',  zone='wheel',  max_items=4 },
  axleparts   = { action='repair', type='axle',        zone='under',  max_items=4 },
  -- Cosmetics/perf
  bumper={ action='setMod', zone='exterior' }, vehicle_bumper={ action='setMod', zone='exterior' },
  exhaust={ action='setMod', zone='exterior' }, hood={ action='setMod', zone='exterior' },
  roof={ action='setMod', zone='exterior' }, skirts={ action='setMod', zone='exterior' },
  spoiler={ action='setMod', zone='exterior' },
  -- Upgrades
  engine1={ action='upgrade', modType=11, modIndex=0, zone='front' },
  engine2={ action='upgrade', modType=11, modIndex=1, zone='front' },
  engine3={ action='upgrade', modType=11, modIndex=2, zone='front' },
  engine4={ action='upgrade', modType=11, modIndex=3, zone='front' },
  engine5={ action='upgrade', modType=11, modIndex=4, zone='front' },
  brakes1={ action='upgrade', modType=12, modIndex=0, zone='wheel' },
  brakes2={ action='upgrade', modType=12, modIndex=1, zone='wheel' },
  brakes3={ action='upgrade', modType=12, modIndex=2, zone='wheel' },
  transmission1={ action='upgrade', modType=13, modIndex=0, zone='under' },
  transmission2={ action='upgrade', modType=13, modIndex=1, zone='under' },
  transmission3={ action='upgrade', modType=13, modIndex=2, zone='under' },
  suspension1={ action='upgrade', modType=15, modIndex=0, zone='under' },
  suspension2={ action='upgrade', modType=15, modIndex=1, zone='under' },
  suspension3={ action='upgrade', modType=15, modIndex=2, zone='under' },
  suspension4={ action='upgrade', modType=15, modIndex=3, zone='under' },
  armor1={ action='upgrade', modType=16, modIndex=0, zone='exterior' },
  armor2={ action='upgrade', modType=16, modIndex=1, zone='exterior' },
  armor3={ action='upgrade', modType=16, modIndex=2, zone='exterior' },
  armor4={ action='upgrade', modType=16, modIndex=3, zone='exterior' },
  armor5={ action='upgrade', modType=16, modIndex=4, zone='exterior' },
  turbo={ action='turbo', modType=18, zone='front' },
}

-- Action timing used by client/main.lua
Config.ActionTimes = {
  inspection=10000, setMod=4500, oil=5500, engine=5500, body=5000, brake=6500, susp=8000, tire=7000, paint=9000,
}

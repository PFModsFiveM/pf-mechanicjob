Config = Config or {}

-- Job / society
Config.JobName  = 'mechanic'
Config.Society  = 'mechanic'

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

Config.BusinessName    = 'mechanic'         -- job / business key used in DB rows
Config.ManagerGrade    = 4                  -- minimum grade to edit management
Config.SalesTax        = 0.05               -- 5%

-- Blip (will be recolored by primary_color when branding is saved)
Config.Blip = {
    enabled = true,
    coords  = vec3(-335.87, -136.95, 39.01),  -- change to your shop
    sprite  = 446,
    scale   = 0.9,
    color   = 2
}


-- POS catalog
Config.POSCatalog = {
  Repairs = {
    { id='engine_part', label='Engine Repair', value='engine', price=250 },
    { id='body_part',   label='Body Repair',   value='body',   price=175 },
    { id='sparkplugs',  label='Spark Plugs',   value='engine', price=90  },
    { id='carbattery',  label='Car Battery',   value='engine', price=140 },
    { id='axleparts',   label='Axle Service',  value='susp',   price=220 },
    { id='newoil',      label='Oil Change',    value='oil',    price=80  },
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

-- Which cosmetic items map to which mod types (client uses this)
Config.ItemModMap = {
  bumper         = {1,2},         -- front & rear
  vehicle_bumper = {1,2},
  exhaust        = {4},
  hood           = {7},
  roof           = {10},
  skirts         = {3},
  spoiler        = {0},
}

-- Part rules
Config.PartRules = {
  -- NPC job parts
  engine_oil  = { action='oil',   zone='front',   radius=4.0, npcOnly=true },
  oil_filter  = { action='oil',   zone='front',   radius=4.0, npcOnly=true },
  brake_pads  = { action='brake', zone='wheel',   npcOnly=true },
  susp_arm    = { action='susp',  zone='wheel',   npcOnly=true },
  tire_new    = { action='tire',  zone='wheel',   npcOnly=true },
  paint_kit   = { action='paint', zone='exterior',npcOnly=true },

  -- General player repairs
  engine_part = { action='engine', zone='under'    },
  body_part   = { action='body',   zone='exterior' },
  sparkplugs  = { action='engine', zone='front'    },
  carbattery  = { action='engine', zone='front'    },
  axleparts   = { action='susp',   zone='under'    },
  newoil      = { action='oil',    zone='front',   radius=4.0 },

  -- Cosmetics/performance (player vehicles)
  bumper         = { action='setMod', zone='exterior' },
  vehicle_bumper = { action='setMod', zone='exterior' },
  exhaust        = { action='setMod', zone='exterior' },
  hood           = { action='setMod', zone='exterior' },
  roof           = { action='setMod', zone='exterior' },
  skirts         = { action='setMod', zone='exterior' },
  spoiler        = { action='setMod', zone='exterior' },
}

-- Action times (ms) for the progress bar
Config.ActionTimes = {
  setMod = 4500,
  oil    = 5500,     -- oil & oil filter
  engine = 5500,
  body   = 5000,
  brake  = 6500,
  susp   = 8000,
  tire   = 7000,
  paint  = 9000,
}

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

-- Vehicle Diagnostics Configuration
Config.DiagnosticParts = {
    engine = {
        sparkplugs = { label = "Spark Plugs", max = 8 },
        carbattery = { label = "Car Battery", max = 1 },
        engine_oil = { label = "Engine Oil", max = 1 },
        oil_filter = { label = "Oil Filter", max = 1 }
    },
    suspension = {
        susp_arm = { label = "Suspension Arms", max = 4 },
        axleparts = { label = "Axle Components", max = 4 }
    }
}

-- Part rules update (replace existing PartRules section)
Config.PartRules = {
    -- Repair Components
    sparkplugs = { action = 'repair', type = 'sparkplugs', zone = 'front' },
    carbattery = { action = 'repair', type = 'battery', zone = 'front' },
    engine_oil = { action = 'repair', type = 'oil', zone = 'front', radius = 4.0 },
    oil_filter = { action = 'repair', type = 'oil', zone = 'front', radius = 4.0 },
    susp_arm = { action = 'repair', type = 'suspension', zone = 'wheel' },
    axleparts = { action = 'repair', type = 'axle', zone = 'under' },

  -- NPC job parts
  engine_oil  = { action='oil',   zone='front',   radius=4.0 },
  oil_filter  = { action='oil',   zone='front',   radius=4.0 },
  brake_pads  = { action='brake', zone='wheel' },
  susp_arm    = { action='susp',  zone='wheel' },
  tire_new    = { action='tire',  zone='wheel' },
  paint_kit   = { action='paint', zone='exterior',npcOnly=true },

  -- General player repairs
  engine_part = { action='engine', zone='under'    },
  body_part   = { action='body',   zone='exterior' },
  sparkplugs  = { action='engine', zone='front'    },
  carbattery  = { action='engine', zone='front'    },
  axleparts   = { action='susp',   zone='under'    },

  -- Cosmetics/performance (player vehicles)
  bumper         = { action='setMod', zone='exterior' },
  vehicle_bumper = { action='setMod', zone='exterior' },
  exhaust        = { action='setMod', zone='exterior' },
  hood           = { action='setMod', zone='exterior' },
  roof           = { action='setMod', zone='exterior' },
  skirts         = { action='setMod', zone='exterior' },
  spoiler        = { action='setMod', zone='exterior' },

  -- Engine upgrades
  engine1 = { action = 'upgrade', modType = 11, modIndex = 0, zone = 'front' },
  engine2 = { action = 'upgrade', modType = 11, modIndex = 1, zone = 'front' },
  engine3 = { action = 'upgrade', modType = 11, modIndex = 2, zone = 'front' },
  engine4 = { action = 'upgrade', modType = 11, modIndex = 3, zone = 'front' },
  engine5 = { action = 'upgrade', modType = 11, modIndex = 4, zone = 'front' },

  -- Brake upgrades
  brakes1 = { action = 'upgrade', modType = 12, modIndex = 0, zone = 'wheel' },
  brakes2 = { action = 'upgrade', modType = 12, modIndex = 1, zone = 'wheel' },
  brakes3 = { action = 'upgrade', modType = 12, modIndex = 2, zone = 'wheel' },

  -- Transmission upgrades
  transmission1 = { action = 'upgrade', modType = 13, modIndex = 0, zone = 'under' },
  transmission2 = { action = 'upgrade', modType = 13, modIndex = 1, zone = 'under' },
  transmission3 = { action = 'upgrade', modType = 13, modIndex = 2, zone = 'under' },

  -- Suspension upgrades
  suspension1 = { action = 'upgrade', modType = 15, modIndex = 0, zone = 'under' },
  suspension2 = { action = 'upgrade', modType = 15, modIndex = 1, zone = 'under' },
  suspension3 = { action = 'upgrade', modType = 15, modIndex = 2, zone = 'under' },
  suspension4 = { action = 'upgrade', modType = 15, modIndex = 3, zone = 'under' },

  -- Armor upgrades (mod index 16)
  armor1 = { action = 'upgrade', modType = 16, modIndex = 0, zone = 'exterior' },
  armor2 = { action = 'upgrade', modType = 16, modIndex = 1, zone = 'exterior' },
  armor3 = { action = 'upgrade', modType = 16, modIndex = 2, zone = 'exterior' },
  armor4 = { action = 'upgrade', modType = 16, modIndex = 3, zone = 'exterior' },
  armor5 = { action = 'upgrade', modType = 16, modIndex = 4, zone = 'exterior' },

  -- Turbo (mod index 18)
  turbo = { action = 'turbo', modType = 18, zone = 'front' },

  -- Repair parts
  engine_part = { action = 'repair', type = 'engine', max_items = 5, zone = 'front' },
  carbattery = { action = 'repair', type = 'battery', max_items = 1, zone = 'front' },
  sparkplugs = { action = 'repair', type = 'sparkplugs', max_items = 8, zone = 'front' },
  axleparts = { action = 'repair', type = 'axle', max_items = 4, zone = 'under' },
  newoil = { action = 'repair', type = 'oil', max_items = 1, zone = 'front' },
  brakes1 = { action = 'upgrade', type = 'brakes', level = 1, zone = 'wheel' },
  brakes2 = { action = 'upgrade', type = 'brakes', level = 2, zone = 'wheel' },
  brakes3 = { action = 'upgrade', type = 'brakes', level = 3, zone = 'wheel' },
}

-- Damage thresholds for vehicle behavior
Config.DamageThresholds = {
  battery = {
    dead = 90, -- Won't start at all above this damage %
    cranking = 70, -- Will have trouble starting above this %
    struggling = 40, -- Will shut off occasionally above this %
  },
  engine = {
    dead = 80, -- Won't start above this damage %
    struggling = 50, -- Will run poorly above this %
    items_needed = { -- How many engine parts needed based on damage
      [80] = 5, -- 80-100% damage needs 5 parts
      [60] = 4, -- 60-79% damage needs 4 parts
      [40] = 3, -- 40-59% damage needs 3 parts
      [20] = 2, -- 20-39% damage needs 2 parts
      [1] = 1,  -- 1-19% damage needs 1 part
    }
  }
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

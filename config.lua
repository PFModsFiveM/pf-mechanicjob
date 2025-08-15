Config = {}

-- Core
Config.JobName = 'mechanic'
Config.Society = 'mechanic' -- for stock/payouts

-- Rank thresholds and pay multipliers
Config.RankXP = {
  { rank = 1, need =   0, payMult = 1.00 },
  { rank = 2, need = 400, payMult = 1.10 },
  { rank = 3, need = 900, payMult = 1.25 },
  { rank = 4, need = 1800, payMult = 1.40 },
  { rank = 5, need = 3200, payMult = 1.60 },
}

-- NPC Vehicle pool and spawn pads (testing: single spot you gave)
Config.NPCModels = { 'sultan', 'premier', 'tampa', 'intruder', 'asea', 'blista' }
Config.NPCSpawns = {
  { coords = vec3(-372.9257, -111.5709, 38.6816), h = 69.1205 }
}

-- Job definitions (base templates). Required parts will be used as-is or customized per NPC job.
Config.JobTypes = {
  engine = {
    label = 'Engine Repair',
    parts = { { id = 'oil_filter', qty = 1 }, { id = 'engine_oil', qty = 1 } },
    basePay = 800, timeLimitMin = 25
  },
  suspension = {
    label = 'Suspension Repair',
    parts = { { id = 'susp_arm', qty = 2 } },
    basePay = 1000, timeLimitMin = 30
  },
  cosmetic = {
    label = 'Cosmetic Repaint',
    parts = { { id = 'paint_kit', qty = 1 } },
    basePay = 700, timeLimitMin = 20
  },
  service = {
    label = 'Basic Service',
    parts = { { id = 'oil_filter', qty = 1 }, { id = 'engine_oil', qty = 1 }, { id = 'brake_pads', qty = 1 } },
    basePay = 900, timeLimitMin = 30
  }
}

-- Parts supplier seed data
Config.Supplier = {
  oil_filter = { label = 'Oil Filter',  cost = 100, leadMin = 5,  supplier = 'BennySupply' },
  engine_oil = { label = 'Engine Oil',  cost = 150, leadMin = 5,  supplier = 'BennySupply' },
  brake_pads = { label = 'Brake Pads',  cost = 220, leadMin = 8,  supplier = 'BennySupply' },
  susp_arm   = { label = 'Suspension Arm', cost = 450, leadMin = 12, supplier = 'TrackPro' },
  tire_new   = { label = 'New Tire',    cost = 350, leadMin = 10, supplier = 'TrackPro' },
  paint_kit  = { label = 'Paint Kit',   cost = 280, leadMin = 6,  supplier = 'ColorWorks' },
}

-- Paint palette
Config.PaintPalette = {
  red        = { name = 'Red',        r = 200, g = 30,  b = 30  },
  blue       = { name = 'Blue',       r = 40,  g = 80,  b = 200 },
  black      = { name = 'Black',      r = 10,  g = 10,  b = 10  },
  white      = { name = 'White',      r = 240, g = 240, b = 240 },
  silver     = { name = 'Silver',     r = 180, g = 185, b = 190 },
  yellow     = { name = 'Yellow',     r = 230, g = 200, b = 40  },
  green      = { name = 'Green',      r = 40,  g = 160, b = 60  },
  orange     = { name = 'Orange',     r = 245, g = 140, b = 30  },
  purple     = { name = 'Purple',     r = 120, g = 60,  b = 180 },
  pink       = { name = 'Pink',       r = 230, g = 130, b = 190 },
}
Config.PaintPenalty = 300

-- Emotes / Anim
Config.UseEmoteCommand = true      -- uses: /e mechanic2 and /e c
Config.FallbackAnim = { dict = 'mini@repair', name = 'fixing_a_player', flag = 49 }

-- Spray particle effect
Config.SprayFx = {
  primary = { dict = 'scr_bike_business', name = 'scr_bike_spray', scale = 0.8 },
  backup  = { dict = 'core',              name = 'ent_sht_steam',  scale = 0.7 }
}

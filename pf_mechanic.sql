-- Ensure qb-garages compatibility (safe to run anytime)
ALTER TABLE `player_vehicles`
  ADD COLUMN IF NOT EXISTS `mods` LONGTEXT NULL,
  ADD INDEX IF NOT EXISTS `idx_plate` (`plate`);

-- NEW: Dedicated vehicle diagnostics table
CREATE TABLE IF NOT EXISTS `vehicle_diagnostics` (
  `plate` varchar(50) NOT NULL,
  `citizenid` varchar(50) DEFAULT NULL,

  `alternator` float DEFAULT 0,
  `sparkplugs` float DEFAULT 0,
  `carbattery` float DEFAULT 0,
  `oil` float DEFAULT 0,
  `oil_filter` float DEFAULT 0,
  `brakes` float DEFAULT 0,
  `suspension` float DEFAULT 0,
  `axle` float DEFAULT 0,
  `fuel_injector` float DEFAULT 0,
  `powersteeringpump` float DEFAULT 0,
  `radiator` float DEFAULT 0,
  `power_steering_fluid` float DEFAULT 0,
  `transmissionfluid` float DEFAULT 0,
  `brakefluid` float DEFAULT 0,
  `coolant` float DEFAULT 0,

  `engine_part` float DEFAULT 0,
  `body_part` float DEFAULT 0,

  `mileage` double DEFAULT 0,
  `engineHealth` float DEFAULT 1000,
  `bodyHealth` float DEFAULT 1000,
  `tankHealth` float DEFAULT 1000,
  `dirtLevel` float DEFAULT 0,

  `dpf_removed` TINYINT(1) DEFAULT 0 COMMENT 'DPF removed = 1, installed = 0',

  PRIMARY KEY (`plate`),
  KEY `citizenid_idx` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS pf_parts_catalog (
  part_id VARCHAR(64) PRIMARY KEY,
  label VARCHAR(64) NOT NULL,
  base_cost INT NOT NULL,
  supplier VARCHAR(32) NOT NULL,
  lead_minutes INT NOT NULL DEFAULT 10
);

CREATE TABLE IF NOT EXISTS pf_parts_stock (
  id INT AUTO_INCREMENT PRIMARY KEY,
  society VARCHAR(32) NOT NULL,
  part_id VARCHAR(64) NOT NULL,
  qty INT NOT NULL DEFAULT 0,
  UNIQUE KEY uniq_society_part (society, part_id)
);

CREATE TABLE IF NOT EXISTS pf_supplier_orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  society VARCHAR(32) NOT NULL,
  part_id VARCHAR(64) NOT NULL,
  qty INT NOT NULL,
  unit_cost INT NOT NULL,
  eta_at TIMESTAMP NOT NULL,
  status ENUM('pending','delivered','cancelled') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pf_work_orders (
  id INT AUTO_INCREMENT PRIMARY KEY,
  type ENUM('engine','suspension','cosmetic','service') NOT NULL,
  source ENUM('npc','player') NOT NULL,
  requester_name VARCHAR(64) DEFAULT NULL,
  requester_identifier VARCHAR(64) DEFAULT NULL,
  plate VARCHAR(16) NOT NULL,
  veh_model VARCHAR(64) NOT NULL,
  notes VARCHAR(256) DEFAULT NULL,
  required_parts JSON NOT NULL,
  deadline_at TIMESTAMP NULL,
  status ENUM('new','accepted','in_progress','awaiting_parts','complete','failed','cancelled') NOT NULL DEFAULT 'new',
  quality TINYINT DEFAULT 0,
  payout INT DEFAULT 0,
  assigned_to VARCHAR(50) DEFAULT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pf_mech_profiles (
  citizenid VARCHAR(50) PRIMARY KEY,
  xp INT NOT NULL DEFAULT 0,
  rank INT NOT NULL DEFAULT 1,
  total_earnings INT NOT NULL DEFAULT 0,
  jobs_done INT NOT NULL DEFAULT 0,
  rating_avg FLOAT DEFAULT 0
);

CREATE TABLE IF NOT EXISTS pf_job_history (
  id INT AUTO_INCREMENT PRIMARY KEY,
  work_order_id INT NOT NULL,
  citizenid VARCHAR(50) NOT NULL,
  plate VARCHAR(16) NOT NULL,
  type VARCHAR(32) NOT NULL,
  quality TINYINT NOT NULL,
  payout INT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX (citizenid), INDEX (plate)
);

CREATE TABLE IF NOT EXISTS `pf_service_log` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `plate` VARCHAR(16) NOT NULL,
  `citizenid` VARCHAR(64) NOT NULL,
  `author` VARCHAR(128) NOT NULL,
  `note` TEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_plate` (`plate`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional: If you want mileage persisted in DB (alternatively use entity statebag)
ALTER TABLE `player_vehicles` ADD COLUMN `mileage` FLOAT DEFAULT 0.0;

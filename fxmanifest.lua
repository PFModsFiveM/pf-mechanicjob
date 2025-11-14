fx_version 'cerulean'
game 'gta5'

name 'pf-mechanicjob'
author 'PF Mods'
description 'Advanced Mechanic job'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/style.css',
    'html/img/*.png',
    'html/img/*.webp',
    'html/img/*.svg'
}

shared_scripts {
  '@ox_lib/init.lua',             -- NEW: load ox_lib to get the `lib` global
  '@qb-core/shared/locale.lua',
  'config.lua',
  'shared/locale.lua',  -- NEW: Load locale system first
  'locales/en.lua',
  'locales/pl.lua',
  'locales/es.lua',
  'locales/fr.lua',
  'locales/de.lua'       -- NEW: Load all locale files
}

client_scripts {
  'client/tools_menu.lua',  -- MUST remain first for early exports
  'client/damage.lua',
  'client/preview.lua',        -- ADDED: separated preview system
  'client/main.lua',
  'client/minigames.lua',
  'client/cosmetics.lua',
  'client/garage_sync.lua',  -- NEW
  'client/mileage_hud.lua',  -- NEW
  'client/rolling_coal.lua',  -- NEW: Rolling coal visual effects
  'client/mechanictools.lua'  -- NEW: Upgrade display menu
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
  'server/repair.lua',
  'server/useables.lua',
  'server/consumables.lua',
  'server/garage_sync.lua'  -- NEW
}

escrow_ignore 'config.lua'

dependencies {
    'qb-core',
    'qb-menu',
    'ox_lib'                      -- NEW: ensure ox_lib is present when enabled in config
}

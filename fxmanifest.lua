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
  'config.lua'
}

client_scripts {
  'client/tools_menu.lua',  -- MUST remain first for early exports
  'client/damage.lua',
  'client/main.lua',
  'client/minigames.lua',
  'client/cosmetics.lua',
  'client/garage_sync.lua'  -- NEW
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

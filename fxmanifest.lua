fx_version 'cerulean'
game 'gta5'

name 'pf-mechanicjob'
author 'pf'
description 'Mechanic job with NPC jobs, POS, and management'
version '1.0.1'

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
  '@qb-core/shared/locale.lua',
  'config.lua'
}

client_scripts {
  'client/tools_menu.lua', -- Load FIRST to define helper functions
  'client/damage.lua',
  'client/*.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/main.lua',
  'server/repair.lua',
  'server/useables.lua',
  'server/consumables.lua'
}

dependencies {
    'qb-core',
    'qb-menu'
}

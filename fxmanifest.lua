fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'pf-mechanicjob'
author 'pf'
version '1.0.1'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/app.js',
    'html/style.css'
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

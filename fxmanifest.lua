fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author '5milez'
description 'Qbox Gas Station Job System with NPCs, Robbery, Tasks & Police Alerts'
version '1.0.0'

shared_scripts {
    'config.lua'
}

client_scripts {
    '@ox_lib/init.lua',
    '@ox_target/ox_target.lua',
    'client.lua'
}

server_scripts {
    
    '@ps-dispatch/server.lua',
    'server.lua'
}

dependencies {
    'qb-core',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'ps-dispatch'
}

local QBCore = exports['qb-core']:GetCoreObject()
local PlayerJob = nil
local WorkingStation = nil
local NPCClerkPed = nil
local ShopperPeds = {}
local LastPoliceAlert = 0

local function DebugPrint(msg)
    if Config.Debug then
        print("^5[GasJob]^7 " .. msg)
    end
end

-- Helper: Spawn NPC clerk for station
local function SpawnClerk(station)
    if NPCClerkPed then
        DeletePed(NPCClerkPed)
        NPCClerkPed = nil
    end
    local data = Config.GasStations[station]
    if not data then return end

    local model = GetHashKey(data.npc)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end

    local ped = CreatePed(4, model, data.npcCoords.x, data.npcCoords.y, data.npcCoords.z - 1, data.npcCoords.w, false, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 17, true)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)

    NPCClerkPed = ped
    exports.ox_target:addLocalEntity(NPCClerkPed, {
    {
        name = 'buy_items',
        icon = 'fa-solid fa-cart-shopping',
        label = 'Browse Items',
        onSelect = function()
            lib.showContext('gas_station_buy_menu')
        end,
        canInteract = function(entity, distance, coords, name)
            return true
        end
    }
})

    DebugPrint("Spawned clerk NPC for station " .. station)
end


-- Helper: Open NPC buying menu

RegisterNetEvent('gasjob:client:OpenBuyMenu', function()
    local station = WorkingStation or "central" -- fallback
    local storeInventory = Config.GasStations[station].storeInventory

    local options = {}
    for itemName, data in pairs(storeInventory) do
        table.insert(options, {
            title = data.label .. " - $" .. data.price,
            icon = "fa-solid fa-box",
            onSelect = function()
                TriggerServerEvent('gasjob:server:BuyItem', itemName, station)
            end
        })
    end

    lib.registerContext({
        id = 'gas_station_buy_menu',
        title = 'Gas Station Items',
        options = options
    })

    lib.showContext('gas_station_buy_menu')
end)

-- Helper: Despawn clerk NPC
local function DespawnClerk()
    if NPCClerkPed then
        DeletePed(NPCClerkPed)
        NPCClerkPed = nil
        DebugPrint("Despawned clerk NPC")
    end
end

-- Helper: Spawn NPC shoppers randomly (1-3 max)
local function SpawnShoppers(station)
    local data = Config.GasStations[station]
    if not data then return end

    local maxShoppers = data.maxNPCShoppers or 3
    local currentCount = #ShopperPeds
    local toSpawn = math.random(1, maxShoppers - currentCount)

    for _=1, toSpawn do
        -- Pick a random ped from shopper models
        local shopperModels = {"a_m_m_bevhills_01", "a_m_y_business_01", "a_f_m_fatcult_01"}
        local model = GetHashKey(shopperModels[math.random(#shopperModels)])
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(100) end

        -- Spawn somewhere near the gas station coords
        local spawnPos = vector3(
            data.coords.x + math.random(-5,5),
            data.coords.y + math.random(-5,5),
            data.coords.z
        )
        local ped = CreatePed(4, model, spawnPos.x, spawnPos.y, spawnPos.z - 1, math.random(0, 360), false, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedFleeAttributes(ped, 0, false)
        SetPedCombatAttributes(ped, 17, true)
        TaskWanderStandard(ped, 10.0, 10)
        ShopperPeds[#ShopperPeds + 1] = ped
    end

    DebugPrint("Spawned " .. toSpawn .. " NPC shoppers at " .. station)
end

-- Helper: Despawn all NPC shoppers
local function DespawnShoppers()
    for i = #ShopperPeds, 1, -1 do
        DeletePed(ShopperPeds[i])
        table.remove(ShopperPeds, i)
    end
    DebugPrint("Despawned all NPC shoppers")
end

-- Handle Player Sign On flow
local function SignOnJob(station)
    if WorkingStation then
        ox_lib.notify("You are already working at a station!")
        return
    end

    TriggerServerEvent("gasjob:server:SignOnJob", station)
end

-- Handle Player Sign Off flow
local function SignOffJob()
    if not WorkingStation then
        ox_lib.notify("You are not currently working at a gas station.")
        return
    end

    TriggerServerEvent("gasjob:server:SignOffJob", WorkingStation)
end

-- Monitor player leaving station zone for auto signoff
local function StartLeaveZoneCheck(station)
    local data = Config.GasStations[station]
    if not data then return end

    local signOffDistance = 50.0
    local leaveTimer = 0
    Citizen.CreateThread(function()
        while WorkingStation == station do
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local dist = #(pos - data.coords)

            if dist > signOffDistance then
                leaveTimer = leaveTimer + 1
                if leaveTimer >= 300 then -- 5 minutes * 1 sec tick
                    ox_lib.notify("You left the station for too long, signing off automatically.")
                    SignOffJob()
                    break
                end
            else
                leaveTimer = 0
            end
            Wait(1000)
        end
    end)
end

-- Handle shopper purchase simulation
local function ShopperMakePurchase(station, ped)
    local data = Config.GasStations[station]
    if not data then return end

    local storeInv = data.storeInventory
    local items = {}

    for k,v in pairs(storeInv) do
        table.insert(items, k)
    end

    if #items == 0 then return end

    local item = items[math.random(#items)]
    local itemData = storeInv[item]

    -- Choose payment method weighted
    local rnd = math.random(1, 100)
    local payMethod = "cash"
    if rnd > Config.Payment.paymentMethodWeights.cash then
        payMethod = "bank"
    end

    -- Add item to shopper inventory and remove from store inventory if tracking quantity (optional)
    TriggerServerEvent("gasjob:server:ShopperPurchase", station, item, payMethod)

    -- Notify player working at station
    if WorkingStation == station then
        ox_lib.notify("Shopper bought " .. itemData.label .. " for $" .. itemData.price)
        -- Pay player percentage
        TriggerServerEvent("gasjob:server:PayPlayerFromPurchase", Config.Payment.purchasePayoutPercent * itemData.price / 100)
    end
end

-- Handle player task execution
local function PerformTask(station, task)
    local data = Config.GasStations[station]
    if not data then return end

    local anim = Config.TaskAnims[task]
    if not anim then
        ox_lib.notify("Task animation not found.")
        return
    end

    local taskZone = data.taskZones[task]
    if not taskZone then
        ox_lib.notify("Task location not configured.")
        return
    end

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    if #(pos - taskZone) > 3.0 then
        ox_lib.notify("You are not at the task location.")
        return
    end

    -- Play animation and progress bar
    RequestAnimDict(anim.dict)
    while not HasAnimDictLoaded(anim.dict) do Wait(100) end

    TaskPlayAnim(ped, anim.dict, anim.anim, 8.0, -8, -1, 49, 0, false, false, false)

    local success = exports.ox_lib:progressBar({
        duration = 10000,
        label = "Performing " .. task,
        useWhileDead = false,
        canCancel = true,
        anim = { dict = anim.dict, clip = anim.anim }
    })

    ClearPedTasks(ped)

    if success then
        ox_lib.notify("Task completed! You earned $" .. Config.Payment.taskPayouts[task])
        TriggerServerEvent("gasjob:server:PayPlayerFromTask", Config.Payment.taskPayouts[task])
    else
        ox_lib.notify("Task cancelled.")
    end
end

-- Setup ox_target zones for each station on client start
local function SetupStationsTargets()
    for stationId, stationData in pairs(Config.GasStations) do

        -- Sign On/Off zone
        exports.ox_target:addBoxZone({
            coords = stationData.coords,
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0,
            debug = Config.Debug,
            options = {
                {
                    name = 'gasjob_signon_' .. stationId,
                    icon = 'fa-solid fa-clipboard-list',
                    label = Config.TargetOptions.signOn,
                    canInteract = function()
                        return PlayerJob ~= nil and PlayerJob.name == 'gasstation' and WorkingStation == nil
                    end,
                    onSelect = function()
                        SignOnJob(stationId)
                    end
                },
                {
                    name = 'gasjob_signoff_' .. stationId,
                    icon = 'fa-solid fa-door-open',
                    label = Config.TargetOptions.signOff,
                    canInteract = function()
                        return WorkingStation == stationId
                    end,
                    onSelect = function()
                        SignOffJob()
                    end
                },
                {
                    name = 'gasjob_manual_alert_' .. stationId,
                    icon = 'fa-solid fa-bell',
                    label = Config.TargetOptions.manualPoliceAlert,
                    canInteract = function()
                        return WorkingStation == stationId
                    end,
                    onSelect = function()
                        local now = GetGameTimer()
                        if now - LastPoliceAlert > Config.Robbery.policeAlertCooldown then
                            LastPoliceAlert = now
                            TriggerServerEvent("gasjob:server:PoliceAlert", stationId, "Manual alert by clerk")
                            ox_lib.notify("Manual police alert triggered.")
                        else
                            ox_lib.notify("Police alert cooldown active.")
                        end
                    end
                }
            }
        })

        -- Task zones
        for taskName, coords in pairs(stationData.taskZones) do
            exports.ox_target:addBoxZone({
                coords = coords,
                size = vec3(1.5, 1.5, 1.5),
                rotation = 0,
                debug = Config.Debug,
                options = {
                    {
                        name = 'gasjob_task_' .. taskName .. '_' .. stationId,
                        icon = 'fa-solid fa-tools',
                        label = Config.TargetOptions.task,
                        canInteract = function()
                            return WorkingStation == stationId
                        end,
                        onSelect = function()
                            PerformTask(stationId, taskName)
                        end
                    }
                }
            })
        end

        -- Register robbery zone
        exports.ox_target:addBoxZone({
            coords = vector3(stationData.coords.x + 1.0, stationData.coords.y - 0.5, stationData.coords.z),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0,
            debug = Config.Debug,
            options = {
                {
                    name = 'gasjob_robbery_register_' .. stationId,
                    icon = 'fa-solid fa-cash-register',
                    label = Config.TargetOptions.registerRobbery,
                    canInteract = function()
                        return true
                    end,
                    onSelect = function()
                        TriggerServerEvent("gasjob:server:AttemptRobbery", stationId, "register")
                    end
                }
            }
        })

        -- Safe robbery zone
        exports.ox_target:addBoxZone({
            coords = vector3(stationData.coords.x - 1.5, stationData.coords.y - 0.5, stationData.coords.z),
            size = vec3(1.5, 1.5, 1.5),
            rotation = 0,
            debug = Config.Debug,
            options = {
                {
                    name = 'gasjob_robbery_safe_' .. stationId,
                    icon = 'fa-solid fa-lock',
                    label = Config.TargetOptions.safeRobbery,
                    canInteract = function()
                        return true
                    end,
                    onSelect = function()
                        TriggerServerEvent("gasjob:server:AttemptRobbery", stationId, "safe")
                    end
                }
            }
        })
    end
end

-- Event: Player job update
RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    PlayerJob = job
    DebugPrint("Job updated: " .. (job and job.name or "nil"))
end)

-- Event: Player signed on to job
RegisterNetEvent('gasjob:client:OnJobStart', function(stationId)
    WorkingStation = stationId
    ox_lib.notify("You have signed on to work at " .. Config.GasStations[stationId].label)
    DespawnClerk()
    SpawnShoppers(stationId)
    StartLeaveZoneCheck(stationId)
end)

-- Event: Player signed off
RegisterNetEvent('gasjob:client:OnJobEnd', function(stationId)
    ox_lib.notify("You have signed off from " .. Config.GasStations[stationId].label)
    WorkingStation = nil
    DespawnShoppers()
    SpawnClerk(stationId)
end)

-- Event: Shopper purchase notification (for debugging)
RegisterNetEvent('gasjob:client:ShopperPurchaseNotify', function(item, price)
    ox_lib.notify("Shopper purchased " .. item .. " for $" .. price)
end)

-- Event: Robbery alert notification
RegisterNetEvent('gasjob:client:RobberyAlert', function(message)
    ox_lib.notify("Robbery Alert: " .. message)
    -- Play sound or other notification here
end)

-- On resource start
AddEventHandler('onClientResourceStart', function(resName)
    if GetCurrentResourceName() ~= resName then return end

    -- Get initial player job
    local job = QBCore.Functions.GetPlayerData().job
    PlayerJob = job

    -- Spawn clerks for all stations
    for stationId, _ in pairs(Config.GasStations) do
        SpawnClerk(stationId)
    end

    SetupStationsTargets()
    DebugPrint("Gas job script started.")
end)

-- Clean up ped entities on resource stop
AddEventHandler('onClientResourceStop', function(resName)
    if GetCurrentResourceName() ~= resName then return end
    DespawnClerk()
    DespawnShoppers()
end)

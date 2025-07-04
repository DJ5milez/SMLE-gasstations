local QBCore = exports['qb-core']:GetCoreObject()
local PlayerJob = nil
local WorkingStation = nil
local NPCClerkPed = nil
local ShopperPeds = {}
local LastPoliceAlert = 0
local clerkSurrendered = false
local clerkRespawnTime = 0
local ClerkSpawnCoords = nil 
local ClerkApproachCoords = nil
local RegisteredRegisterZones = {}
local clerkDeathTime = 0
local hasThermite = false



local function DebugPrint(msg)
    if Config.Debug then
        print("^5[GasJob]^7 " .. msg)
    end
end

-- Helper: Open NPC buying menu

RegisterNetEvent('gasjob:client:OpenBuyMenu', function()
    local station = WorkingStation or "mirrorpark"
    local storeInventory = Config.GasStations[station].storeInventory or {}

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

    -- Register then show
    lib.registerContext({
        id = 'gas_station_buy_menu',
        title = 'Gas Station Items',
        options = options
    })
    lib.showContext('gas_station_buy_menu')
end)



-- Helper: Spawn NPC clerk for station
local function SpawnClerk(station)
    WorkingStation = station
    if GetGameTimer() < clerkRespawnTime then
        DebugPrint("Clerk cooldown active, not respawning yet.")
        return
    end

    if NPCClerkPed then
        DeletePed(NPCClerkPed)
        NPCClerkPed = nil
    end

    local data = Config.GasStations[station]
    if not data then return end

    local model = GetHashKey(data.npc)
    RequestModel(model)
    while not HasModelLoaded(model) do Wait(100) end
    
    ClerkSpawnCoords = vector4(data.npcCoords.x, data.npcCoords.y, data.npcCoords.z, data.npcCoords.w)
    ClerkApproachCoords = vector3(data.approachCoords.x, data.approachCoords.y, data.approachCoords.z)


    local ped = CreatePed(4, model, data.npcCoords.x, data.npcCoords.y, data.npcCoords.z - 1, data.npcCoords.w, false, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatAttributes(ped, 46, true) -- Always fight
    SetPedCombatAbility(ped, 2) -- High ability
    SetPedCombatRange(ped, 2)   -- Medium-far
    SetPedCanSwitchWeapon(ped, true)
    TaskSetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, false)

    NPCClerkPed = ped
    exports.ox_target:addLocalEntity(NPCClerkPed, {
        {
            name = 'buy_items',
            icon = 'fa-solid fa-cart-shopping',
            label = 'Browse Items',
            onSelect = function()
                TriggerEvent('gasjob:client:OpenBuyMenu')
            end,
            canInteract = function(entity, distance, coords, name)
                return true
            end
        }
    })

        -- Add target zones for each cash register
        if not RegisteredRegisterZones[station] then
    RegisteredRegisterZones[station] = true
    DebugPrint("Setting up register zones for " .. station .. ", found " .. tostring(#data.registers) .. " registers.")
    for i, regCoords in ipairs(data.registers) do
        local zoneId = 'rob_register_' .. station .. '_' .. i
        exports.ox_target:addSphereZone({
            coords = regCoords,
            radius = 0.6,
            debug = Config.Debug,
            options = {
                {
                    name = zoneId,
                    icon = 'fas fa-cash-register',
                    label = 'Rob Cash Register',
                    onSelect = function()
                        AttemptRegisterRobbery(station, i)
                    end
                }
            }
        })
    end
    --  Register safe zones (correct placement)
    if not RegisteredSafeZones then RegisteredSafeZones = {} end
    if not RegisteredSafeZones[station] then
        RegisteredSafeZones[station] = true
        DebugPrint("Setting up safe zones for " .. station .. ", found " .. tostring(#data.safes or 0) .. " safes.")
        for i, safeCoords in ipairs(data.safes or {}) do
            exports.ox_target:addBoxZone({
                coords = safeCoords,
                size = vec3(0.6, 0.6, 0.6),
                rotation = 0.0,
                debug = Config.Debug,
                options = {
                    {
                        name = 'rob_safe_' .. station .. '_' .. i,
                        icon = 'fas fa-vault',
                        label = 'Rob Safe',
                        onSelect = function()
                            AttemptSafeRobbery(station, i)
                        end
                    }
                }
            })
        end
    end

    DebugPrint("Spawned clerk NPC for station " .. station)
end
end


-- Helper: Raycast to detect what player is aiming at
local function GetEntityPlayerIsLookingAt(distance)
    local playerPed = PlayerPedId()
    local startPos = GetPedBoneCoords(playerPed, 31086, 0.0, 0.0, 0.0) -- Head bone
    local forwardVector = GetEntityForwardVector(playerPed)
    local endPos = startPos + (forwardVector * (distance or 10.0))
    local rayHandle = StartShapeTestRay(
        startPos.x, startPos.y, startPos.z,
        endPos.x, endPos.y, endPos.z,
        -1, playerPed, 0
    )
    local _, _, _, _, entityHit = GetShapeTestResult(rayHandle)
    return entityHit
end


--Helper: Robbery Attempts

function AttemptRegisterRobbery(station, registerIndex)
    local playerPed = PlayerPedId()

    -- Check if clerk exists and isn't being aimed at
    if NPCClerkPed and DoesEntityExist(NPCClerkPed) and not IsEntityDead(NPCClerkPed) and not IsPlayerFreeAiming(PlayerId()) then
    local aimingEntity = GetEntityPlayerIsLookingAt(10.0)
    if not IsPlayerFreeAiming(PlayerId()) or aimingEntity ~= NPCClerkPed then
        DebugPrint("Player tried to rob register without holding up the clerk. Clerk retaliates.")
        ClearPedTasks(NPCClerkPed)
        FreezeEntityPosition(NPCClerkPed, false)
        GiveWeaponToPed(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, 100, false, true)
        Wait(50)
        SetCurrentPedWeapon(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, true)
        TaskCombatPed(NPCClerkPed, playerPed, 0, 16)
        clerkSurrendered = false
        QBCore.Functions.Notify("The clerk noticed you and retaliated!", "error")

        TriggerServerEvent('ps-dispatch:CustomAlert', {
            job = {'police'},
            coords = GetEntityCoords(NPCClerkPed),
            title = "Clerk Retaliation",
            message = "A store clerk has engaged a suspect during a robbery.",
            flash = true,
            uniqueId = 'register_retaliation_' .. math.random(1, 999999)
        })

        return -- prevent robbery attempt
    end
end
    -- Assume advanced lockpick logic (adjust to your needs)
    local hasAdvLockpick = QBCore.Functions.GetPlayerData().items and QBCore.Functions.GetPlayerData().items['advancedlockpick']
    local difficulty = hasAdvLockpick and 'easy' or 'medium'

    QBCore.Functions.Progressbar("rob_register", "Robbing register...", 6000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true
    }, {}, {}, {}, function()
        local success = exports['ps-ui']:CircleMiniGame(difficulty, 5, 15)
        if success then
            TriggerServerEvent("gasjob:server:RobRegister", station, registerIndex)
            QBCore.Functions.Notify("You stole some cash!", "success")
        else
            QBCore.Functions.Notify("You failed to crack the register!", "error")
        end
    end)

    TriggerServerEvent('ps-dispatch:CustomAlert', {
        job = {'police'},
        coords = GetEntityCoords(NPCClerkPed),
        title = "Gas Station Robbery",
        message = "A robbery is in progress at a gas station register.",
        flash = true,
        uniqueId = 'register_robbery_' .. math.random(1, 999999)
    })
end

function AttemptSafeRobbery(station, safeIndex)
    local PlayerData = QBCore.Functions.GetPlayerData()
    local hasThermite = false

    for _, item in pairs(PlayerData.items or {}) do
        if item.name == "thermite" then
            hasThermite = true
            break
        end
    end

    if not hasThermite then
        QBCore.Functions.Notify("You need thermite to rob the safe", "error")
        return
    end

    local playerPed = PlayerPedId()

    -- Check if clerk exists and isn't dead
    if NPCClerkPed and DoesEntityExist(NPCClerkPed) and not IsEntityDead(NPCClerkPed) then
        local aimingEntity = GetEntityPlayerIsLookingAt(10.0)
        local isAimedAt = IsPlayerFreeAiming(PlayerId()) and aimingEntity == NPCClerkPed

        if not isAimedAt then
            DebugPrint("Player tried to rob safe without aiming at the clerk. Clerk retaliates.")

            ClearPedTasks(NPCClerkPed)
            FreezeEntityPosition(NPCClerkPed, false)
            GiveWeaponToPed(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, 100, false, true)
            Wait(50)
            SetCurrentPedWeapon(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, true)
            TaskCombatPed(NPCClerkPed, playerPed, 0, 16)
            clerkSurrendered = false

            QBCore.Functions.Notify("The clerk noticed you and retaliated!", "error")

            TriggerServerEvent('ps-dispatch:CustomAlert', {
                job = {'police'},
                coords = GetEntityCoords(NPCClerkPed),
                title = "Clerk Retaliation",
                message = "A store clerk has engaged a suspect during a safe robbery.",
                flash = true,
                uniqueId = 'safe_retaliation_' .. math.random(1, 999999)
            })

            return -- Cancel the robbery
        end
    end

    -- Play thermite animation
    local dict = "anim@heists@ornate_bank@thermal_charge"
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(10) end

    TaskPlayAnim(PlayerPedId(), dict, "thermal_charge", 8.0, -8.0, 2500, 49, 0, false, false, false)
    Wait(2500)
    ClearPedTasks(PlayerPedId())

    -- Start robbery progressbar
    QBCore.Functions.Progressbar("rob_safe", "Placing Thermite...", 7000, false, true, {
        disableMovement = true,
        disableCarMovement = true,
        disableMouse = false,
        disableCombat = true
    }, {}, {}, {}, function()
        TriggerServerEvent("gasjob:server:RobSafe", station, safeIndex)
        QBCore.Functions.Notify("Safe is being robbed!", "success")

        TriggerServerEvent('ps-dispatch:CustomAlert', {
            job = {'police'},
            coords = GetEntityCoords(PlayerPedId()),
            title = "Gas Station Safe Robbery",
            message = "A safe robbery is in progress!",
            flash = true,
            uniqueId = 'safe_robbery_' .. math.random(1, 999999)
        })

        -- Remove thermite
        TriggerServerEvent("QBCore:Server:RemoveItem", "thermite", 1)
        TriggerEvent("inventory:client:ItemBox", QBCore.Shared.Items["thermite"], "remove")
    end)
end


--Helper: NPC clerk attack

Citizen.CreateThread(function()
    while true do
        Wait(500)

        if not NPCClerkPed or not DoesEntityExist(NPCClerkPed) then 
            goto continue 
        end

        DebugPrint("Clerk AI thread running. NPCClerkPed: " .. tostring(NPCClerkPed))

        local playerPed = PlayerPedId()

        if IsPlayerFreeAiming(PlayerId()) then
            local aimingEntity = GetEntityPlayerIsLookingAt(10.0)
            DebugPrint("Raycast aiming at entity: " .. tostring(aimingEntity) .. ", Clerk: " .. tostring(NPCClerkPed))

            if aimingEntity == NPCClerkPed then
                DebugPrint("Player is aiming at the clerk.")
                if not clerkSurrendered then
                    RequestAnimDict("random@arrests")
                    while not HasAnimDictLoaded("random@arrests") do Wait(10) end

                    TaskPlayAnim(NPCClerkPed, "random@arrests", "idle_2_hands_up", 8.0, -8.0, -1, 49, 0, false, false, false)
                    clerkSurrendered = true
                    DebugPrint("Clerk has surrendered.")
                    --Optional: Play surrender sound
                    PlayAmbientSpeech1(NPCClerkPed, "GENERIC_SHOCKED_HIGH", "SPEECH_PARAMS_FORCE")
                end
            elseif clerkSurrendered then
                -- Player aiming but not at clerk (maybe lowered gun)
                DebugPrint("Player aiming elsewhere — clerk retaliates.")
                ClearPedTasks(NPCClerkPed)
                FreezeEntityPosition(NPCClerkPed, false) -- Allow movement
                GiveWeaponToPed(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, 100, false, true)
                    Wait(50)
                    SetCurrentPedWeapon(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, true)    
                TaskCombatPed(NPCClerkPed, playerPed, 0, 16)
                clerkSurrendered = false
                -- Optional: Play retaliation sound
                PlayAmbientSpeech1(NPCClerkPed, "GENERIC_INSULT_HIGH", "SPEECH_PARAMS_FORCE")
                TriggerServerEvent('ps-dispatch:CustomAlert', {
                    job = {'police'},
                    coords = GetEntityCoords(NPCClerkPed),
                    title = "Armed Clerk Alert",
                    message = "A store clerk is engaging a suspect with a firearm.",
                    flash = true,
                    uniqueId = 'gas_clerk_retaliation_' .. math.random(1, 999999)
})
            end
        else
            -- Player not aiming at all
            if clerkSurrendered then
                DebugPrint("Player stopped aiming completely — clerk retaliates.")
                ClearPedTasks(NPCClerkPed)
                FreezeEntityPosition(NPCClerkPed, false) -- Allow movement
                GiveWeaponToPed(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, 100, false, true)
                    Wait(50)
                    SetCurrentPedWeapon(NPCClerkPed, `WEAPON_PUMPSHOTGUN`, true)    
                TaskCombatPed(NPCClerkPed, playerPed, 0, 16)
                clerkSurrendered = false
                -- Optional: Play retaliation sound
                PlayAmbientSpeech1(NPCClerkPed, "GENERIC_INSULT_HIGH", "SPEECH_PARAMS_FORCE")
                TriggerServerEvent('ps-dispatch:CustomAlert', {
                    job = {'police'},
                    coords = GetEntityCoords(NPCClerkPed),
                    title = "Armed Clerk Alert",
                    message = "A store clerk is engaging a suspect with a firearm.",
                    flash = true,
                    uniqueId = 'gas_clerk_retaliation_' .. math.random(1, 999999)
})
            end
        end

        ::continue::
    end
end)
--to add if there is player hostage do not engage

Citizen.CreateThread(function()
    while true do
        Wait(1000)

        if NPCClerkPed then
            if IsEntityDead(NPCClerkPed) and clerkDeathTime == 0 then
                -- Clerk just died
                clerkDeathTime = GetGameTimer()
                clerkRespawnTime = clerkDeathTime + ((Config.Debug and 1 or 15) * 60 * 1000)
                DebugPrint("Clerk killed. Corpse will remain for 15 minutes. Respawn scheduled at " .. clerkRespawnTime)
            end

            if clerkDeathTime > 0 and GetGameTimer() >= clerkRespawnTime then
                -- Time to remove corpse and allow respawn
                DeletePed(NPCClerkPed)
                NPCClerkPed = nil
                clerkDeathTime = 0
                DebugPrint("Clerk corpse removed. Ready for respawn.")
            end
        end
    end
end)

-- Helper - NPC return to work after combat

Citizen.CreateThread(function()
    while true do
        Wait(5000)

        if NPCClerkPed and not IsEntityDead(NPCClerkPed) and not clerkSurrendered then
            if not IsPedInCombat(NPCClerkPed, 0) and ClerkSpawnCoords then
                DebugPrint("Clerk is no longer in combat, returning to counter.")

                ClearPedTasks(NPCClerkPed)
                SetPedAsGroupMember(NPCClerkPed, 0)
                SetPedRelationshipGroupDefaultHash(NPCClerkPed, `CIVMALE`)
                SetPedRelationshipGroupHash(NPCClerkPed, `CIVMALE`)
                GiveWeaponToPed(NPCClerkPed, `WEAPON_UNARMED`, 0, true, true)

                TaskGoStraightToCoord(NPCClerkPed, ClerkSpawnCoords.x, ClerkSpawnCoords.y, ClerkSpawnCoords.z, 1.0, -1, ClerkSpawnCoords.w, 0.0)

                -- Wait until the clerk is close to original spot
                while #(GetEntityCoords(NPCClerkPed) - vec3(ClerkSpawnCoords.x, ClerkSpawnCoords.y, ClerkSpawnCoords.z)) > 1.5 do
                    Wait(1000)
                end

                FreezeEntityPosition(NPCClerkPed, true)
                SetEntityHeading(NPCClerkPed, ClerkSpawnCoords.w)

                DebugPrint("Clerk returned to counter.")
                clerkSurrendered = false
                TaskStartScenarioInPlace(NPCClerkPed, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
            end
        end
    end
end)

--Helper: check for dead NPC

Citizen.CreateThread(function()
    while true do
        Wait(10000) -- check every 10 seconds

        if not NPCClerkPed and GetGameTimer() >= clerkRespawnTime and WorkingStation then
            DebugPrint("Clerk respawn timer elapsed. Respawning NPC...")
            SpawnClerk(WorkingStation)
        end
    end
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

for stationId, stationData in pairs(Config.GasStations) do
    exports.ox_target:addBoxZone({
    coords   = stationData.signPoint,
    size     = vec3(1.5, 1.5, 1.5),
    rotation = 0,
    debug    = Config.Debug,
    options  = {
        {
            name  = 'gasjob_signon_' .. stationId,
            icon  = 'fa-solid fa-clock',
            label = 'Sign On to ' .. stationData.label,
            canInteract = function()
                return PlayerJob and PlayerJob.name == 'store' and WorkingStation == nil
            end,
            onSelect = function()
                SignOnJob(stationId)
            end
        },
        {
            name  = 'gasjob_signoff_' .. stationId,
            icon  = 'fa-solid fa-clock',
            label = 'Sign Off from ' .. stationData.label,
            canInteract = function()
                return PlayerJob and PlayerJob.name == 'store' and WorkingStation == stationId
            end,
            onSelect = function()
                SignOffJob()
            end
        }
    }
})

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


-- Spawn NPC clerk when player loads or on script start
--CreateThread(function()
  --  Wait(2000) -- Give time for core to load
   -- local station = "mirrorpark" -- Change if dynamic
 ---   SpawnClerk(station)
--end)
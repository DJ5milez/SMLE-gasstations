-- server.lua
-- Server-side logic for the Gas Station Job system on a Qbox (QBCore-based) FiveM server

local QBCore = exports['qb-core']:GetCoreObject()
local Stations = {} -- Tracks current working players and station states
local Cooldowns = {} -- Tracks robbery cooldowns per station
local stationData = Stations[station]

-- Utility for debug printing
local function DebugPrint(...)
    if Config.Debug then
        print("[GasStationJob] ", ...)
    end
end

-- Initialize stations data on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for stationName, _ in pairs(Config.GasStations) do
            Stations[stationName] = {
                workingPlayer = nil,
                registerFunds = Config.GasStations[stationName].registerStartAmount or 1000,
                safeFunds = Config.GasStations[stationName].safeStartAmount or 5000,
                npcClerkActive = true,
                shoppers = {},
                robberyCooldown = false,
            }
            Cooldowns[stationName] = false
        end
        DebugPrint("Stations initialized")
    end
end)

-- Helper: Let player buy item from NPC pedId
RegisterNetEvent('gasjob:server:BuyItem', function(itemKey, stationName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local item = Config.GasStations[stationName].storeInventory[itemKey]
    if not item then return end

    if Player.Functions.RemoveMoney("cash", item.price, "bought-gas-item") then
        Player.Functions.AddItem(itemKey, 1)
        TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[itemKey], "add")
        TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = "Purchased " .. item.label })
    else
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = "Not enough cash!" })
    end
end)


--Helper: Server robbery attempt
RegisterNetEvent("gasjob:server:RobRegister", function(station, registerIndex)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local stationData = Config.GasStations[station]
    if not stationData then return end

    local reward = math.random(100, 300)
    stationData.registerCash = math.max(0, stationData.registerCash - reward)
    Player.Functions.AddMoney("cash", reward, "register-robbery")
end)

RegisterNetEvent("gasjob:server:RobSafe", function(station, safeIndex)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local stationData = Config.GasStations[station]
    if not stationData then return end

    local amount = math.random(500, 1500)
    Player.Functions.AddMoney('cash', amount, "safe-robbery")
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = "You stole $" .. amount .. " from the safe" })

    -- Optional: Remove C4 or start cooldown
    Player.Functions.RemoveItem("c4", 1)
    TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items["c4"], "remove")
end)

-- Helper to check if a player is working at a station
local function IsPlayerWorking(playerId)
    for stationName, data in pairs(Stations) do
        if data.workingPlayer == playerId then
            return true, stationName
        end
    end
    return false, nil
end

-- Handle player signing on to a station
QBCore.Functions.CreateCallback('gasstationjob:server:SignOn', function(source, cb, stationName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        cb(false, "Player not found")
        return
    end
    if not Stations[stationName] then
        cb(false, "Station does not exist")
        return
    end

    if Stations[stationName].workingPlayer ~= nil then
        cb(false, "Someone is already working at this station")
        return
    end

    -- Prevent player from working at multiple stations
    local isWorking, currentStation = IsPlayerWorking(src)
    if isWorking then
        cb(false, "You are already working at " .. currentStation)
        return
    end

    -- Sign on player
    Stations[stationName].workingPlayer = src
    Stations[stationName].npcClerkActive = false

    DebugPrint(("Player %d signed on at station %s"):format(src, stationName))

    -- Notify client to remove NPC clerk and start job UI
    TriggerClientEvent('gasstationjob:client:OnSignOn', src, stationName)

    cb(true)
end)

-- Handle player signing off from a station
QBCore.Functions.CreateCallback('gasstationjob:server:SignOff', function(source, cb)
    local src = source
    local isWorking, stationName = IsPlayerWorking(src)
    if not isWorking then
        cb(false, "You are not currently signed on to any station")
        return
    end

    Stations[stationName].workingPlayer = nil
    Stations[stationName].npcClerkActive = true

    DebugPrint(("Player %d signed off from station %s"):format(src, stationName))

    -- Notify client to respawn NPC clerk and reset UI
    TriggerClientEvent('gasstationjob:client:OnSignOff', src, stationName)

    cb(true)
end)

-- Auto sign off player if they leave station zone for 5 mins
-- Client will trigger this event after timer
RegisterNetEvent('gasstationjob:server:AutoSignOff', function(stationName)
    local src = source
    if Stations[stationName] and Stations[stationName].workingPlayer == src then
        Stations[stationName].workingPlayer = nil
        Stations[stationName].npcClerkActive = true

        DebugPrint(("Player %d auto signed off (left zone) from station %s"):format(src, stationName))

        TriggerClientEvent('gasstationjob:client:OnSignOff', src, stationName)
    end
end)

-- Handle NPC shopper purchase and payout
RegisterNetEvent('gasstationjob:server:ShopperPurchase', function(stationName, paymentMethod, itemKey)
    local src = source
    if not Stations[stationName] then return end

    local station = Stations[stationName]
    local item = Config.StoreInventory[itemKey]
    if not item then
        DebugPrint("Invalid item for purchase: " .. tostring(itemKey))
        return
    end

    local price = item.price

    -- Add item to NPC shopper inventory (simulate purchase)
    -- For server, just track funds increase and player payout
    if paymentMethod == "cash" then
        station.registerFunds = station.registerFunds + price
    else -- bank
        station.safeFunds = station.safeFunds + price
    end

    -- Pay the player working at the station a cut (e.g. 10%)
    local clerkId = station.workingPlayer
    if clerkId then
        local payout = math.floor(price * Config.PayoutPercentage)
        local clerkPlayer = QBCore.Functions.GetPlayer(clerkId)
        if clerkPlayer then
            if paymentMethod == "cash" then
                clerkPlayer.Functions.AddMoney('cash', payout, "gas-station-payout")
            else
                clerkPlayer.Functions.AddMoney('bank', payout, "gas-station-payout")
            end
            DebugPrint(("Paid clerk %d %s $%d from shopper purchase at %s"):format(clerkId, paymentMethod, payout, stationName))
            TriggerClientEvent('ox_lib:notify', clerkId, { type = 'success', description = ("Received $%d from shopper purchase"):format(payout) })
        end
    end
end)

-- Handle task payout and completion
RegisterNetEvent('gasstationjob:server:CompleteTask', function(stationName, paymentMethod)
    local src = source
    if not Stations[stationName] then return end

    local station = Stations[stationName]
    local clerkId = station.workingPlayer
    if clerkId ~= src then return end

    local payout = Config.TaskPayoutAmount or 50

    local clerkPlayer = QBCore.Functions.GetPlayer(clerkId)
    if clerkPlayer then
        if paymentMethod == "cash" then
            clerkPlayer.Functions.AddMoney('cash', payout, "gas-station-task")
        else
            clerkPlayer.Functions.AddMoney('bank', payout, "gas-station-task")
        end
        DebugPrint(("Paid clerk %d %s $%d for completing task at %s"):format(clerkId, paymentMethod, payout, stationName))
        TriggerClientEvent('ox_lib:notify', clerkId, { type = 'success', description = ("Received $%d for task completion"):format(payout) })
    end
end)

-- Robbery cooldown timer helper
local function StartRobberyCooldown(stationName)
    Stations[stationName].robberyCooldown = true
    DebugPrint(("Robbery cooldown started at station %s"):format(stationName))
    SetTimeout(Config.RobberyCooldownDuration * 1000, function()
        Stations[stationName].robberyCooldown = false
        DebugPrint(("Robbery cooldown ended at station %s"):format(stationName))
    end)
end

-- Police alert helper
local function SendPoliceAlert(stationName, reason, offenderId)
    local coords = Config.GasStations[stationName].coords or vector3(0,0,0)
    local offender = QBCore.Functions.GetPlayer(offenderId)
    local offenderName = offender and offender.PlayerData.charinfo.firstname .. " " .. offender.PlayerData.charinfo.lastname or "Unknown"

    -- Trigger ps-dispatch alert
    TriggerEvent('ps-dispatch:server:sendPoliceAlert', {
        dispatchCode = "10-90", -- Robbery
        firstStreet = Config.GasStations[stationName].name or stationName,
        coords = coords,
        description = reason,
        priority = 3,
        source = offenderId
    })

    -- Log to Discord webhook
    PerformHttpRequest(Config.DiscordWebhook, function(err, text, headers) end, 'POST', json.encode({
        username = "GasStationJob",
        embeds = {{
            title = "Robbery Alert",
            description = ("Station: %s\nOffender: %s\nReason: %s\nTime: %s"):format(stationName, offenderName, reason, os.date("%Y-%m-%d %H:%M:%S")),
            color = 16711680, -- red
            footer = { text = "GasStationJob Logs" }
        }}
    }), { ['Content-Type'] = 'application/json' })

    DebugPrint(("Police alerted for robbery at %s by player %s (%d)"):format(stationName, offenderName, offenderId))
end

-- Handle register robbery attempt
QBCore.Functions.CreateCallback('gasstationjob:server:AttemptRegisterRobbery', function(source, cb, stationName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Stations[stationName] then
        cb(false, "Invalid station or player")
        return
    end

    if Stations[stationName].robberyCooldown then
        cb(false, "Station is on robbery cooldown")
        return
    end

    if Player.Functions.GetItemByName("lockpick") == nil then
        cb(false, "You need a lockpick to rob the register")
        return
    end

    -- TODO: Implement lockpick minigame on client
    -- For now, simulate success
    local success = true -- Replace with minigame result

    if success then
        -- Deduct funds from register
        local stolenAmount = math.min(Stations[stationName].registerFunds, Config.RegisterRobberyAmount or 1000)
        Stations[stationName].registerFunds = Stations[stationName].registerFunds - stolenAmount
        Player.Functions.AddMoney('cash', stolenAmount, "register-robbery")

        DebugPrint(("Player %d robbed $%d from register at %s"):format(src, stolenAmount, stationName))

        -- Alert police & start cooldown
        SendPoliceAlert(stationName, "Register Robbery", src)
        StartRobberyCooldown(stationName)

        cb(true, stolenAmount)
    else
        cb(false, "Lockpick minigame failed")
    end
end)

-- Handle safe robbery attempt
QBCore.Functions.CreateCallback('gasstationjob:server:AttemptSafeRobbery', function(source, cb, stationName)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or not Stations[stationName] then
        cb(false, "Invalid station or player")
        return
    end

    if Stations[stationName].robberyCooldown then
        cb(false, "Station is on robbery cooldown")
        return
    end

    local hasC4 = Player.Functions.GetItemByName("c4") ~= nil
    -- TODO: Also support hacking minigame
    if not hasC4 then
        cb(false, "You need C4 or hacking to rob the safe")
        return
    end

    -- TODO: Implement hacking or C4 minigame on client
    local success = true -- Replace with minigame result

    if success then
        local stolenAmount = math.min(Stations[stationName].safeFunds, Config.SafeRobberyAmount or 5000)
        Stations[stationName].safeFunds = Stations[stationName].safeFunds - stolenAmount
        Player.Functions.AddMoney('cash', stolenAmount, "safe-robbery")

        -- Remove one C4 from inventory
        if hasC4 then
            Player.Functions.RemoveItem("c4", 1)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items["c4"], "remove")
        end

        DebugPrint(("Player %d robbed $%d from safe at %s"):format(src, stolenAmount, stationName))

        SendPoliceAlert(stationName, "Safe Robbery", src)
        StartRobberyCooldown(stationName)

        cb(true, stolenAmount)
    else
        cb(false, "Safe robbery minigame failed")
    end
end)

-- Player manual police alert during robbery
RegisterNetEvent('gasstationjob:server:ManualPoliceAlert', function(stationName)
    local src = source
    local isWorking, workingStation = IsPlayerWorking(src)
    if not isWorking or workingStation ~= stationName then
        TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = "You are not working at this station" })
        return
    end

    SendPoliceAlert(stationName, "Manual police alert triggered by clerk", src)
    TriggerClientEvent('ox_lib:notify', src, { type = 'success', description = "Police alert sent" })
end)

-- Debug command to print current working players
QBCore.Commands.Add("gasstationstatus", "Print Gas Station job status (Debug)", {}, false, function(source, args)
    if not Config.Debug then
        TriggerClientEvent('chat:addMessage', source, { args = { "^1GasStationJob", "Debug mode is disabled." } })
        return
    end

    local statusMsg = "Gas Station Status:\n"
    for stationName, data in pairs(Stations) do
        local worker = data.workingPlayer and ("Player %d"):format(data.workingPlayer) or "No worker"
        local cooldown = data.robberyCooldown and "ON" or "OFF"
        statusMsg = statusMsg .. ("%s - Worker: %s, Robbery Cooldown: %s\n"):format(stationName, worker, cooldown)
    end
    TriggerClientEvent('chat:addMessage', source, { args = { "^2GasStationJob", statusMsg } })
end, "admin")

-- Cleanup player data on disconnect
AddEventHandler('playerDropped', function(reason)
    local src = source
    for stationName, data in pairs(Stations) do
        if data.workingPlayer == src then
            data.workingPlayer = nil
            data.npcClerkActive = true
            DebugPrint(("Player %d disconnected, signed off from station %s"):format(src, stationName))
        end
    end
end)

-- Server export to check if station is on cooldown (for client-side use)
exports('IsStationOnCooldown', function(stationName)
    if Stations[stationName] then
        return Stations[stationName].robberyCooldown
    end
    return false
end)

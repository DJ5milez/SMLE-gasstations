Config = {}

Config.Debug = true -- Enable debug prints

-- Gas Stations config
Config.GasStations = {
    -- Each gas station has a unique id, coords, npc model, task zones, inventory, and cooldown state
    ["Mirror Park"] = {
        label = "Mirror Park Gas Station",
        coords = vec3(1160.85, -329.99, 68.99),
        npc = "s_m_y_shop_mask", -- clerk ped model
        npcCoords = vec4(1164.87, -323.64, 69.21, 101.09), -- ped heading included
        taskZones = {
            restock = vec3(1156.82, -322.75, 69.21),
            sweep = vector3(268.5, -1260.5, 29.3),
            cleanCounter = vec3(1161.54, -324.98, 69.21),
            takeTrash = vec3(1167.82, -318.25, 69.33),
        },
        storeInventory = {
            ["water"] = { label = "Water Bottle", price = 5 },
            ["chips"] = { label = "Chips", price = 8 },
            ["sandwich"] = { label = "Sandwich", price = 12 }
        },
        registerCash = 500, -- starting cash in register
        safeBank = 2000, -- money in safe (banked)
        robberyCooldown = 0, -- timestamp when next robbery allowed
        maxNPCShoppers = 3
    },

    -- Add more stations here
}

-- Payment config
Config.Payment = {
    purchasePayoutPercent = 10, -- % cut player receives on shopper purchases
    taskPayouts = {
        restock = 20,
        sweep = 15,
        cleanCounter = 15,
        takeTrash = 10,
    },
    paymentMethodWeights = {
        cash = 70, -- 70% chance shopper pays cash
        bank = 30
    }
}

-- Robbery config
Config.Robbery = {
    lockpickItem = "lockpick",
    c4Item = "c4",
    cooldownMinutes = 60, -- 1 hour cooldown after robbery
    robberyDistance = 5.0,
    policeAlertCooldown = 300000, -- 5 minutes between manual police alerts
}

-- Discord webhook for robbery/police logs
Config.DiscordWebhook = "https://discord.com/api/webhooks/your_webhook_url_here"

-- NPC shopper item purchase interval (seconds)
Config.ShopperPurchaseInterval = {min = 120, max = 300}

-- Task animations dictionary
Config.TaskAnims = {
    restock = {dict = "mini@repair", anim = "fixing_a_ped"},
    sweep = {dict = "amb@world_human_janitor@male@base", anim = "base"},
    cleanCounter = {dict = "timetable@maid@cleaning_window@", anim = "base"},
    takeTrash = {dict = "missfinale_c2mcs_1", anim = "fin_c2_mcs_1_camman"},
}

-- ox_target interaction options (labels)
Config.TargetOptions = {
    signOn = "Sign On for Job",
    signOff = "Sign Off from Job",
    task = "Perform Task",
    registerRobbery = "Rob Register",
    safeRobbery = "Rob Safe",
    manualPoliceAlert = "Trigger Police Alert"
}

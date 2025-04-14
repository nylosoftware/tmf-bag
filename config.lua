Config = {}

-- Standalone Money System Configuration --
-- Set these to match the standalone resource handling player money on your server.
Config.EnableMoneyCheck = true -- Set to true to require payment for bags
Config.MoneyResourceName = 'qb-core' -- Common frameworks: 'qb-core', 'es_extended', or your custom money resource
Config.GetMoneyExport = 'GetPlayerData' -- For QBCore typically: 'GetPlayerData'
Config.RemoveMoneyExport = 'RemoveMoney' -- For QBCore typically: 'RemoveMoney'
Config.AddMoneyExport = 'AddMoney' -- For QBCore typically: 'AddMoney'
Config.MoneyAccountName = 'cash' -- Most common: 'cash', 'money', or 'bank'

Config.checkForUpdates = false -- Set to false if using standalone

Config.OneBagInInventory = true -- Allow only one bag in inventory?
Config.NetworkBackpacks = true -- When true, backpacks are visible to all players
Config.EnableShop = true -- Set to true to enable the backpack shop
Config.Debug = false -- Set to true to enable debug output

-- Shop location
Config.ShopLocation = vec4(45.6547, -1748.8419, 29.6013, 50.1399) -- x, y, z, heading

Config.BackpackStorage = {
    [1] = { slots = 8, weight = 10000 }, -- Level 1 Bag
    [2] = { slots = 12, weight = 15000 }, -- Level 2 Bag
    [3] = { slots = 20, weight = 25000 }  -- Level 3 Bag
}

Config.BackpackProps = {
    [1] = 'prop_michael_backpack', -- Level 1 - Small Backpack
    [2] = 'p_michael_backpack_s',  -- Level 2 - Medium Backpack 
    [3] = 'prop_cs_duffel_01b'     -- Level 3 - Duffle Bag
}

-- You can customize the position/rotation of specific props if needed
Config.PropAdjustments = {
    ['prop_cs_duffel_01b'] = { -- Level 3 - Duffle Bag
        position = {x = 0.15, y = -0.15, z = -0.05}, -- Positioned slightly more to the side
        rotation = {x = 0.0, y = 90.0, z = 180.0}    -- Adjusted rotation
    },
    ['p_michael_backpack_s'] = { -- Level 2 - Medium Backpack
        position = {x = 0.07, y = -0.11, z = -0.05},
        rotation = {x = 0.0, y = 90.0, z = 175.0}
    },
    ['prop_michael_backpack'] = { -- Level 1 - Small Backpack
        position = {x = 0.07, y = -0.17, z = -0.06}, -- Moved back and down a bit
        rotation = {x = 0.0, y = 90.0, z = 175.0}
    }
    -- Add more props with specific adjustments as needed
}

Strings = { -- Notification strings
    action_incomplete = 'Unable to Complete Action',
    one_backpack_only = 'You can only carry one backpack at a time!',
    backpack_in_backpack = 'You cannot store a backpack inside another backpack!',
    purchase_success = 'Purchase Complete',
    purchase_failed = 'Purchase Failed',
    purchase_no_money = 'Not Enough Money',
    money_refunded = 'Money Refunded',
    item_received = 'Item Received',
    bag_level1 = 'Small Backpack',
    bag_level2 = 'Medium Backpack',
    bag_level3 = 'Large Backpack',
}

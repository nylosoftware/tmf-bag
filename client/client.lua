exports('openBackpack', function(data, slot)
    local bagLevel = (slot and slot.metadata and slot.metadata.bag_level) or 1
    if not (slot and slot.metadata and slot.metadata.identifier) then
        local identifier = lib.callback.await('tmf-bag:getNewIdentifier', 100, data.slot, bagLevel)
        exports.ox_inventory:openInventory('stash', 'bag_'..identifier)
    else
        TriggerServerEvent('tmf-bag:openBackpack', slot.metadata.identifier, bagLevel)
        exports.ox_inventory:openInventory('stash', 'bag_'..slot.metadata.identifier)
    end
end)

local bagEquipped, bagObj, currentBagHash
local ox_inventory = exports.ox_inventory
local ped = cache.ped
local justConnect = true

local function FindEquippedBackpack()
    for i = 3, 1, -1 do
        local itemName = 'backpack_l' .. i
        local itemSlots = ox_inventory:Search('slots', itemName)

        if type(itemSlots) == 'table' and next(itemSlots) then
            local firstSlot = next(itemSlots)
            return itemSlots[firstSlot]
        end
    end

    return nil
end

local function RemoveBag()
    if DoesEntityExist(bagObj) then
        SetEntityVisible(bagObj, false, false)
        DeleteEntity(bagObj)
    end
    
    if currentBagHash then
        SetModelAsNoLongerNeeded(currentBagHash)
    end
    
    bagObj = nil
    bagEquipped = nil
    currentBagHash = nil
end

local function PutOnBag(propModel)
    if not propModel then return end
    
    local propHash = type(propModel) == 'string' and GetHashKey(propModel) or propModel
    
    if not HasModelLoaded(propHash) then
        lib.requestModel(propHash, 500)
    end
    
    RemoveBag()
    
    local x, y, z = table.unpack(GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.5))
    bagObj = CreateObjectNoOffset(propHash, x, y, z, true, false)
    
    local pos = {x = 0.07, y = -0.11, z = -0.05}
    local rot = {x = 0.0, y = 90.0, z = 175.0}
    
    if Config.PropAdjustments and Config.PropAdjustments[propModel] then
        local adjustment = Config.PropAdjustments[propModel]
        if adjustment.position then pos = adjustment.position end
        if adjustment.rotation then rot = adjustment.rotation end
    end
    
    AttachEntityToEntity(
        bagObj, 
        ped, 
        GetPedBoneIndex(ped, 24818), 
        pos.x, pos.y, pos.z,
        rot.x, rot.y, rot.z, 
        true, true, false, true, 1, true
    )
    
    SetEntityAsMissionEntity(bagObj, true, true)
    
    bagEquipped = true
    currentBagHash = propHash
end

local function UpdateBagAppearance()
    local itemData = FindEquippedBackpack()
    local bagLevel, propModel
    
    if itemData then
        bagLevel = (itemData.metadata and itemData.metadata.bag_level) or 
                   tonumber(string.match(itemData.name, 'backpack_l(%d)')) or 
                   1
                   
        propModel = itemData.metadata and itemData.metadata.prop
        
        if not propModel and Config.BackpackProps and Config.BackpackProps[bagLevel] then
            propModel = Config.BackpackProps[bagLevel]
        end
        
        if not propModel then
            propModel = 'p_michael_backpack_s'
        end
        
        if Config.Debug then
            print('[tmf-bag] Equipping backpack level ' .. bagLevel .. ' with prop ' .. propModel)
        end
        
        local currentPropHash = currentBagHash
        local newPropHash = GetHashKey(propModel)
        
        if not bagEquipped or not bagObj or (currentPropHash ~= newPropHash) then
            RemoveBag()
            Wait(100)
            PutOnBag(propModel)
        end
    elseif bagEquipped then
        RemoveBag()
    end
end

CreateThread(function()
    Wait(5000)
    if Config.Debug then
        local currentResourceName = GetCurrentResourceName() 
        print('')
        print('===============================================================')
        print('BACKPACK EXPORT DEBUG INFO')
        print('Current Resource Name: ' .. currentResourceName)
        print('This is what should appear before .openBackpack in your ox_inventory item definition')
        print('For example: server = { export = \'' .. currentResourceName .. '.openBackpack\' }')
        print('===============================================================')
        print('')
    end
end)

RegisterNetEvent('ox_inventory:itemCount', function(itemName, totalCount)
    if string.find(itemName, 'backpack') and totalCount == 0 then
        RemoveBag()
    end
end)

exports('onBackpackRemoved', function()
    RemoveBag()
    return true
end)

AddEventHandler('ox_inventory:updateInventory', function(changes)
    if justConnect then
        Wait(4500)
        justConnect = nil
        UpdateBagAppearance()
        return
    end

    local backpackChanged = false
    local backpackRemoved = false
    
    if type(changes) == 'table' then
        for k, v in pairs(changes) do
            if type(v) == 'table' and (string.find(v.name or '', 'backpack') or v.name == 'backpack') then
                backpackChanged = true
                
                if v.count and v.count == 0 then
                    backpackRemoved = true
                end
                break
            end
            
            if type(v) == 'boolean' and (string.find(k or '', 'backpack') or k == 'backpack') then
                backpackChanged = true
                if v == false then
                    backpackRemoved = true
                end
                break
            end
        end
    elseif type(changes) == 'boolean' then
        backpackChanged = true
        backpackRemoved = true
    end

    if backpackRemoved then
        RemoveBag()
    elseif backpackChanged then
        UpdateBagAppearance()
    end
end)

lib.onCache('ped', function(value)
    ped = value
    if value then
        Wait(1000)
        UpdateBagAppearance()
    else
        RemoveBag()
    end
end)

lib.onCache('vehicle', function(value)
    if GetResourceState('ox_inventory') ~= 'started' then return end
    if value then
        RemoveBag()
    else
        Wait(500)
        UpdateBagAppearance()
    end
end)

CreateThread(function()
    while not exports.ox_inventory or not exports.interact do Wait(500) end

    local pedModel = `csb_prolsec`
    local shopCoords = vec4(45.6547, -1748.8419, 29.6013, 50.1399)

    lib.requestModel(pedModel, 100)

    local npc = CreatePed(0, pedModel, shopCoords.x, shopCoords.y, shopCoords.z - 1.0, shopCoords.w, true, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    FreezeEntityPosition(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedKeepTask(npc, true)
    SetModelAsNoLongerNeeded(pedModel)

    local bagShopItems = {
        { name = 'backpack_l1', label = 'Level 1 Backpack', price = 100, image = Config.BackpackImages[1] },
        { name = 'backpack_l2', label = 'Level 2 Backpack', price = 250, image = Config.BackpackImages[2] },
        { name = 'backpack_l3', label = 'Level 3 Backpack', price = 500, image = Config.BackpackImages[3] },
    }

    lib.registerContext({
        id = 'bag_shop_context_lib',
        title = 'Backpack Shop',
        options = (function()
            local opts = {}
            for _, item in ipairs(bagShopItems) do
                table.insert(opts, {
                    title = item.label,
                    description = 'Price: $' .. item.price,
                    icon = 'shopping-bag',
                    image = item.image,
                    canSelect = true,
                    onSelect = function()
                        TriggerServerEvent('tmf-bag:buyBag', item.name, item.price)
                    end,
                })
            end
            return opts
        end)()
    })

    exports.interact:AddEntityInteraction({
        netId = NetworkGetNetworkIdFromEntity(npc),
        id = 'bag_shop_npc',
        name = 'bag_shop',
        distance = 3.0,
        interactDst = 1.5,
        options = {
            {
                label = 'Browse Backpacks',
                icon = 'shopping-bag',
                action = function(entity, coords, args)
                    lib.showContext('bag_shop_context_lib')
                end,
            },
        }
    })

    local blip = AddBlipForCoord(shopCoords.x, shopCoords.y, shopCoords.z)
    SetBlipSprite(blip, 351)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Backpack Shop")
    EndTextCommandSetBlipName(blip)
end)

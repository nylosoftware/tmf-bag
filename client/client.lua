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
    Wait(10000)
    
    if not Config.EnableShop then
        if Config.Debug then
            print("[tmf-bag] Shop disabled in config")
        end
        return
    end
    
    if not exports.ox_inventory or not exports.interact then
        print("[tmf-bag] ERROR: Required resources ox_inventory or interact are not available")
        return
    end
    
    local pedModel = `csb_prolsec`
    local shopCoords = Config.ShopLocation
    
    if Config.Debug then
        print("[tmf-bag] Setting up shop at coordinates:", shopCoords.x, shopCoords.y, shopCoords.z)
    end
    
    if not HasModelLoaded(pedModel) then
        RequestModel(pedModel)
        while not HasModelLoaded(pedModel) do
            Wait(10)
        end
    end
    
    local npc = CreatePed(4, pedModel, shopCoords.x, shopCoords.y, shopCoords.z - 1.0, shopCoords.w, false, false)
    
    if not DoesEntityExist(npc) then
        print("[tmf-bag] ERROR: Failed to create shop NPC")
        return
    end
    
    SetEntityAsMissionEntity(npc, true, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
    SetPedDiesWhenInjured(npc, false)
    SetPedCanPlayAmbientAnims(npc, true)
    SetPedCanRagdollFromPlayerImpact(npc, false)
    SetEntityInvincible(npc, true)
    FreezeEntityPosition(npc, true)
    
    NetworkRegisterEntityAsNetworked(npc)
    local netID = NetworkGetNetworkIdFromEntity(npc)
    SetNetworkIdExistsOnAllMachines(netID, true)
    SetNetworkIdCanMigrate(netID, false)
    
    if Config.Debug then
        print("[tmf-bag] Shop NPC created with netID:", netID)
    end
    
    SetModelAsNoLongerNeeded(pedModel)
    
    local bagShopItems = {
        { name = 'backpack_l1', label = 'Level 1 Backpack', price = 100 },
        { name = 'backpack_l2', label = 'Level 2 Backpack', price = 250 },
        { name = 'backpack_l3', label = 'Level 3 Backpack', price = 500 },
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
                    onSelect = function()
                        TriggerServerEvent('tmf-bag:buyBag', item.name, item.price)
                    end,
                })
            end
            return opts
        end)()
    })
    
    local interactAvailable = false
    local success, errorMsg = pcall(function()
        exports.interact:AddEntityInteraction({
            netId = netID,
            id = 'bag_shop_entity',
            name = 'bag_shop',
            distance = 3.0,
            interactDst = 1.5,
            options = {
                {
                    label = 'Browse Backpacks',
                    action = function(_, _, _)
                        lib.showContext('bag_shop_context_lib')
                    end,
                },
            }
        })
        return true
    end)
    
    if success then
        interactAvailable = true
        if Config.Debug then
            print("[tmf-bag] Interaction registered successfully")
        end
    else
        if Config.Debug then
            print("[tmf-bag] Failed to register interaction with interact:", errorMsg)
        end
        
        pcall(function()
            exports.interact:AddInteraction({
                coords = vector3(shopCoords.x, shopCoords.y, shopCoords.z),
                id = 'bag_shop_location',
                name = 'bag_shop',
                distance = 3.0,
                interactDst = 1.5,
                options = {
                    {
                        label = 'Browse Backpacks',
                        action = function(_, _, _)
                            lib.showContext('bag_shop_context_lib')
                        end,
                    },
                }
            })
            interactAvailable = true
        end)
    end
    
    local blip = AddBlipForCoord(shopCoords.x, shopCoords.y, shopCoords.z)
    SetBlipSprite(blip, 351)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, 2)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Backpack Shop")
    EndTextCommandSetBlipName(blip)
    
    if Config.Debug then
        print("[tmf-bag] Shop setup complete!")
    end
    
    if not interactAvailable then
        if Config.Debug then
            print("[tmf-bag] Interact not available, using 3D text fallback")
        end
        
        CreateThread(function()
            while true do
                local sleep = 1000
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)
                local dist = #(playerCoords - vector3(shopCoords.x, shopCoords.y, shopCoords.z))
                
                if dist < 3.0 then
                    sleep = 0
                    DrawText3D(shopCoords.x, shopCoords.y, shopCoords.z, "Press ~g~E~w~ to browse backpacks")
                    
                    if dist < 1.5 and IsControlJustReleased(0, 38) then
                        lib.showContext('bag_shop_context_lib')
                    end
                end
                
                Wait(sleep)
            end
        end)
    end
end)

function DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    local px, py, pz = table.unpack(GetGameplayCamCoords())
    
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

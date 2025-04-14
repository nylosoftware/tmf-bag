-- This file exists solely to register the openBackpack export
-- for ox_inventory to use

print('tmf-bag exports.lua loaded - registering multiple export variants')

exports('openBackpack', function(data, slot)
    if Config.Debug then
        print('[tmf-bag] openBackpack export called')
    end
    OpenBackpackFunction(data, slot)
end)

exports('openbackpack', function(data, slot)
    if Config.Debug then
        print('[tmf-bag] openbackpack export called (lowercase variant)')
    end
    OpenBackpackFunction(data, slot)
end)

exports('OpenBackpack', function(data, slot)
    if Config.Debug then
        print('[tmf-bag] OpenBackpack export called (capitalized variant)')
    end
    OpenBackpackFunction(data, slot)
end)

exports({'openBackpack', 'openbackpack', 'OpenBackpack'})

AddEventHandler('tmf-bag:openBackpack', function(data, slot)
    if Config.Debug then
        print('[tmf-bag] tmf-bag:openBackpack event called')
    end
    OpenBackpackFunction(data, slot)
end)

function OpenBackpackFunction(data, slot)
    if Config.Debug then
        print('[tmf-bag] Processing backpack open with data:', json.encode(data or {}), 'slot:', json.encode(slot or {}))
    end
    
    local bagLevel = (slot and slot.metadata and slot.metadata.bag_level) or 1
    
    if not (slot and slot.metadata and slot.metadata.identifier) then
        local slotData = {
            name = data.name,
            slot = slot.slot
        }
        
        if Config.Debug then
            print('[tmf-bag] Getting new identifier for', json.encode(slotData))
        end
        local identifier = lib.callback.await('tmf-bag:getNewIdentifier', 1000, slotData, bagLevel)
        
        if not identifier then
            print('[tmf-bag] ERROR: Failed to get identifier from server callback')
            return
        end
        
        if Config.Debug then
            print('[tmf-bag] Got identifier:', identifier, '- Opening stash')
        end
        exports.ox_inventory:openInventory('stash', 'bag_'..identifier)
    else
        if Config.Debug then
            print('[tmf-bag] Using existing identifier:', slot.metadata.identifier)
        end
        TriggerServerEvent('tmf-bag:openBackpack', slot.metadata.identifier, bagLevel)
        exports.ox_inventory:openInventory('stash', 'bag_'..slot.metadata.identifier)
    end
end

if Config.Debug then
    print('tmf-bag all export and event handlers registered')
end 
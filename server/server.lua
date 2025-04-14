local registeredStashes = {}
local ox_inventory = exports.ox_inventory

local function GenerateText(num)
	local str
	repeat str = {}
		for i = 1, num do str[i] = string.char(math.random(65, 90)) end
		str = table.concat(str)
	until str ~= 'POL' and str ~= 'EMS'
	return str
end

local function GenerateSerial(text)
	if text and text:len() > 3 then
		return text
	end
	return ('%s%s%s'):format(math.random(100000,999999), text == nil and GenerateText(3) or text, math.random(100000,999999))
end

RegisterServerEvent('tmf-bag:openBackpack')
AddEventHandler('tmf-bag:openBackpack', function(identifier, bagLevel)
	if not registeredStashes[identifier] then
		local storageConfig = Config.BackpackStorage[bagLevel or 1]
		ox_inventory:RegisterStash('bag_'..identifier, 'Backpack', storageConfig.slots, storageConfig.weight, false)
		registeredStashes[identifier] = true
	end
end)

lib.callback.register('tmf-bag:getNewIdentifier', function(source, slot, bagLevel)
	if Config.Debug then
		print('[tmf-bag:server] Got getNewIdentifier callback with slot:', json.encode(slot), 'bagLevel:', bagLevel)
	end
	local itemData = ox_inventory:GetItem(source, slot.name, nil, false, slot.slot)
	bagLevel = bagLevel or (itemData and itemData.metadata and itemData.metadata.bag_level) or 1
	if Config.Debug then
		print('[tmf-bag:server] Using bag level:', bagLevel)
	end
	local newId = GenerateSerial()
	if Config.Debug then
		print('[tmf-bag:server] Generated ID:', newId)
	end
	ox_inventory:SetMetadata(source, slot.slot, {identifier = newId})
	local storageConfig = Config.BackpackStorage[bagLevel]
	ox_inventory:RegisterStash('bag_'..newId, 'Backpack', storageConfig.slots, storageConfig.weight, false)
	registeredStashes[newId] = true
	if Config.Debug then
		print('[tmf-bag:server] Registered stash bag_'..newId)
	end
	return newId
end)

CreateThread(function()
	while GetResourceState('ox_inventory') ~= 'started' do Wait(500) end
	local swapHook = ox_inventory:registerHook('swapItems', function(payload)
		local start, destination, move_type = payload.fromInventory, payload.toInventory, payload.toType
		local count_bagpacks = ox_inventory:GetItem(payload.source, 'backpack', nil, true)
	
		if string.find(destination, 'bag_') then
			TriggerClientEvent('ox_lib:notify', payload.source, {type = 'error', title = Strings.action_incomplete, description = Strings.backpack_in_backpack}) 
			return false
		end
		if Config.OneBagInInventory then
			if (count_bagpacks > 0 and move_type == 'player' and destination ~= start) then
				TriggerClientEvent('ox_lib:notify', payload.source, {type = 'error', title = Strings.action_incomplete, description = Strings.one_backpack_only}) 
				return false
			end
		end
		
		return true
	end, {
		print = false,
		itemFilter = {
			backpack = true,
		},
	})
	
	local createHook
	if Config.OneBagInInventory then
		createHook = exports.ox_inventory:registerHook('createItem', function(payload)
			local count_bagpacks = ox_inventory:GetItem(payload.inventoryId, 'backpack', nil, true)
			local playerItems = ox_inventory:GetInventoryItems(payload.inventoryId)
	
	
			if count_bagpacks > 0 then
				local slot = nil
	
				for i,k in pairs(playerItems) do
					if k.name == 'backpack' then
						slot = k.slot
						break
					end
				end
	
				Citizen.CreateThread(function()
					local inventoryId = payload.inventoryId
					local dontRemove = slot
					Citizen.Wait(1000)
	
					for i,k in pairs(ox_inventory:GetInventoryItems(inventoryId)) do
						if k.name == 'backpack' and dontRemove ~= nil and k.slot ~= dontRemove then
							local success = ox_inventory:RemoveItem(inventoryId, 'backpack', 1, nil, k.slot)
							if success then
								TriggerClientEvent('ox_lib:notify', inventoryId, {type = 'error', title = Strings.action_incomplete, description = Strings.one_backpack_only}) 
							end
							break
						end
					end
				end)
			end
		end, {
			print = false,
			itemFilter = {
				backpack = true
			}
		})
	end
	
	AddEventHandler('onResourceStop', function()
		ox_inventory:removeHooks(swapHook)
		if Config.OneBagInInventory then
			ox_inventory:removeHooks(createHook)
		end
	end)
end)

RegisterNetEvent('tmf-bag:buyBag', function(itemName, itemPrice)
	local src = source
	if Config.Debug then
		print(string.format('[tmf-bag] Received buy request from %s for item %s at price %s', src, itemName, itemPrice))
	end

	local itemExists = false
	if itemName == 'backpack_l1' or itemName == 'backpack_l2' or itemName == 'backpack_l3' then
		itemExists = true
	end

	if not itemExists then
		if Config.Debug then
			print(string.format('[tmf-bag] Invalid item name %s from %s', itemName, src))
		end
		TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'Invalid item selected.', type = 'error' })
		return
	end
	if Config.Debug then
		print(string.format('[tmf-bag] Item %s validation passed for %s', itemName, src))
	end

	if Config.EnableMoneyCheck then
		local moneyResource = exports[Config.MoneyResourceName]
		if not moneyResource then
			if Config.Debug then
				print(string.format('[tmf-bag] ERROR: Configured MoneyResourceName \'%s\' not found or not started.', Config.MoneyResourceName))
			end
			TriggerClientEvent('ox_lib:notify', src, { title = 'Server Error', description = 'Money system is not configured correctly.', type = 'error' })
			return
		end

		if Config.Debug then
			print(string.format('[tmf-bag] Attempting to check money using %s', Config.MoneyResourceName))
		end
		
		local currentMoney = 0
		local hasEnoughMoney = false
		
		if Config.MoneyResourceName == 'qb-core' then
			local QBCore = exports['qb-core']:GetCoreObject()
			local Player = QBCore.Functions.GetPlayer(src)
			
			if Player then
				currentMoney = Player.Functions.GetMoney(Config.MoneyAccountName)
				hasEnoughMoney = currentMoney >= itemPrice
				
				if Config.Debug then
					print(string.format('[tmf-bag] QBCore player %s %s balance: %s (Required: %s)', src, Config.MoneyAccountName, currentMoney, itemPrice))
				end
				
				if hasEnoughMoney then
					Player.Functions.RemoveMoney(Config.MoneyAccountName, itemPrice, "backpack-purchase")
					if Config.Debug then
						print(string.format('[tmf-bag] Removed %s %s from QBCore player %s', itemPrice, Config.MoneyAccountName, src))
					end
				end
			else
				if Config.Debug then
					print(string.format('[tmf-bag] ERROR: Could not get QBCore player data for source %s', src))
				end
				TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'Could not access your player data.', type = 'error' })
				return
			end
		elseif Config.MoneyResourceName == 'es_extended' then
			local ESX = exports['es_extended']:getSharedObject()
			local xPlayer = ESX.GetPlayerFromId(src)
			
			if xPlayer then
				if Config.MoneyAccountName == 'money' then
					currentMoney = xPlayer.getMoney()
				else
					currentMoney = xPlayer.getAccount(Config.MoneyAccountName).money
				end
				
				hasEnoughMoney = currentMoney >= itemPrice
				
				if Config.Debug then
					print(string.format('[tmf-bag] ESX player %s %s balance: %s (Required: %s)', src, Config.MoneyAccountName, currentMoney, itemPrice))
				end
				
				if hasEnoughMoney then
					if Config.MoneyAccountName == 'money' then
						xPlayer.removeMoney(itemPrice)
					else
						xPlayer.removeAccountMoney(Config.MoneyAccountName, itemPrice)
					end
					if Config.Debug then
						print(string.format('[tmf-bag] Removed %s %s from ESX player %s', itemPrice, Config.MoneyAccountName, src))
					end
				end
			else
				if Config.Debug then
					print(string.format('[tmf-bag] ERROR: Could not get ESX player data for source %s', src))
				end
				TriggerClientEvent('ox_lib:notify', src, { title = 'Error', description = 'Could not access your player data.', type = 'error' })
				return
			end
		else
			local getMoneyFunc = moneyResource[Config.GetMoneyExport]
			local removeMoneyFunc = moneyResource[Config.RemoveMoneyExport]
			
			if not getMoneyFunc or not removeMoneyFunc then
				print(string.format('[tmf-bag] ERROR: Configured money export functions (\'%s\' or \'%s\') not found in resource \'%s\'.', Config.GetMoneyExport, Config.RemoveMoneyExport, Config.MoneyResourceName))
				TriggerClientEvent('ox_lib:notify', src, { title = 'Server Error', description = 'Money system functions are not configured correctly.', type = 'error' })
				return
			end
			
			local accountData
			
			local success, result = pcall(function()
				return getMoneyFunc(src, Config.MoneyAccountName)
			end)
			
			if success then
				accountData = result
			else
				success, result = pcall(function()
					local player = getMoneyFunc(src)
					if player and type(player) == 'table' then
						return player.getAccount and player.getAccount(Config.MoneyAccountName) or player[Config.MoneyAccountName]
					end
					return nil
				end)
				
				if success then
					accountData = result
				end
			end
			
			if type(accountData) == 'table' and accountData.money ~= nil then
				currentMoney = accountData.money
			elseif type(accountData) == 'table' and accountData.value ~= nil then
				currentMoney = accountData.value
			elseif type(accountData) == 'number' then
				currentMoney = accountData
			else
				print(string.format('[tmf-bag] ERROR: Could not determine money from \'%s\'. Returned: %s', Config.GetMoneyExport, json.encode(accountData or 'nil')))
				TriggerClientEvent('ox_lib:notify', src, { title = 'Server Error', description = 'Could not retrieve your money balance.', type = 'error' })
				return
			end
			
			hasEnoughMoney = currentMoney >= itemPrice
			
			print(string.format('[tmf-bag] Generic player %s %s balance: %s (Required: %s)', src, Config.MoneyAccountName, currentMoney, itemPrice))
			
			if hasEnoughMoney then
				local removed = false
				
				success, result = pcall(function()
					return removeMoneyFunc(src, Config.MoneyAccountName, itemPrice)
				end)
				
				if success then
					removed = result ~= false
				else
					success, result = pcall(function()
						local player = getMoneyFunc(src)
						if player and type(player) == 'table' and player.removeMoney then
							return player.removeMoney(Config.MoneyAccountName, itemPrice)
						end
						return false
					end)
					
					if success then
						removed = result ~= false
					end
				end
				
				print(string.format('[tmf-bag] Attempted to remove %s %s from player %s. Success: %s', itemPrice, Config.MoneyAccountName, src, tostring(removed)))
			end
		end
		
		if hasEnoughMoney then
			print(string.format('[tmf-bag] Player %s has enough money. Adding item.', src))
			
			print(string.format('[tmf-bag] Attempting to add item %s to player %s', itemName, src))
			
			local bagLevel = tonumber(string.match(itemName, 'backpack_l(%d)'))
			local metadata = {
				bag_level = bagLevel,
				prop = Config.BackpackProps[bagLevel],
				image = Config.BackpackImages and Config.BackpackImages[bagLevel]
			}
			
			for k, v in pairs(metadata) do
				if v == nil then metadata[k] = nil end
			end
			
			local success, reason = exports.ox_inventory:AddItem(src, itemName, 1, metadata)

			if success then
				print(string.format('[tmf-bag] Successfully added item %s to player %s', itemName, src))
				TriggerClientEvent('ox_lib:notify', src, {
					title = 'Purchase Successful',
					description = string.format('You purchased a %s for $%s', itemName, itemPrice),
					type = 'success'
				})
			else
				print(string.format('[tmf-bag] FAILED to add item %s to player %s. Refunding attempt. Reason: %s', itemName, src, reason or 'Unknown'))
				
				if Config.MoneyResourceName == 'qb-core' then
					local QBCore = exports['qb-core']:GetCoreObject()
					local Player = QBCore.Functions.GetPlayer(src)
					if Player then
						Player.Functions.AddMoney(Config.MoneyAccountName, itemPrice, "backpack-purchase-refund")
						print(string.format('[tmf-bag] Refunded %s %s to QBCore player %s', itemPrice, Config.MoneyAccountName, src))
					end
				elseif Config.MoneyResourceName == 'es_extended' then
					local ESX = exports['es_extended']:getSharedObject()
					local xPlayer = ESX.GetPlayerFromId(src)
					if xPlayer then
						if Config.MoneyAccountName == 'money' then
							xPlayer.addMoney(itemPrice)
						else
							xPlayer.addAccountMoney(Config.MoneyAccountName, itemPrice)
						end
						print(string.format('[tmf-bag] Refunded %s %s to ESX player %s', itemPrice, Config.MoneyAccountName, src))
					end
				end
				
				TriggerClientEvent('ox_lib:notify', src, {
					title = 'Purchase Failed',
					description = reason or 'Could not add item. Your money has been refunded.',
					type = 'error'
				})
			end
		else
			print(string.format('[tmf-bag] Player %s does not have enough money (%s / %s)', src, currentMoney, itemPrice))
			TriggerClientEvent('ox_lib:notify', src, {
				title = 'Purchase Failed',
				description = 'You do not have enough money.',
				type = 'error'
			})
		end
	else
		print(string.format('[tmf-bag] Money check disabled. Attempting to add item %s to player %s for free.', itemName, src))
		
		local bagLevel = tonumber(string.match(itemName, 'backpack_l(%d)'))
		local metadata = {
			bag_level = bagLevel,
			prop = Config.BackpackProps[bagLevel],
			image = Config.BackpackImages and Config.BackpackImages[bagLevel]
		}
		
		for k, v in pairs(metadata) do
			if v == nil then metadata[k] = nil end
		end
		
		local success, reason = exports.ox_inventory:AddItem(src, itemName, 1, metadata)
		
		if success then
			print(string.format('[tmf-bag] Successfully added free item %s to player %s', itemName, src))
			TriggerClientEvent('ox_lib:notify', src, {
				title = 'Item Received',
				description = string.format('You received a %s', itemName),
				type = 'success'
			})
		else
			print(string.format('[tmf-bag] FAILED to add free item %s to player %s. Reason: %s', itemName, src, reason or 'Unknown'))
			TriggerClientEvent('ox_lib:notify', src, {
				title = 'Failed to Add Item',
				description = reason or 'Could not add item to your inventory.',
				type = 'error'
			})
		end
	end
end)

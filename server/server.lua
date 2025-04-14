local registeredStashes = {}
local ox_inventory = exports.ox_inventory
local recentPurchases = {}

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
	
	local preSwapHook = ox_inventory:registerHook('swapItems', function(payload)
		if type(payload.toInventory) == 'string' and payload.toInventory:find('bag_') then
			if payload.fromSlot then
				local success, item = pcall(function() return exports.ox_inventory:GetSlot(payload.fromInventory, payload.fromSlot) end)
				
				if success and item and item.name then
					if item.name:find('backpack') then
						TriggerClientEvent('ox_lib:notify', payload.source, {type = 'error', title = Strings.action_incomplete, description = Strings.backpack_in_backpack})
						return false
					end
				end
			end
		end
		
		if Config.OneBagInInventory and payload.toType == 'player' then
			if payload.fromType ~= 'player' or (payload.fromType == 'player' and payload.fromInventory ~= payload.toInventory) then
				local success, item = pcall(function() return exports.ox_inventory:GetSlot(payload.fromInventory, payload.fromSlot) end)
				
				if success and item and item.name and item.name:find('backpack') then
					local total_backpacks = 0
					for _, v in pairs({'backpack_l1', 'backpack_l2', 'backpack_l3'}) do
						total_backpacks = total_backpacks + ox_inventory:GetItem(payload.toInventory, v, nil, true)
					end
					
					if total_backpacks > 0 then
						TriggerClientEvent('ox_lib:notify', payload.source, {type = 'error', title = Strings.action_incomplete, description = Strings.one_backpack_only})
						return false
					end
				end
			end
		end
		
		return true
	end, {
		print = false
	})
	
	local createHook
	if Config.OneBagInInventory then
		createHook = exports.ox_inventory:registerHook('createItem', function(payload)
			local total_backpacks = 0
			local backpack_slots = {}
			
			for _, backpack_type in pairs({'backpack_l1', 'backpack_l2', 'backpack_l3'}) do
				local success, items = pcall(function() return ox_inventory:GetInventoryItems(payload.inventoryId, backpack_type) end)
				
				if success and items and #items > 0 then
					for _, item in pairs(items) do
						total_backpacks = total_backpacks + 1
						backpack_slots[#backpack_slots + 1] = item.slot
					end
				end
			end
	
			if total_backpacks > 0 then
				Citizen.CreateThread(function()
					local inventoryId = payload.inventoryId
					local allowedSlots = {}
					
					for _, slot in ipairs(backpack_slots) do
						allowedSlots[slot] = true
					end
					
					Citizen.Wait(1000)
					
					for _, backpack_type in pairs({'backpack_l1', 'backpack_l2', 'backpack_l3'}) do
						local success, items = pcall(function() return ox_inventory:GetInventoryItems(inventoryId, backpack_type) end)
						
						if success and items and #items > 0 then
							for _, item in pairs(items) do
								if not allowedSlots[item.slot] then
									local success = ox_inventory:RemoveItem(inventoryId, item.name, 1, nil, item.slot)
									if success then
										TriggerClientEvent('ox_lib:notify', inventoryId, {type = 'error', title = Strings.action_incomplete, description = Strings.one_backpack_only}) 
										
										if recentPurchases[inventoryId] and os.time() - recentPurchases[inventoryId].timestamp < 5 then
											local purchaseData = recentPurchases[inventoryId]
											recentPurchases[inventoryId] = nil
											
											if Config.EnableMoneyCheck then
												if Config.MoneyResourceName == 'qb-core' then
													local QBCore = exports['qb-core']:GetCoreObject()
													local Player = QBCore.Functions.GetPlayer(inventoryId)
													if Player then
														Player.Functions.AddMoney(Config.MoneyAccountName, purchaseData.price, "backpack-purchase-refund")
														if Config.Debug then
															print(string.format('[tmf-bag] Refunded %s %s to QBCore player %s for auto-removed backpack', purchaseData.price, Config.MoneyAccountName, inventoryId))
														end
													end
												elseif Config.MoneyResourceName == 'es_extended' then
													local ESX = exports['es_extended']:getSharedObject()
													local xPlayer = ESX.GetPlayerFromId(inventoryId)
													if xPlayer then
														if Config.MoneyAccountName == 'money' then
															xPlayer.addMoney(purchaseData.price)
														else
															xPlayer.addAccountMoney(Config.MoneyAccountName, purchaseData.price)
														end
														if Config.Debug then
															print(string.format('[tmf-bag] Refunded %s %s to ESX player %s for auto-removed backpack', purchaseData.price, Config.MoneyAccountName, inventoryId))
														end
													end
												else
													local moneyResource = exports[Config.MoneyResourceName]
													local addMoneyFunc = moneyResource[Config.AddMoneyExport]
													
													if addMoneyFunc then
														pcall(function()
															addMoneyFunc(inventoryId, Config.MoneyAccountName, purchaseData.price, "backpack-purchase-refund")
														end)
														if Config.Debug then
															print(string.format('[tmf-bag] Attempted to refund %s %s to player %s using custom framework', purchaseData.price, Config.MoneyAccountName, inventoryId))
														end
													end
												end
												
												TriggerClientEvent('ox_lib:notify', inventoryId, {
													title = Strings.money_refunded,
													description = string.format('You were refunded $%s for your backpack', purchaseData.price),
													type = 'success'
												})
											end
										end
									end
									
									return
								end
							end
						end
					end
				end)
			end
		end, {
			print = false,
			itemFilter = {
				backpack_l1 = true,
				backpack_l2 = true,
				backpack_l3 = true
			}
		})
	end
	
	local addItemHook = ox_inventory:registerHook('addItem', function(payload)
		if not payload or type(payload) ~= 'table' then 
			return true
		end
		
		if payload.inventoryId and type(payload.inventoryId) == 'string' and payload.inventoryId:find('bag_') then
			if payload.item and type(payload.item) == 'table' and payload.item.name then
				if payload.item.name:find('backpack') then
					if Config.Debug then
						print('[tmf-bag] Blocked attempt to add backpack to backpack stash:', payload.inventoryId)
					end
					return false
				end
			end
		end
		return true
	end, {
		print = false
	})
	
	AddEventHandler('onResourceStop', function()
		ox_inventory:removeHooks(preSwapHook)
		ox_inventory:removeHooks(addItemHook)
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
	local bagLevel = nil
	
	if itemName == 'backpack_l1' then
		itemExists = true
		bagLevel = 1
	elseif itemName == 'backpack_l2' then
		itemExists = true
		bagLevel = 2
	elseif itemName == 'backpack_l3' then
		itemExists = true
		bagLevel = 3
	end

	if not itemExists then
		if Config.Debug then
			print(string.format('[tmf-bag] Invalid item name %s from %s', itemName, src))
		end
		TriggerClientEvent('ox_lib:notify', src, { 
			title = Strings.purchase_failed, 
			description = 'Invalid item selected.', 
			type = 'error' 
		})
		return
	end
	
	local bagName = Strings['bag_level'..bagLevel] or 'Backpack'
	
	if Config.Debug then
		print(string.format('[tmf-bag] Item %s validation passed for %s', itemName, src))
	end

	if Config.EnableMoneyCheck then
		local moneyResource = exports[Config.MoneyResourceName]
		if not moneyResource then
			if Config.Debug then
				print(string.format('[tmf-bag] ERROR: Configured MoneyResourceName \'%s\' not found or not started.', Config.MoneyResourceName))
			end
			TriggerClientEvent('ox_lib:notify', src, { 
				title = Strings.purchase_failed, 
				description = 'Money system is not configured correctly.', 
				type = 'error' 
			})
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
				TriggerClientEvent('ox_lib:notify', src, { 
					title = Strings.purchase_failed, 
					description = 'Could not access your player data.', 
					type = 'error' 
				})
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
				TriggerClientEvent('ox_lib:notify', src, { 
					title = Strings.purchase_failed, 
					description = 'Could not access your player data.', 
					type = 'error' 
				})
				return
			end
		else
			local getMoneyFunc = moneyResource[Config.GetMoneyExport]
			local removeMoneyFunc = moneyResource[Config.RemoveMoneyExport]
			
			if not getMoneyFunc or not removeMoneyFunc then
				print(string.format('[tmf-bag] ERROR: Configured money export functions (\'%s\' or \'%s\') not found in resource \'%s\'.', Config.GetMoneyExport, Config.RemoveMoneyExport, Config.MoneyResourceName))
				TriggerClientEvent('ox_lib:notify', src, { 
					title = Strings.purchase_failed, 
					description = 'Money system functions are not configured correctly.', 
					type = 'error' 
				})
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
				TriggerClientEvent('ox_lib:notify', src, { 
					title = Strings.purchase_failed, 
					description = 'Could not retrieve your money balance.', 
					type = 'error' 
				})
				return
			end
			
			hasEnoughMoney = currentMoney >= itemPrice
			
			if Config.Debug then
				print(string.format('[tmf-bag] Generic player %s %s balance: %s (Required: %s)', src, Config.MoneyAccountName, currentMoney, itemPrice))
			end
			
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
				
				if Config.Debug then
					print(string.format('[tmf-bag] Attempted to remove %s %s from player %s. Success: %s', itemPrice, Config.MoneyAccountName, src, tostring(removed)))
				end
			end
		end
		
		if not hasEnoughMoney then
			print(string.format('[tmf-bag] Player %s does not have enough money (%s / %s)', src, currentMoney, itemPrice))
			TriggerClientEvent('ox_lib:notify', src, {
				title = Strings.purchase_failed,
				description = Strings.purchase_no_money,
				type = 'error'
			})
			return
		end
		
		print(string.format('[tmf-bag] Player %s has enough money. Adding item.', src))
	end
	
	print(string.format('[tmf-bag] Attempting to add item %s to player %s', itemName, src))
	
	local metadata = {
		bag_level = bagLevel,
		prop = Config.BackpackProps[bagLevel]
	}
	
	for k, v in pairs(metadata) do
		if v == nil then metadata[k] = nil end
	end
	
	local success, reason = exports.ox_inventory:AddItem(src, itemName, 1, metadata)

	if success then
		print(string.format('[tmf-bag] Successfully added item %s to player %s', itemName, src))
		
		if Config.OneBagInInventory then
			recentPurchases[src] = {
				name = itemName,
				price = itemPrice,
				timestamp = os.time()
			}
			
			SetTimeout(5000, function()
				if recentPurchases[src] then
					recentPurchases[src] = nil
				end
			end)
		end
		
		TriggerClientEvent('ox_lib:notify', src, {
			title = Strings.purchase_success,
			description = string.format('You purchased a %s for $%s', bagName, itemPrice),
			type = 'success'
		})
	else
		print(string.format('[tmf-bag] FAILED to add item %s to player %s. Refunding attempt. Reason: %s', itemName, src, reason or 'Unknown'))
		
		if Config.EnableMoneyCheck then
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
			else
				local moneyResource = exports[Config.MoneyResourceName]
				local addMoneyFunc = moneyResource[Config.AddMoneyExport]
				
				if addMoneyFunc then
					pcall(function()
						addMoneyFunc(src, Config.MoneyAccountName, itemPrice, "backpack-purchase-refund")
					end)
					if Config.Debug then
						print(string.format('[tmf-bag] Attempted to refund %s %s to player %s using custom framework', itemPrice, Config.MoneyAccountName, src))
					end
				end
			end
			
			TriggerClientEvent('ox_lib:notify', src, {
				title = Strings.purchase_failed,
				description = reason or 'Could not add item to your inventory. Your money has been refunded.',
				type = 'error'
			})
		end
	end
end)

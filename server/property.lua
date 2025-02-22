local sharedConfig = require 'config.shared'
local enteredProperty = {}
local insideProperty = {}
local citizenid = {}
local ring = {}

function EnterProperty(playerSource, id, isSpawn)
    local property = MySQL.single.await('SELECT * FROM properties WHERE id = ?', {id})
    if not property then return end -- Lua and its stupid need check nil warnings
    local propertyCoords = json.decode(property.coords)
    propertyCoords = vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    if not isSpawn and #(playerCoords - propertyCoords) > 8.0 then return end

    local player = exports.qbx_core:GetPlayer(playerSource)
    citizenid[playerSource] = player.PlayerData.citizenid

    local interactions = {}
    local isInteriorShell = tonumber(property.interior) ~= nil
    local stashes = json.decode(property.stash_options)
    for i = 1, #stashes do
        local stashCoords = isInteriorShell and CalculateOffsetCoords(propertyCoords, stashes[i].coords) or stashes[i].coords
        interactions[#interactions + 1] = {
            type = 'stash',
            coords = vec3(stashCoords.x, stashCoords.y, stashCoords.z)
        }
        exports.ox_inventory:RegisterStash(string.format('qbx_properties_%s_%s', id, i), string.format('Property: %s', property.property_name), stashes[i].slots, stashes[i].maxWeight, property.owner)
    end

    if isInteriorShell then
        TriggerClientEvent('qbx_properties:client:createInterior', playerSource, tonumber(property.interior), vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z - sharedConfig.shellUndergroundOffset))
    end

    local interactData = json.decode(property.interact_options)
    for i = 1, #interactData do
        local coords = isInteriorShell and CalculateOffsetCoords(propertyCoords, interactData[i].coords) or interactData[i].coords
        interactions[#interactions + 1] = {
            type = interactData[i].type,
            coords = vec3(coords.x, coords.y, coords.z)
        }
        if interactData[i].type == 'exit' then
            SetEntityCoords(GetPlayerPed(playerSource), coords.x, coords.y, coords.z, false, false, false, false)
            SetEntityHeading(GetPlayerPed(playerSource), coords.w)
        end
    end

    enteredProperty[playerSource] = id
    insideProperty[id] = insideProperty[id] or {}
    insideProperty[id][#insideProperty[id] + 1] = playerSource
    lib.triggerClientEvent('qbx_properties:client:concealPlayers', insideProperty[id], insideProperty[id])

    player.Functions.SetMetaData('currentPropertyId', id)

    local decorations =  MySQL.query.await('SELECT `id`, `model`, `coords`, `rotation` FROM `properties_decorations` WHERE `property_id` = ?', {id})
    for i = 1, #decorations do
        local temp = json.decode(decorations[i].coords)
        decorations[i].coords = isInteriorShell and CalculateOffsetCoords(propertyCoords, vec3(temp.x, temp.y, temp.z)) or vec3(temp.x, temp.y, temp.z)
        temp = json.decode(decorations[i].rotation)
        decorations[i].rotation = vec3(temp.x, temp.y, temp.z)
    end

    TriggerClientEvent('qbx_properties:client:loadDecorations', playerSource, decorations)

    TriggerClientEvent('qbx_properties:client:updateInteractions', playerSource, interactions, property.interior, type(property.rent_interval) == 'number')
end

---@param playerSource integer
local function exitProperty(playerSource, isLogout)
    if not enteredProperty[playerSource] then return end

    TriggerClientEvent('qbx_properties:client:unloadProperty', playerSource)
    TriggerClientEvent('qbx_properties:client:revealPlayers', playerSource)

    if not isLogout then
        local enterCoords = json.decode(MySQL.single.await('SELECT coords FROM properties WHERE id = ?', {enteredProperty[playerSource]}).coords)
        SetEntityCoords(GetPlayerPed(playerSource), enterCoords.x, enterCoords.y, enterCoords.z, false, false, false, false)
    end

    for i = 1, #insideProperty[enteredProperty[playerSource]] do
        if insideProperty[enteredProperty[playerSource]][i] == playerSource then
            table.remove(insideProperty[enteredProperty[playerSource]], i)
            break
        end
    end

    lib.triggerClientEvent('qbx_properties:client:concealPlayers', insideProperty[enteredProperty[playerSource]], insideProperty[enteredProperty[playerSource]])
    enteredProperty[playerSource] = nil

    if isLogout then return end

    local player = exports.qbx_core:GetPlayer(playerSource)
    if not player then return end

    player.Functions.SetMetaData('currentPropertyId', nil)
end

RegisterNetEvent('qbx_properties:server:exitProperty', function()
    exitProperty(source --[[@as number]])
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(source)
    exitProperty(source, true)
end)

lib.callback.register('qbx_properties:callback:loadProperties', function()
    local result = MySQL.query.await('SELECT coords FROM properties GROUP BY coords')
    local properties = {}
    for i = 1, #result do
        local coords = json.decode(result[i].coords)
        properties[i] = vec3(coords.x, coords.y, coords.z)
    end

    return properties
end)

lib.callback.register('qbx_properties:callback:requestProperties', function(_, propertyCoords)
    return MySQL.query.await('SELECT property_name, owner, id, price, rent_interval, keyholders FROM properties WHERE coords = ?', {json.encode(propertyCoords)})
end)

local function hasAccess(citizenId, propertyId)
    local property = MySQL.single.await('SELECT owner, keyholders FROM properties WHERE id = ?', {propertyId})
    if citizenId == property.owner then return true end

    local keyholders = json.decode(property.keyholders)
    for i = 1, #keyholders do
        if citizenId == keyholders[i] then return true end
    end

    return false
end

RegisterNetEvent('qbx_properties:server:enterProperty', function(data)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = data.id
    if not hasAccess(player.PlayerData.citizenid, propertyId) then return end

    EnterProperty(playerSource, propertyId, data.isSpawn)
end)

RegisterNetEvent('qbx_properties:server:ringProperty', function(data)
    local playerSource = source --[[@as number]]
    local propertyId = data.id
    local property = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    local owner = exports.qbx_core:GetPlayerByCitizenId(property.owner)

    ring[propertyId] = ring[propertyId] or {}
    if not lib.table.contains(ring[propertyId], playerSource) then
        ring[propertyId][#ring[propertyId] + 1] = playerSource
        SetTimeout(300000, function()
            for i = 1, #ring[propertyId] do
                if ring[propertyId][i] == playerSource then
                    table.remove(ring[propertyId], i)
                    break
                end
            end
        end)
    end
    if owner and enteredProperty[owner.PlayerData.source] == propertyId then
        exports.qbx_core:Notify(owner.PlayerData.source, locale('notify.someone_at_door'))
    end
end)

lib.callback.register('qbx_properties:callback:requestKeyHolders', function(source)
    local propertyId = enteredProperty[source]
    local result = MySQL.single.await('SELECT owner, keyholders FROM properties WHERE id = ?', {propertyId})
    local player = exports.qbx_core:GetPlayer(source)

    if player.PlayerData.citizenid ~= result.owner then return end

    local keyholders = json.decode(result.keyholders)
    local currentholders = {}
    for i = 1, #keyholders do
        local offlinePlayer = exports.qbx_core:GetOfflinePlayer(keyholders[i])
        if offlinePlayer then
            currentholders[#currentholders + 1] = {
                citizenid = offlinePlayer.PlayerData.citizenid,
                name = offlinePlayer.PlayerData.charinfo.firstname .. ' ' .. offlinePlayer.PlayerData.charinfo.lastname
            }
        end
    end
    return currentholders
end)

lib.callback.register('qbx_properties:callback:requestPotentialKeyholders', function(source)
    local propertyId = enteredProperty[source]
    local result = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    local owner = exports.qbx_core:GetPlayer(source)

    if owner.PlayerData.citizenid ~= result.owner then return end

    local players = insideProperty[propertyId]
    local insidePlayers = {}
    for i = 1, #players do
        local player = exports.qbx_core:GetPlayer(players[i])
        if player and not hasAccess(player.PlayerData.citizenid, propertyId) then
            insidePlayers[#insidePlayers + 1] = {
                citizenid = player.PlayerData.citizenid,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
            }
        end
    end
    return insidePlayers
end)

lib.callback.register('qbx_properties:callback:requestRingers', function(source)
    local propertyId = enteredProperty[source]
    local players = ring[propertyId] or {}
    local ringers = {}
    for i = 1, #players do
        local player = exports.qbx_core:GetPlayer(players[i])
        if player then
            ringers[#ringers + 1] = {
                citizenid = player.PlayerData.citizenid,
                name = player.PlayerData.charinfo.firstname .. ' ' .. player.PlayerData.charinfo.lastname
            }
        end
    end
    return ringers
end)

lib.callback.register('qbx_properties:callback:checkAccess', function(source)
    local propertyId = enteredProperty[source]
    local result = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    return result.owner == exports.qbx_core:GetPlayer(source).PlayerData.citizenid
end)

RegisterNetEvent('qbx_properties:server:letRingerIn', function(visitorCid)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    local result = MySQL.single.await('SELECT owner, interior FROM properties WHERE id = ?', {propertyId})

    if player.PlayerData.citizenid ~= result.owner then return end

    local visitor = exports.qbx_core:GetPlayerByCitizenId(visitorCid)
    if not visitor then return end

    EnterProperty(visitor.PlayerData.source, propertyId)
    for i = 1, #ring[propertyId] do
        if ring[propertyId][i] == visitor.PlayerData.source then
            table.remove(ring[propertyId], i)
            break
        end
    end
end)

RegisterNetEvent('qbx_properties:server:addKeyholder', function(keyholderCid)
    local playerSource = source --[[@as number]]
    local owner = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]
    local result = MySQL.single.await('SELECT owner, keyholders FROM properties WHERE id = ?', {propertyId})

    if owner.PlayerData.citizenid ~= result.owner then return end

    local keyholders = json.decode(result.keyholders)
    if lib.table.contains(keyholders, keyholderCid) then return end
    keyholders[#keyholders + 1] = keyholderCid
    MySQL.Sync.execute('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), propertyId})
    local keyholder = exports.qbx_core:GetPlayerByCitizenId(keyholderCid)
    exports.qbx_core:Notify(playerSource, keyholder.PlayerData.charinfo.firstname.. locale('notify.keyholder'))
    exports.qbx_core:Notify(keyholder.PlayerData.source, locale('notify.added_as_keyholder'))
end)

RegisterNetEvent('qbx_properties:server:removeKeyholder', function(keyholderCid)
    local playerSource = source --[[@as number]]
    local owner = exports.qbx_core:GetPlayer(playerSource)
    local propertyId = enteredProperty[playerSource]

    local result = MySQL.single.await('SELECT owner, keyholders FROM properties WHERE id = ?', {propertyId})
    if owner.PlayerData.citizenid ~= result.owner then return end

    local keyholders = json.decode(result.keyholders)
    if not lib.table.contains(keyholders, keyholderCid) then return end

    for i = 1, #keyholders do
        if keyholders[i] == keyholderCid then
            table.remove(keyholders, i)
            break
        end
    end

    MySQL.Sync.execute('UPDATE properties SET keyholders = ? WHERE id = ?', {json.encode(keyholders), propertyId})
    local keyholder = exports.qbx_core:GetOfflinePlayer(keyholderCid)
    exports.qbx_core:Notify(playerSource, keyholder.PlayerData.charinfo.firstname.. locale('notify.removed_as_keyholder'))
end)

RegisterNetEvent('qbx_properties:server:logoutProperty', function()
    local playerSource = source --[[@as number]]
    local propertyId = enteredProperty[playerSource]
    if not propertyId then return end

    local result = MySQL.single.await('SELECT owner, coords FROM properties WHERE id = ?', {propertyId})
    local player = exports.qbx_core:GetPlayer(playerSource)
    if player.PlayerData.citizenid ~= result.owner then return end

    TriggerClientEvent('qbx_properties:client:unloadProperty', playerSource)
    TriggerClientEvent('qbx_properties:client:revealPlayers', playerSource)
    for i = 1, #insideProperty[enteredProperty[playerSource]] do
        if insideProperty[enteredProperty[playerSource]][i] == playerSource then
            table.remove(insideProperty[enteredProperty[playerSource]], i)
            break
        end
    end

    lib.triggerClientEvent('qbx_properties:client:concealPlayers', insideProperty[enteredProperty[playerSource]], insideProperty[enteredProperty[playerSource]])
    enteredProperty[playerSource] = nil
    exports.qbx_core:Logout(playerSource)
    Wait(50)
    local coords = json.decode(result.coords)
    MySQL.update('UPDATE players SET position = ? WHERE citizenid = ?', { json.encode(vec4(coords.x, coords.y, coords.z, 0.0)), player.PlayerData.citizenid })
end)

RegisterNetEvent('qbx_properties:server:openStash', function()
    local playerSource = source --[[@as number]]
    local propertyId = enteredProperty[playerSource]
    local player = exports.qbx_core:GetPlayer(playerSource)
    -- Set to 1 as there is currently no implementation for multiple stashes
    local stashId = 1
    if not hasAccess(player.PlayerData.citizenid, propertyId) then return end
    exports.ox_inventory:forceOpenInventory(playerSource, 'stash', { id = string.format('qbx_properties_%s_%s', propertyId, stashId) })
end)

AddEventHandler('playerDropped', function ()
    local playerSource = source --[[@as number]]

    if not enteredProperty[playerSource] then return end

    for i = 1, #insideProperty[enteredProperty[playerSource]] do
        if insideProperty[enteredProperty[playerSource]][i] == playerSource then
            table.remove(insideProperty[enteredProperty[playerSource]], i)
            break
        end
    end

    Wait(50)
    local coords = json.decode(MySQL.single.await('SELECT coords FROM properties WHERE id = ?', {enteredProperty[playerSource]}).coords)
    MySQL.update('UPDATE players SET position = ? WHERE citizenid = ?', { json.encode(vec4(coords.x, coords.y, coords.z, 0.0)), citizenid[playerSource] })
end)

local function canAccess(source, owner, keyholders)
    local player = exports.qbx_core:GetPlayer(source)
    if player.PlayerData.citizenid == owner then return true end
    for i = 1, #keyholders do
        if player.PlayerData.citizenid == keyholders[i] then return true end
    end
    return false
end

local function registerGarage(name, owner, keyholders, garage)
    local garageName = 'property_' .. string.gsub(string.lower(name), ' ', '_')
    exports.qbx_garages:RegisterGarage(garageName, {
        label = name,
        vehicleType = 'car',
        accessPoints = {
            {
                coords = vec4(garage.x, garage.y, garage.z, garage.w),
            }
        },
        canAccess = function(source)
            return canAccess(source, owner, keyholders)
        end
    })
end

local function registerGarages()
    local properties = MySQL.query.await('SELECT property_name, owner, keyholders, garage FROM properties WHERE owner IS NOT NULL AND garage IS NOT NULL')
    if not properties then return end
    for i = 1, #properties do
        local property = properties[i]
        registerGarage(property.property_name, property.owner, json.decode(property.keyholders), json.decode(property.garage))
    end
end

local function startRentThread(propertyId)
    CreateThread(function()
        while true do
            local property = MySQL.single.await('SELECT owner, price, rent_interval, property_name FROM properties WHERE id = ?', {propertyId})
            if not property or not property.owner then break end

            local player = exports.qbx_core:GetPlayerByCitizenId(property.owner) or exports.qbx_core:GetOfflinePlayer(property.owner)
            if not player then print(string.format('%s does not exist anymore, consider checking property id %s', property.owner, propertyId)) break end

            if player.Offline then
                player.PlayerData.money.bank = player.PlayerData.money.bank - property.price
                if player.PlayerData.money.bank < 0 then break end
                exports.qbx_core:SaveOffline(player.PlayerData)
            else
                if not player.Functions.RemoveMoney('bank', property.price, string.format('Rent for %s', property.property_name)) then
                    exports.qbx_core:Notify(player.PlayerData.source, string.format('Not enough money to pay rent for %s', property.property_name), 'error')
                    break
                end
            end

            Wait(property.rent_interval * 3600000)
        end

        MySQL.update('UPDATE properties SET owner = ? WHERE id = ?', {nil, propertyId})
    end)
end

RegisterNetEvent('qbx_properties:server:rentProperty', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    local property = MySQL.single.await('SELECT owner, price, property_name, coords, rent_interval, keyholders, garage FROM properties WHERE id = ?', {propertyId})
    local propertyCoords = json.decode(property.coords)
    if #(playerCoords - vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)) > 8.0 then return end
    if property.owner then return end
    if not property.rent_interval then return end

    if player.PlayerData.money.bank < property.price then
        exports.qbx_core:Notify(playerSource, 'Not enough money to rent property.', 'error')
        return
    end

    if property.garage then
        registerGarage(property.property_name, player.PlayerData.citizenid, json.decode(property.keyholders), json.decode(property.garage))
    end

    exports.qbx_core:Notify(playerSource, string.format('Successfully started renting %s', property.property_name), 'success')
    MySQL.update('UPDATE properties SET owner = ? WHERE id = ?', {player.PlayerData.citizenid, propertyId})
    startRentThread()
end)

RegisterNetEvent('qbx_properties:server:buyProperty', function(propertyId)
    local playerSource = source --[[@as number]]
    local player = exports.qbx_core:GetPlayer(playerSource)
    local playerCoords = GetEntityCoords(GetPlayerPed(playerSource))
    local property = MySQL.single.await('SELECT owner, price, property_name, coords, keyholders, garage FROM properties WHERE id = ?', {propertyId})
    local propertyCoords = json.decode(property.coords)

    if #(playerCoords - vec3(propertyCoords.x, propertyCoords.y, propertyCoords.z)) > 8.0 or property.owner then return end

    if not player.Functions.RemoveMoney('cash', property.price, string.format('Purchased %s', property.property_name)) and not player.Functions.RemoveMoney('bank', property.price, string.format('Purchased %s', property.property_name)) then
        exports.qbx_core:Notify(playerSource, 'Not enough money to purchase property.', 'error')
        return
    end

    if property.garage then
        registerGarage(property.property_name, player.PlayerData.citizenid, json.decode(property.keyholders), json.decode(property.garage))
    end

    MySQL.update('UPDATE properties SET owner = ? WHERE id = ?', {player.PlayerData.citizenid, propertyId})
    exports.qbx_core:Notify(playerSource, string.format('Successfully purchased %s for $%s', property.property_name, property.price))
end)

Citizen.CreateThreadNow(function()
    local sql1 = LoadResourceFile(cache.resource, 'property.sql')
    local sql2 = LoadResourceFile(cache.resource, 'decorations.sql')
    local sql3 = LoadResourceFile(cache.resource, 'property_garages.sql')

    MySQL.query.await(sql1)
    MySQL.query.await(sql2)
    MySQL.query.await(sql3)

    local properties = MySQL.query.await('SELECT id FROM properties WHERE owner IS NOT NULL AND rent_interval IS NOT NULL')
    for i = 1, #properties do
        startRentThread(properties[i].id)
    end

    registerGarages()
end)

RegisterNetEvent('qbx_properties:server:stopRenting', function()
    local player = exports.qbx_core:GetPlayer(source)
    local propertyId = enteredProperty[source]
    local property = MySQL.single.await('SELECT owner, property_name FROM properties WHERE id = ?', {propertyId})
    if player.PlayerData.citizenid ~= property.owner then return end

    exports.qbx_core:Notify(player.PlayerData.source, string.format('You stopped your rental contract for %s', property.property_name), 'success')
    MySQL.update.await('UPDATE properties SET owner = ?, keyholders = JSON_OBJECT() WHERE id = ?', {nil, propertyId})
    for _ = 1, #insideProperty[propertyId] do
        exitProperty(insideProperty[propertyId][1])
    end
end)

RegisterNetEvent('qbx_properties:server:addDecoration', function(hash, coords, rotation, objectId)
    local player = exports.qbx_core:GetPlayer(source)
    local propertyId = enteredProperty[source]
    local property = MySQL.single.await('SELECT owner, property_name FROM properties WHERE id = ?', {propertyId})
    if player.PlayerData.citizenid ~= property.owner then return end

    if objectId then
        lib.triggerClientEvent('qbx_properties:client:removeDecoration', insideProperty[propertyId], objectId)
        MySQL.update.await('UPDATE properties_decorations SET coords = ?, rotation = ? WHERE id = ?', { json.encode(coords), json.encode(rotation), objectId })
        lib.triggerClientEvent('qbx_properties:client:addDecoration', insideProperty[propertyId], objectId, hash, coords, rotation)
    else
        local id = MySQL.insert.await('INSERT INTO `properties_decorations` (property_id, model, coords, rotation) VALUES (?, ?, ?, ?)', {propertyId, hash, json.encode(coords), json.encode(rotation)})
        lib.triggerClientEvent('qbx_properties:client:addDecoration', insideProperty[propertyId], id, hash, coords, rotation)
    end
end)

RegisterNetEvent('qbx_properties:server:removeDecoration', function(objectId)
    local player = exports.qbx_core:GetPlayer(source)
    local propertyId = enteredProperty[source]
    local property = MySQL.single.await('SELECT owner FROM properties WHERE id = ?', {propertyId})
    if player.PlayerData.citizenid ~= property.owner then return end

    MySQL.query.await('DELETE FROM properties_decorations WHERE id = ?', {objectId})
    lib.triggerClientEvent('qbx_properties:client:removeDecoration', insideProperty[propertyId], objectId)
end)

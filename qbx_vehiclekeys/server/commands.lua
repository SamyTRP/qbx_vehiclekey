---@param src number
---@return number?
local function getClosestPlayer(src)
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local nearbyPlayers = lib.getNearbyPlayers(playerCoords, 3)
    local closestPlayer, closestDistance
    for i = 1, #nearbyPlayers do
        local nearbyPlayer = nearbyPlayers[i]
        if nearbyPlayer.id ~= source then
            local distance = #(nearbyPlayer.coords - playerCoords)
            if not distance or distance < closestDistance then
                closestPlayer = nearbyPlayer
                closestDistance = distance
            end
        end
    end
    return closestPlayer?.id
end

local function getClosestVehicleServer(coords, maxDistance)
    local closestVehicle, closestDistance = nil, maxDistance
    for _, vehicle in ipairs(GetAllVehicles()) do
        local vehicleCoords = GetEntityCoords(vehicle)
        local distance = #(coords - vehicleCoords)
        if distance < closestDistance then
            closestVehicle = vehicle
            closestDistance = distance
        end
    end
    return closestVehicle
end

---@param source number
---@param target? number
---@param enforceSrcHasKeys boolean if true, source must have keys to transfer
local function transferKeys(source)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = lib.getClosestVehicle(playerCoords, 5.0)
        if not vehicle then
            exports.qbx_core:Notify(source, locale('notify.vehicle_not_near'), 'error')
            return
        end

        -- Anahtarı vereceğimiz en yakın oyuncuyu bul
        local closestPlayer, closestDist = nil, 999.0
        local TRANSFER_RANGE = 3.0

        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if pid and pid ~= source then
                local ped = GetPlayerPed(pid)
                if ped then
                    local dist = #(playerCoords - GetEntityCoords(ped))
                    if dist < closestDist then
                        closestDist = dist
                        closestPlayer = pid
                    end
                end
            end
        end

        if not closestPlayer or closestDist > TRANSFER_RANGE then
            exports.qbx_core:Notify(source, '🚫 Yakınında anahtar verebileceğin kimse yok.', 'error')
            return
        end

        -- En yakın oyuncuya anahtarı ver
        GiveKeyssamy(closestPlayer, vehicle, false, true)

        exports.qbx_core:Notify(source, ('🔑 En yakındaki oyuncuya (%s) anahtar verildi!'):format(GetPlayerName(closestPlayer)), 'success')
        exports.qbx_core:Notify(closestPlayer, '🔑 Bir araç anahtarı sana verildi!', 'success')
end

local function transferKeysamy(source, target, enforceSrcHasKeys)
    local playerPed = GetPlayerPed(source)
    local playerCoords = GetEntityCoords(playerPed)
    local vehicle = getClosestVehicleServer(playerCoords, 5.0)
    if not vehicle then
        exports.qbx_core:Notify(source, locale('notify.vehicle_not_near'), 'error')
        return
    end
    if enforceSrcHasKeys and not HasKeys(source, vehicle) then
        exports.qbx_core:Notify(source, locale('notify.no_keys'), 'error')
        return
    end
    if target and type(target) == 'number' then
        GiveKeyssamy(target, vehicle)
    elseif GetVehiclePedIsIn(playerPed, false) == vehicle then -- Give keys to everyone in vehicle
        for i = -1, 7 do
            local ped = GetPedInVehicleSeat(vehicle, i)
            local serverId = ped and NetworkGetEntityOwner(ped)
            if serverId and serverId ~= source then
                GiveKeyssamy(serverId, vehicle)
            end
        end

        exports.qbx_core:Notify(source, locale('notify.gave_keys'))
    else -- Give keys to closest player
        local closestPlayer = getClosestPlayer(source)
        if closestPlayer then
            GiveKeyssamy(closestPlayer, vehicle)
        end
    end
end


lib.addCommand(locale('addcom.givekeys'), {
    help = locale('addcom.givekeys_help'),
    params = {
        {
            name = locale('addcom.givekeys_id'),
            type = 'playerId',
            help = locale('addcom.givekeys_id_help'),
            optional = true
        },
    },
    restricted = false,
}, function (source, args)
    transferKeys(source, args[locale('addcom.givekeys_id')], true)
end)

lib.addCommand(locale('addcom.addkeys'), {
    help = locale('addcom.addkeys_help'),
    params = {
        {
            name = locale('addcom.addkeys_id'),
            type = 'playerId',
            help = locale('addcom.addkeys_id_help'),
            optional = true,
        },
    },
    restricted = 'group.admin',
}, function (source, args)
    local playerId = args[locale('addcom.addkeys_id')]
    transferKeysamy(source, playerId, false)
end)



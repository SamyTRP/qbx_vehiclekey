local config = require 'config.server'
local debug = GetConvarInt(('%s-debug'):format(GetCurrentResourceName()), 0) == 1

---@alias CitizenId string
---@alias SessionId integer
---@type table<CitizenId, table<SessionId, boolean>>
local loggedOutKeys = {} ---holds key status for some time after player logs out (Prevents frustration by crashing the client)

---@alias LogoutTime integer
---@type table<CitizenId, LogoutTime>
local logedOutTime = {} ---Life timestamp of the keys of a character who has logged out

---Gets Citizen Id based on source
---@param source number ID of the player
---@return string? citizenid The player CitizenID, nil otherwise.
local function getCitizenId(source)
    local player = exports.qbx_core:GetPlayer(source)
    if not player then return end

    return player.PlayerData.citizenid
end

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    local src = source
    local citizenId = getCitizenId(src)
    if not citizenId then return end
    if loggedOutKeys[citizenId] then
        Player(src).state:set('keysList', loggedOutKeys[citizenId], true)
        loggedOutKeys[citizenId] = nil
        logedOutTime[citizenId] = nil
    end
end)

local function onPlayerUnload(src)
    local citizenId = getCitizenId(src)
    if not citizenId then return end
    loggedOutKeys[citizenId] = Player(src).state.keysList
    logedOutTime[citizenId] = os.time()
end

RegisterNetEvent('QBCore:Server:OnPlayerUnload', onPlayerUnload)

AddEventHandler('playerDropped', function()
    onPlayerUnload(source)
end)

---Removes old keys from server memory
lib.cron.new('*/'..config.runClearCronMinutes ..' * * * *', function ()
    local time = os.time()
    local seconds = config.runClearCronMinutes * 60
    for citizenId, lifetime in pairs(logedOutTime) do
        if lifetime + seconds < time then
            loggedOutKeys[citizenId] = nil
            logedOutTime[citizenId] = nil
        end
    end
end, {debug = debug})

--- Removing the vehicle keys from the user
---@param source number ID of the player
---@param vehicle number
---@param skipNotification? boolean
function RemoveKeys(source, vehicle, skipNotification)
    local citizenid = getCitizenId(source)
    if not citizenid then return end

    local keys = Player(source).state.keysList
    if not keys then return end

    local sessionId = Entity(vehicle).state.sessionId
    if not keys[sessionId] then return end
    keys[sessionId] = nil

    Player(source).state:set('keysList', keys, true)

    TriggerClientEvent('qbx_vehiclekeys:client:OnLostKeys', source)
    if not skipNotification then
        exports.qbx_core:Notify(source, locale('notify.keys_removed'))
    end

    return true
end

exports('RemoveKeys', RemoveKeys)


function GiveKeys(source, vehicle, skipNotification, transferkey)
    local citizenid = getCitizenId(source)
    if not citizenid then return false end

    -- Temel validasyonlar
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
        exports.qbx_core:Notify(source, '🚫 Geçerli bir araç hedeflenmedi.', 'error')
        return false
    end

    local ped = GetPlayerPed(source)
    if not ped then
        exports.qbx_core:Notify(source, '🚫 Oyuncu ped bulunamadı.', 'error')
        return false
    end

    -- Yakınlık kontrolü (genel)
    local playerVeh = GetVehiclePedIsIn(ped, false)
    local GIVE_RANGE = 5.0
    local vehCoords = GetEntityCoords(vehicle)
    local plyCoords = GetEntityCoords(ped)
    local distToVeh = #(vehCoords - plyCoords)

    if playerVeh ~= vehicle and distToVeh > GIVE_RANGE then
        -- oyuncu ne araçta ne de aracın çok yakınında
        return false
    end

    local plate = GetVehicleNumberPlateText(vehicle)
    if not plate or plate == '' then
        exports.qbx_core:Notify(source, '🚫 Araç plakası bulunamadı.', 'error')
        return false
    end

    local sessionId = Entity(vehicle).state.sessionId or exports.qbx_core:CreateSessionId(vehicle)
    if not sessionId then
        exports.qbx_core:Notify(source, '🚫 SessionId oluşturulamadı.', 'error')
        return false
    end

    ----------------------------------------------------------------------
    -- TRANSFER KEY MODU (GÜÇLENDİRİLMİŞ: yakında olma veya zaten anahtar sahibi olma)
    ----------------------------------------------------------------------
    if transferkey == true or transferkey == "true" then
        local TRANSFER_RANGE = 3.0
        -- kaynak oyuncunun koordinatları hazır (plyCoords)
        local srcCoords = plyCoords

        -- en yakın oyuncuyu bul
        local closestPlayer, closestDist
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if pid and pid ~= source then
                local otherPed = GetPlayerPed(pid)
                if otherPed then
                    local otherCoords = GetEntityCoords(otherPed)
                    local d = #(srcCoords - otherCoords)
                    if not closestDist or d < closestDist then
                        closestDist = d
                        closestPlayer = pid
                    end
                end
            end
        end

        if not closestPlayer or closestDist > TRANSFER_RANGE then
            exports.qbx_core:Notify(source, '🚫 Yakınında anahtar verebileceğin kimse yok.', 'error')
            return false
        end

        -- kaynak oyuncunun anahtar listesi (sunucu state)
        local srcKeys = Player(source).state.keysList or {}

        -- Eğer kaynak oyuncunun anahtarı yoksa ama araçla YAKINSA buna izin ver (yolda naldığın senaryosu)
        local sourceHasKey = srcKeys[sessionId] == true
        local sourceInVehicle = (playerVeh == vehicle)
        local sourceIsNearVehicle = distToVeh <= GIVE_RANGE

        if not sourceHasKey and not sourceInVehicle and not sourceIsNearVehicle then
            exports.qbx_core:Notify(source, '🚫 Anahtarın yok ve araçla ilişkili değilsin; transfer yapılamıyor.', 'error')
            return false
        end

        -- hedef oyuncunun mevcut keysList'ini al (varsa koru, üzerine ekle)
        local targetKeys = Player(closestPlayer).state.keysList or {}
        targetKeys[sessionId] = true
        Player(closestPlayer).state:set('keysList', targetKeys, true)

        -- eğer kaynakta anahtar varsa onu kaldır (çalıntıysa zaten yoktur; böylece kaldırma yapmaz)
        if sourceHasKey then
            srcKeys[sessionId] = nil
            Player(source).state:set('keysList', srcKeys, true)
        end

        exports.qbx_core:Notify(source, ('🔑 %s plakalı aracın anahtarı verildi.'):format(plate))
        exports.qbx_core:Notify(closestPlayer, ('🔑 %s plakalı araç anahtarı sana verildi.'):format(plate))

        return true
    end

    ----------------------------------------------------------------------
    -- NORMAL ANAHTAR VERME (TRANSFER DEĞİLSE)
    ----------------------------------------------------------------------
    local result = MySQL.single.await('SELECT citizenid, job FROM player_vehicles WHERE plate = ?', {plate})
    if not result then
        return false
    end

    local allowedToGive = false
    if result.citizenid == citizenid then
        allowedToGive = true
    elseif result.job and result.job ~= '' then
        local playerObj = exports.qbx_core:GetPlayer(source)
        if playerObj and playerObj.PlayerData.job and playerObj.PlayerData.job.name == result.job then
            allowedToGive = true
        end
    end
    if transferkey == false then
        if not allowedToGive then
            local needMsg = result.job and ('🚫 Bu araca anahtar almak/vermek için %s işi gerekli.'):format(result.job)
                or '🚫 Bu aracın sahibi değilsin ve iş iznin yok.'
            exports.qbx_core:Notify(source, needMsg, 'error')
            return false
        end
    end

    local keys = Player(source).state.keysList or {}
    if keys[sessionId] then return true end

    keys[sessionId] = true
    Player(source).state:set('keysList', keys, true)

    exports.qbx_core:Notify(source, ('🔑 %s plakalı aracın anahtarını aldın.'):format(plate))
    return true
end



---@param source number
---@param vehicle number
---@param skipNotification? boolean
-- function GiveKeys(source, vehicle, skipNotification)
--     local citizenid = getCitizenId(source)
--     if not citizenid then return end

--     local plate = GetVehicleNumberPlateText(vehicle)
--     local result = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ?', {plate})

--     if not result then
--         -- exports.qbx_core:Notify(source, '🚫 Bu aracın sahibi veritabanında bulunamadı.', 'error')
--         return false
--     end

--     -- Eğer araç sahibi oyuncunun citizenid'si değilse
--     if result.citizenid ~= citizenid then
--         -- exports.qbx_core:Notify(source, '🚫 Bu aracın sahibi sen değilsin, anahtar alamazsın.', 'error')
--         return false
--     end

--     local sessionId = Entity(vehicle).state.sessionId or exports.qbx_core:CreateSessionId(vehicle)
--     local keys = Player(source).state.keysList or {}
--     if keys[sessionId] then return end

--     keys[sessionId] = true
--     Player(source).state:set('keysList', keys, true)

--     if not skipNotification then
--         exports.qbx_core:Notify(source, locale('notify.keys_taken'))
--     end

--     return true
-- end


function GiveKeyssamy(source, vehicle, skipNotification)
    
    local citizenid = getCitizenId(source)
    if not citizenid then return end

    local sessionId = Entity(vehicle).state.sessionId or exports.qbx_core:CreateSessionId(vehicle)
    local keys = Player(source).state.keysList or {}
    if keys[sessionId] then return end

    keys[sessionId] = true

    Player(source).state:set('keysList', keys, true)
    if not skipNotification then
        exports.qbx_core:Notify(source, locale('notify.keys_taken'))
    end
    return true
end


-- function GiveKeys(source, vehicle, skipNotification, transferkey)
--     local citizenid = getCitizenId(source)
--     if not citizenid then return false end

--     -- ---------- Yeni: araç geçerlilik & yakınlık kontrolleri ----------
--     if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
--         exports.qbx_core:Notify(source, '🚫 Geçerli bir araç hedeflenmedi.', 'error')
--         return false
--     end

--     local ped = GetPlayerPed(source)
--     if not ped then
--         exports.qbx_core:Notify(source, '🚫 Oyuncu ped bulunamadı.', 'error')
--         return false
--     end

--     local playerVeh = GetVehiclePedIsIn(ped, false)
--     local GIVE_RANGE = 5.0 -- gerekirse burayı değiştir

--     -- Eğer oyuncu araçta değilse, aracın oyuncuya yakın olup olmadığını kontrol et
--     if playerVeh ~= vehicle then
--         local vehCoords = GetEntityCoords(vehicle)
--         local plyCoords = GetEntityCoords(ped)
--         local dist = #(vehCoords - plyCoords)

--         if dist > GIVE_RANGE then
--             -- exports.qbx_core:Notify(source, ('🚫 Bu araçla yeterince yakın değilsin (%.1fm).'):format(dist), 'error')
--             return false
--         end
--     end
--     -- ------------------------------------------------------------------

--     local plate = GetVehicleNumberPlateText(vehicle)
--     if not plate or plate == '' then
--         exports.qbx_core:Notify(source, '🚫 Araç plakası bulunamadı.', 'error')
--         return false
--     end

--     local sessionId = Entity(vehicle).state.sessionId or exports.qbx_core:CreateSessionId(vehicle)
--     if not sessionId then
--         exports.qbx_core:Notify(source, '🚫 SessionId oluşturulamadı.', 'error')
--         return false
--     end

--     ----------------------------------------------------------------------
--     -- 🚀 TRANSFER KEY MODU - SAHİPLİK / JOB KONTROLÜ YOK
--     ----------------------------------------------------------------------
--     if transferkey == true or transferkey == "true" then
--         local TRANSFER_RANGE = 3.0
--         local srcPed = GetPlayerPed(source)
--         if not srcPed then return false end

--         local srcCoords = GetEntityCoords(srcPed)
--         local closestPlayer, closestDist

--         for _, pid in ipairs(GetPlayers()) do
--             pid = tonumber(pid)
--             if pid and pid ~= source then
--                 local ped = GetPlayerPed(pid)
--                 if ped then
--                     local dist = #(srcCoords - GetEntityCoords(ped))
--                     if not closestDist or dist < closestDist then
--                         closestDist = dist
--                         closestPlayer = pid
--                     end
--                 end
--             end
--         end

--         if not closestPlayer or closestDist > TRANSFER_RANGE then
--             exports.qbx_core:Notify(source, '🚫 Yakınında anahtar verebileceğin kimse yok.', 'error')
--             return false
--         end

--         -- Anahtar aktarımı
--         local targetKeys = {}
--         targetKeys[sessionId] = true
--         Player(closestPlayer).state:set('keysList', targetKeys, true)

--         local srcKeys = Player(source).state.keysList or {}
--         srcKeys[sessionId] = nil
--         Player(source).state:set('keysList', srcKeys, true)

--         exports.qbx_core:Notify(source, ('🔑 %s plakalı aracın anahtarı verildi.'):format(plate))
--         exports.qbx_core:Notify(closestPlayer, ('🔑 %s plakalı araç anahtarı sana verildi.'):format(plate))

--         return true -- 🔥 BURADA KESİN ÇIKIŞ!
--     end

--     ----------------------------------------------------------------------
--     -- 🔒 NORMAL ANAHTAR VERME (TRANSFER DEĞİLSE)
--     ----------------------------------------------------------------------
--     local result = MySQL.single.await('SELECT citizenid, job FROM player_vehicles WHERE plate = ?', {plate})
--     if not result then
--         -- exports.qbx_core:Notify(source, '🚫 Bu aracın kaydı bulunamadı.', 'error')
--         return false
--     end

--     local allowedToGive = false
--     if result.citizenid == citizenid then
--         allowedToGive = true
--     elseif result.job and result.job ~= '' then
--         local playerObj = exports.qbx_core:GetPlayer(source)
--         if playerObj and playerObj.PlayerData.job and playerObj.PlayerData.job.name == result.job then
--             allowedToGive = true
--         end
--     end
--     if transferkey == false then
--         if not allowedToGive then
--             local needMsg = result.job and ('🚫 Bu araca anahtar almak/vermek için %s işi gerekli.'):format(result.job)
--                 or '🚫 Bu aracın sahibi değilsin ve iş iznin yok.'
--             exports.qbx_core:Notify(source, needMsg, 'error')
--             return false
--         end
--     end

--     ----------------------------------------------------------------------
--     -- 🔑 ANAHTAR VERME
--     ----------------------------------------------------------------------
--     local keys = Player(source).state.keysList or {}
--     if keys[sessionId] then return true end

--     keys[sessionId] = true
--     Player(source).state:set('keysList', keys, true)

--     exports.qbx_core:Notify(source, ('🔑 %s plakalı aracın anahtarını aldın.'):format(plate))
--     return true
-- end

exports('GiveKeyssamy', GiveKeyssamy)
exports('GiveKeys', GiveKeys)

---@param src number
---@param vehicle number
---@return boolean
function HasKeys(src, vehicle)
    local keysList = Player(src).state.keysList
    if keysList then
        local sessionId = Entity(vehicle).state.sessionId
        if keysList[sessionId] then
            return true
        end
    end

    local owner = Entity(vehicle).state.owner
    if owner and getCitizenId(src) == owner then
        GiveKeys(src, vehicle)
        return true
    end

    return false
end

exports('HasKeys', HasKeys)

lib.callback.register('qbx_vehiclekeys:server:giveKeys', function(source, netId)
    GiveKeys(source, NetworkGetEntityFromNetworkId(netId))
end)

AddStateBagChangeHandler('vehicleid', '', function(bagName, _, vehicleId)
    local vehicle = GetEntityFromStateBagName(bagName)
    if not vehicle or vehicle == 0 then return end
    local owner = exports.qbx_vehicles:GetPlayerVehicle(vehicleId)?.citizenid
    if not owner then return end
    Entity(vehicle).state:set('owner', owner, true)
end)

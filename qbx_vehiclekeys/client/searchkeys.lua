local config = require 'config.client'
local isSearchLocked = false
local isSearchAllowed = false

local function setSearchLabelState(isAllowed)
    if isSearchLocked and isAllowed then return end
    if isAllowed and cache.vehicle and GetVehicleConfig(cache.vehicle).findKeysChance == 0.0 then
        isSearchAllowed = false
        return
    end
    local isOpen, text = lib.isTextUIOpen()
    local newText = 'Anahtarları ara [~g~H~s~]'
    local isValidMessage = text and text == newText
    if isAllowed and not isValidMessage and cache.seat == -1 then
        lib.showTextUI(newText)
    elseif (not isAllowed or cache.seat ~= -1) and isOpen and isValidMessage then
        lib.hideTextUI()
    end

    isSearchAllowed = isAllowed and cache.seat == -1
end

-- config.client içine ekle (yoksa):
-- config.keysSkillCheckDifficulty = {'easy', 'easy', 'medium'}
-- config.keysSkillCheckKeys = {'w', 'a', 's', 'd'}

local function findKeys(vehicleModel, vehicleClass, vehicle)
    if cache.vehicle ~= vehicle then return false end

    local anim = config.anims.searchKeys.model[vehicleModel]
        or config.anims.searchKeys.model[vehicleClass]
        or config.anims.searchKeys.default

    local searchingForKeys = true
    CreateThread(function()
        while searchingForKeys do
            if not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 49) then
                lib.playAnim(cache.ped, anim.dict, anim.clip, 3.0, 1.0, -1, 49)
            end
            Wait(100)
        end
    end)

    local skillPassed = lib.skillCheck(
        config.keysSkillCheckDifficulty or { 'easy', 'medium', 'easy', 'medium', 'easy', 'medium', 'easy', 'medium', 'easy', 'medium', },
        config.keysSkillCheckKeys or { 'w', 'a', 's', 'd' }
    )

    searchingForKeys = false
    ClearPedTasks(cache.ped)

    local success = false

    if skillPassed and cache.vehicle == vehicle then
        local result = lib.callback.await('qbx_vehiclekeys:server:findKeys', false, VehToNet(vehicle))
        success = result == true
    end

    if not success then
        TriggerServerEvent('hud:server:GainStress', math.random(1, 4))
        exports.qbx_core:Notify('Anahtarları bulamadın.', 'error')

        lib.showTextUI('Anahtar bulunamadı...', { position = 'bottom' })
        Wait(5000)
        lib.hideTextUI()
    end

    return success
end

local searchKeysKeybind = lib.addKeybind({
    name = 'searchkeys',
    description = 'Araç Anahtarlarını Ara',
    defaultKey = 'H',
    secondaryMapper = 'PAD_DIGITALBUTTONANY',
    secondaryKey = 'LRIGHT_INDEX',
    disabled = true,
    onPressed = function()
        if not (isSearchAllowed and cache.vehicle) then return end

        TriggerEvent('tgiann-PolisBildirim:BildirimGonder', 'Araç Gasp İhbarı', '10-55', false)

        isSearchLocked = true
        setSearchLabelState(false)

        local vehicle = cache.vehicle
        local isFound = false

        if not GetIsVehicleAccessible(vehicle) then
            isFound = findKeys(GetEntityModel(vehicle), GetVehicleClass(vehicle), vehicle)
            -- SendPoliceAlertAttempt('steal', vehicle)
        end

        Wait(config.timeBetweenHotwires)
        isSearchLocked = false
        setSearchLabelState(not isFound)
    end
})

function GetKeySearchEnabled()
    return isSearchAllowed
end

function EnableKeySearch()
    setSearchLabelState(true)
    searchKeysKeybind:disable(false)
end

function DisableKeySearch()
    setSearchLabelState(false)
    searchKeysKeybind:disable(true)
end
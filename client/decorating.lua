IsDecorating = false
local camera
local previewObject
local cursorMode = false
local IsDisabledControlPressed = IsDisabledControlPressed
local SetCamCoord = SetCamCoord
local SetCamRot = SetCamRot
local GetCamCoord = GetCamCoord
local GetCamRot = GetCamRot
---@diagnostic disable-next-line: unused-local
local GetHashKey = GetHashKey

local function freeCam()
    local cameraPosition = GetGameplayCamCoord()
    local cameraRotation = GetGameplayCamRot(2)
    local cameraFov = GetGameplayCamFov()
    camera = CreateCameraWithParams('DEFAULT_SCRIPTED_CAMERA', cameraPosition.x, cameraPosition.y, cameraPosition.z, cameraRotation.x, cameraRotation.y, cameraRotation.z, cameraFov, true, 2)
    CreateThread(function()
        local multiplier = 0.1
        while IsDecorating do
            cameraPosition = GetCamCoord(camera)
            cameraRotation = GetCamRot(camera, 2)
            local forwardX = -math.sin(math.rad(cameraRotation.z))
            local forwardY = math.cos(math.rad(cameraRotation.z))
            local rightX = math.cos(math.rad(cameraRotation.z))
            local rightY = math.sin(math.rad(cameraRotation.z))
            local upwardZ = math.sin(math.rad(cameraRotation.x))
            if IsDisabledControlPressed(0, 241) then
                multiplier = multiplier + 0.01
            end
            if IsDisabledControlPressed(0, 242) then
                multiplier = multiplier - 0.01
            end
            if multiplier < 0.01 then multiplier = 0.001 end
            if multiplier > 1.0 then multiplier = 1.0 end
            if IsDisabledControlPressed(0, 32) then
                cameraPosition = cameraPosition + vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
            end
            if IsDisabledControlPressed(0, 33) then
                cameraPosition = cameraPosition - vector3(forwardX * multiplier, forwardY * multiplier, upwardZ * multiplier)
            end
            if IsDisabledControlPressed(0, 34) then
                cameraPosition = cameraPosition - vector3(rightX * multiplier, rightY * multiplier, 0)
            end
            if IsDisabledControlPressed(0, 35) then
                cameraPosition = cameraPosition + vector3(rightX * multiplier, rightY * multiplier, 0)
            end
            if IsDisabledControlPressed(0, 36) then
                cameraPosition = cameraPosition - vector3(0, 0, multiplier)
            end
            if IsDisabledControlPressed(0, 203) then
                cameraPosition = cameraPosition + vector3(0, 0, multiplier)
            end
            cameraRotation = cameraRotation - vector3(GetDisabledControlNormal(0, 272) * 5, 0, GetDisabledControlNormal(0, 270) * 5)
            SetCamCoord(camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
            SetCamRot(camera, math.min(math.max(cameraRotation.x, -89), 89), cameraRotation.y, cameraRotation.z, 2)
            Wait(0)
        end
        DestroyCam(camera, false)
    end)
    SetPlayerControl(cache.playerId, not IsDecorating, 0)
    RenderScriptCams(IsDecorating, true, 1000, true, true)
end

local function showText()
    if cursorMode then
        lib.showTextUI('BACKSPACE - Exit  \n LALT - Toggle Cursor Mode  \n T - Move Object  \n R - Rotate Object  \n G - Snap To Ground')
    else
        lib.showTextUI('BACKSPACE - Exit  \n SPACE - Up  \n LCTRL - Down  \n WHEELUP - Speedup  \n WHEELDOWN - Slowdown  \n E - Add Object  \n DEL - Delete Object  \n LALT - Toggle Cursor Mode')
    end
end

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    local view = DataView.ArrayBuffer(60)
    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
    return view
end

local function applyEntityMatrix(entity, view)
    SetEntityMatrix(entity,
        view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24),
        view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8),
        view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40),
        view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)
    )
end

function ToggleDecorating()
    IsDecorating = not IsDecorating
    freeCam()
    showText()
    while IsDecorating do
        Wait(0)
        if IsDisabledControlJustReleased(0, 202) then
            ToggleDecorating()
        end
        if IsDisabledControlJustReleased(0, 38) then
            lib.showContext('qbx_properties_decoratingMenu')
        end
        if IsDisabledControlJustReleased(0, 19) then
            cursorMode = not cursorMode
            showText()
            if cursorMode then
                EnterCursorMode()
            else
                LeaveCursorMode()
            end
        end
        if IsDisabledControlJustReleased(0, 214) then
            if DoesEntityExist(previewObject) then
                DeleteEntity(previewObject)
            end
        end
        if IsDisabledControlJustReleased(0, 47) then
            PlaceObjectOnGroundProperly(previewObject)
        end
        if DoesEntityExist(previewObject) then
            local matrixBuffer = makeEntityMatrix(previewObject)
            local changed = Citizen.InvokeNative(0xEB2EDCA2, matrixBuffer:Buffer(), 'Editor1', Citizen.ReturnResultAnyway())
            if changed then
                applyEntityMatrix(previewObject, matrixBuffer)
            end
        end
    end
    lib.hideTextUI()
    if DoesEntityExist(previewObject) then
        DeleteEntity(previewObject)
    end
end

RegisterKeyMapping('+gizmoTranslation', 'Sets mode of the gizmo to translation', 'keyboard', 'T')
RegisterKeyMapping('+gizmoRotation', 'Sets mode for the gizmo to rotation', 'keyboard', 'R')

local decoratingOptions = {}
for k, v in pairs(Furniture) do
    local menuId = string.format('qbx_properties_decoratingMenu_%s', k)
    decoratingOptions[#decoratingOptions + 1] = {
        title = k,
        menu = menuId
    }

    local furnitureOptions = {}
    for i = 1, #v do
        local furniture = v[i]
        furnitureOptions[#furnitureOptions + 1] = {
            title = furniture.label,
            onSelect = function(args)
                if DoesEntityExist(previewObject) then
                    DeleteEntity(previewObject)
                end
                local modelHash = GetHashKey(args.object)
                lib.requestModel(modelHash, 5000)
                local camCoords = GetCamCoord(camera)
                local camRotation = GetCamRot(camera, 2)
                local forwardCoords = camCoords + vector3(-math.sin(math.rad(camRotation.z)), math.cos(math.rad(camRotation.z)), math.sin(math.rad(camRotation.x)) * 1.2) * 2
                previewObject = CreateObjectNoOffset(modelHash, forwardCoords.x, forwardCoords.y, forwardCoords.z, false, false, false)
                SetModelAsNoLongerNeeded(modelHash)
                FreezeEntityPosition(previewObject, true)
                SetEntityCollision(previewObject, false, false)
                SetEntityDrawOutline(previewObject, true)
            end,
            image = string.format('nui://qbx_properties/screenshots/%s.png', furniture.object),
            args = {
                object = furniture.object,
                label = furniture.label
            }
        }
    end
    lib.registerContext({
        id = menuId,
        title = k,
        menu = 'qbx_properties_decoratingMenu',
        options = furnitureOptions
    })
end

lib.registerContext({
    id = 'qbx_properties_decoratingMenu',
    title = locale('menu.decorating_categories'),
    options = decoratingOptions
})

-- this command should not be used in production. Dev command only to create images of the objects put into the Furniture table.
-- RegisterCommand('screenshotfurniture', function()
--     local modelHash = GetHashKey('prop_ld_greenscreen_01')
--     lib.requestModel(modelHash, 5000)
--     local greenScreen = CreateObject(modelHash, -1894.99, -3357.08, 145.35, false, false, false)
--     SetModelAsNoLongerNeeded(modelHash)
--     FreezeEntityPosition(greenScreen, true)
--     CreateThread(function()
--         while DoesEntityExist(greenScreen) do
--             local forward, right, upVector, position = GetEntityMatrix(greenScreen)
--             SetEntityMatrix(greenScreen, forward.x, 20.0, forward.z, 20.0, right.y, right.z, upVector.x, upVector.y, 20.0, position.x, position.y, position.z)
--             Wait(0)
--         end
--     end)
--     DisableIdleCamera(true)
--     local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
--     RenderScriptCams(true, false, 0, false, false)
--     for _, v in pairs(Furniture) do
--         for i = 1, #v do
--             modelHash = GetHashKey(v[i].object)
--             lib.requestModel(modelHash, 5000)
--             local object = CreateObjectNoOffset(modelHash, -1899.83, -3340.52, 150.24, false, false, false)
--             SetModelAsNoLongerNeeded(modelHash)
--             FreezeEntityPosition(object, true)
--             local minDimension, maxDimension = GetModelDimensions(modelHash)
--             local modelSize = maxDimension - minDimension
--             local fov = math.min(math.max(modelSize.x, modelSize.y) / 0.35 * 10, 60)
--             local objectCoords = GetEntityCoords(object)
--             local objectForward = -GetEntityForwardVector(object) * 2
--             local center = vector3(objectCoords.x + (minDimension.x + maxDimension.x) / 2, objectCoords.y + (minDimension.y + maxDimension.y) / 2, objectCoords.z + (minDimension.z + maxDimension.z) / 2)
--             local cameraPosition = center + objectForward * 2 + vector3(1.5, -1, 1.5 * modelSize.z)
--             SetCamFov(cam, fov)
--             SetCamCoord(cam, cameraPosition.x, cameraPosition.y, cameraPosition.z)
--             PointCamAtCoord(cam, center.x, center.y, center.z)
--             TriggerServerEvent('screenshotFurniture', v[i].object)
--             Wait(1000)
--             DeleteEntity(object)
--         end
--     end
--     DestroyCam(cam, false)
--     RenderScriptCams(false, false, 0, false, false)
--     DisableIdleCamera(false)
--     DeleteEntity(greenScreen)
-- end)

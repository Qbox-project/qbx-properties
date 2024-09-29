local BoardCoords = vec4(-44.19, -585.99, 87.71, 250.0)
local BoardModel = `tr_prop_tr_planning_board_01a`
local RenderTarget = 'modgarage_01'
local Board, scaleform, buttonsScaleform
local currentButtonID = 1
local previewCam

local function SetupBoard()
    lib.requestModel(BoardModel, 10000)
    Board = CreateObject(BoardModel, BoardCoords.x, BoardCoords.y, BoardCoords.z, false, false, false)
    SetEntityHeading(Board, BoardCoords.w)
    SetModelAsNoLongerNeeded(BoardModel)
end

local function SetupInstructionalScaleform()
    -- reset the scaleform
    buttonsScaleform:Method('CLEAR_ALL')
    buttonsScaleform:MethodArgs('SET_CLEAR_SPACE', { 200 })

    -- Define the buttons
    local sumbit = GetControlInstructionalButton(2, 191, true)
    local up = GetControlInstructionalButton(2, 188, true)
    local down = GetControlInstructionalButton(2, 187, true)

    -- Add the buttons
    buttonsScaleform:MethodArgs('SET_DATA_SLOT', { 0, sumbit, locale('instructButtons.submit') })
    buttonsScaleform:MethodArgs('SET_DATA_SLOT', { 1, up, locale('instructButtons.down') })
    buttonsScaleform:MethodArgs('SET_DATA_SLOT', { 2, down, locale('instructButtons.up') })

    -- Draw the buttons
    buttonsScaleform:Method('DRAW_INSTRUCTIONAL_BUTTONS')
end

local function StartScaleform()
    scaleform = qbx.newScaleform("AUTO_SHOP_BOARD")
    scaleform:RenderTarget(RenderTarget, BoardModel)

    scaleform:SetFullScreen(false)
    scaleform:SetProperties(0.25, 0.5, 0.5, 1.0)

    buttonsScaleform = qbx.newScaleform("INSTRUCTIONAL_BUTTONS")

    CreateThread(function()
        SetupInstructionalScaleform()
        scaleform:Draw(true)
        buttonsScaleform:Draw(true)

        while DoesCamExist(previewCam) do
            HideHudComponentThisFrame(6)
            HideHudComponentThisFrame(7)
            HideHudComponentThisFrame(9)
            Wait(0)
        end

        scaleform:Dispose()
        scaleform = nil

        buttonsScaleform:Dispose()
        buttonsScaleform = nil
    end)
end

local function SetupScaleform()
    -- Somehow doesn't update the screen unless you make it blank first. Even though the actionscript suggest it cleans the screen itself internally. :shrug:
    scaleform:Method('SHOW_BLANK_SCREEN')
    scaleform:MethodArgs('SET_STYLE', {3})

    -- Smart math that isn't modular at all. Can't wait for the support questions for this one
    local StartingPoint
    if currentButtonID < 4 then
        StartingPoint = 1
    elseif currentButtonID < 7 then
        StartingPoint = 4
    end

    local selectionArgs = {}
    for i = StartingPoint, StartingPoint + 2 do
        selectionArgs[#selectionArgs+1] = string.format('selection%s', i)
        selectionArgs[#selectionArgs+1] = ApartmentOptions[i].label
        selectionArgs[#selectionArgs+1] = ApartmentOptions[i].description
        selectionArgs[#selectionArgs+1] = 0
    end

    selectionArgs[#selectionArgs+1] = string.format('%s/%s', currentButtonID, #ApartmentOptions)
    selectionArgs[#selectionArgs+1] = 0
    selectionArgs[#selectionArgs+1] = true
    selectionArgs[#selectionArgs+1] = true
    selectionArgs[#selectionArgs+1] = true

    -- Same "modular" bullshit here. Had no success with CURRENT_SELECTION nor CURRENT_ROLLOVER, not sure why.
    for i = StartingPoint, StartingPoint + 2 do
        if i == currentButtonID then
            selectionArgs[#selectionArgs+1] = true
        else
            selectionArgs[#selectionArgs+1] = false
        end
    end

    scaleform:MethodArgs('SHOW_SELECTION_SCREEN', selectionArgs)
end

function SetupCamera(apartmentCam)
    if apartmentCam then
        previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', -46.33, -585.24, 89.29, -5.0, 0.0, 250.0, 60.0, false, 2)
        SetCamActive(previewCam, true)
        SetCamFarDof(previewCam, 0.65)
        SetCamDofStrength(previewCam, 0.5)
        RenderScriptCams(true, false, 1, true, true)
        CreateThread(function()
            while DoesCamExist(previewCam) do
                SetUseHiDof()
                Wait(0)
            end
        end)
    else
        previewCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', -24.77, -590.35, 90.8, -2.0, 0.0, 160.0, 45.0, false, 2)
        SetCamActive(previewCam, true)
        RenderScriptCams(true, false, 1, true, true)
    end
end

function StopCamera()
    SetCamActive(previewCam, false)
    DestroyCam(previewCam, true)
end

function ManagePlayer()
    SetEntityCoords(cache.ped, -21.58, -583.76, 86.31, false, false, false, false)
    FreezeEntityPosition(cache.ped, true)
    SetTimeout(500, function()
        DoScreenFadeIn(5000)
    end)
end

local function InputHandler()
    while true do
        if IsControlJustReleased(0, 188) then
            currentButtonID -= 1
            if currentButtonID < 1 then currentButtonID = #ApartmentOptions end
            SetupScaleform()
        elseif IsControlJustReleased(0, 187) then
            currentButtonID += 1
            if currentButtonID > #ApartmentOptions then currentButtonID = 1 end
            SetupScaleform()
        elseif IsControlJustReleased(0, 191) then
            local alert = lib.alertDialog({
                header = locale('alert.apartment_selection'),
                content = string.format(locale('alert.are_you_sure'), ApartmentOptions[currentButtonID].label),
                centered = true,
                cancel = true
            })
            if alert == 'confirm' then
                DoScreenFadeOut(500)
                while not IsScreenFadedOut() do Wait(0) end
                FreezeEntityPosition(cache.ped, false)
                SetEntityCoords(cache.ped, ApartmentOptions[currentButtonID].enter.x, ApartmentOptions[currentButtonID].enter.y, ApartmentOptions[currentButtonID].enter.z - 2.0, false, false, false, false)
                Wait(0)
                TriggerServerEvent('qbx_properties:server:apartmentSelect', currentButtonID)
                Wait(1000) -- Wait for player to spawn correctly so clothing menu can load in nice
                TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
                TriggerEvent('QBCore:Client:OnPlayerLoaded')
                break
            end
        end
        Wait(0)
    end
    StopCamera()
end

RegisterNetEvent('apartments:client:setupSpawnUI', function()
    Wait(400)
    ManagePlayer()
    SetupCamera(true)
    SetupBoard()
    StartScaleform()
    SetupScaleform()
    InputHandler()
end)

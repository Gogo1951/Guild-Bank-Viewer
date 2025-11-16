local ADDON = ...
local GBV = {}
_G[ADDON] = GBV
local DISPLAY_NAME = "Guild Bank Viewer"

local hasC = C_Container and true or false

local function GBV_GetNumSlots(bag)
    if hasC then
        return C_Container.GetContainerNumSlots(bag)
    end
    return GetContainerNumSlots(bag)
end

local function GBV_GetItemLink(bag, slot)
    if hasC and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return GetContainerItemLink(bag, slot)
end

local function GBV_GetItemInfo(bag, slot)
    if hasC then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info then
            return nil
        end
        local link = C_Container.GetContainerItemLink(bag, slot)
        local itemID = info and info.itemID
        local count = info and info.stackCount or 0
        return itemID, count, link
    else
        local link = GetContainerItemLink(bag, slot)
        if not link then
            return nil
        end
        local _, count = GetContainerItemInfo(bag, slot)
        local iid = (GetItemInfoInstant and select(1, GetItemInfoInstant(link))) or nil
        return iid, count or 0, link
    end
end

local function GBV_GetItemIDFromLink(link)
    if not link then
        return nil
    end
    if GetItemInfoInstant then
        local iid = select(1, GetItemInfoInstant(link))
        if iid then
            return iid
        end
    end
    local itemPart = link and link:match("item:[-%d:]+")
    if not itemPart then
        return nil
    end
    local idStr = select(2, strsplit(":", itemPart))
    return tonumber(idStr)
end

local NAMEC = "|cFFB0BEC5"
local LINKC = "|cFF2196F3"
local SLASHC = "|cFF607D8B"
local TEXTC = "|cFFECEFF1"
local ENDC = "|r"
local ERRORC = "|cFFC41E3A"

local function gbvLink(tag, label)
    return (LINKC .. "|Hgbv:%s|h[%s]|h|r"):format(tag, label)
end

local function now()
    return GetTime()
end

local GBV_BankOpen = false
local GBV_GuildBankOpen = false

local lastShown = {bag = 0, bank = 0, guild = 0}
local COOLDOWN = 3

local function safeAddMessage(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(msg)
    end
end

local function frameShown(name)
    local f = _G[name]
    return f and f:IsShown()
end

local function isBusyContext()
    if (InCombatLockdown and InCombatLockdown()) or UnitAffectingCombat("player") then
        return true
    end
    if
        frameShown("AuctionFrame") or
        frameShown("AuctionHouseFrame") or
        frameShown("BarberShopFrame") or
        frameShown("ClassTrainerFrame") or
        frameShown("GossipFrame") or
        frameShown("GuildRegistrarFrame") or
        frameShown("ItemSocketingFrame") or
        frameShown("MailFrame") or
        frameShown("MerchantFrame") or 
        frameShown("ProfessionsFrame") or
        frameShown("ScrappingMachineFrame") or
        frameShown("TabardFrame") or
        frameShown("TradeFrame") or 
        frameShown("TransmogrifyFrame") or
        frameShown("VoidStorageFrame")
     then
        return true
    end
    return false
end

local BACKPACK = 0
local FIRST_BAG, LAST_BAG = 1, 4
local BANK_CONTAINER = -1
local REAGENTBANK_CONTAINER = -3
local BANK_FIRST, BANK_LAST = 5, 11

local function makeExtended(items)
    local t = {}
    for _, it in ipairs(items) do
        if it.loc.tab then
            table.insert(t, string.format("{i:%d,q:%d,loc:{tab:%d,slot:%d}}", it.i, it.q, it.loc.tab, it.loc.slot))
        elseif it.loc.bag then
            table.insert(t, string.format("{i:%d,q:%d,loc:{bag:%d,slot:%d}}", it.i, it.q, it.loc.bag, it.loc.slot))
        else
            table.insert(t, string.format("{i:%d,q:%d}", it.i, it.q))
        end
    end
    return "{" .. table.concat(t, ",") .. "}"
end

local function collectFromBagRange(firstBag, lastBag)
    local list = {}
    for bag = firstBag, lastBag do
        local slots = GBV_GetNumSlots(bag) or 0
        if slots > 0 then
            for slot = 1, slots do
                local link = GBV_GetItemLink(bag, slot)
                if link then
                    local iid, count = GBV_GetItemInfo(bag, slot)
                    iid = iid or GBV_GetItemIDFromLink(link)
                    if iid and (count or 0) > 0 then
                        table.insert(list, {i = iid, q = count or 1, loc = {bag = bag, slot = slot}})
                    end
                end
            end
        end
    end
    return list
end

local function CollectBags()
    local mixed = {}
    local slots = GBV_GetNumSlots(BACKPACK) or 0
    for slot = 1, slots do
        local link = GBV_GetItemLink(BACKPACK, slot)
        if link then
            local iid, count = GBV_GetItemInfo(BACKPACK, slot)
            iid = iid or GBV_GetItemIDFromLink(link)
            if iid and (count or 0) > 0 then
                table.insert(mixed, {i = iid, q = count or 1, loc = {bag = BACKPACK, slot = slot}})
            end
        end
    end
    for _, v in ipairs(collectFromBagRange(FIRST_BAG, LAST_BAG)) do
        table.insert(mixed, v)
    end
    return mixed
end

local function CollectBank()
    local out = {}
    for _, v in ipairs(collectFromBagRange(BANK_CONTAINER, BANK_CONTAINER)) do
        table.insert(out, v)
    end
    for _, v in ipairs(collectFromBagRange(BANK_FIRST, BANK_LAST)) do
        table.insert(out, v)
    end
    for _, v in ipairs(collectFromBagRange(REAGENTBANK_CONTAINER, REAGENTBANK_CONTAINER)) do
        table.insert(out, v)
    end
    return out
end

local function CollectGuildBank()
    local items = {}
    if not IsInGuild() then
        return items
    end
    local tabs = GetNumGuildBankTabs and GetNumGuildBankTabs() or 0
    if tabs <= 0 then
        return items
    end
    for tab = 1, tabs do
        if QueryGuildBankTab then
            QueryGuildBankTab(tab)
        end
        local numSlots = 98
        for slot = 1, numSlots do
            local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
            if link then
                local _, count = GetGuildBankItemInfo(tab, slot)
                count = count or 1
                local iid = GBV_GetItemIDFromLink(link)
                if iid then
                    table.insert(items, {i = iid, q = count, loc = {tab = tab, slot = slot}})
                end
            end
        end
    end
    return items
end

local function moneyText(copper)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return string.format("%dg%ds%dc", g, s, c)
end

local function makeExportBlob(whereLabel, items)
    local copper = GetMoney and GetMoney() or 0
    return string.format(
        '{where:"%s",gold:{c:%d,t:"%s"},items:%s}',
        whereLabel,
        copper,
        moneyText(copper),
        makeExtended(items)
    )
end

local frame
local titleFS
local errorFS
local labelExport
local editURL1, btnURL1
local editURL2, btnURL2
local editExport, btnExport
local helpText

local function selectEditBox(eb)
    if not eb then
        return
    end
    eb:HighlightText()
    eb:SetFocus()
end

local function layoutRow(y, labelFS, editBox, button)
    labelFS:SetPoint("TOPLEFT", 16, y)
    button:SetPoint("TOPRIGHT", -16, y - 20)
    button:SetSize(80, 24)
    editBox:SetPoint("TOPLEFT", 16, y - 20)
    editBox:SetPoint("RIGHT", button, "LEFT", -8, 0)
    editBox:SetHeight(24)
end

local function ensureFrame()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "GBVExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(500, 260)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")

    if frame.SetBackdrop then
        frame:SetBackdrop(
            {
                bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 16,
                insets = {left = 4, right = 4, top = 4, bottom = 4}
            }
        )
        frame:SetBackdropColor(0, 0, 0, 0.85)
    end

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    titleFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleFS:SetPoint("TOPLEFT", 16, -12)
    titleFS:SetText(NAMEC .. DISPLAY_NAME .. SLASHC .. " // " .. TEXTC .. "Export Tool" .. ENDC)

    errorFS = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorFS:SetPoint("TOPLEFT", titleFS, "BOTTOMLEFT", 0, -2)
    errorFS:SetText("")
    errorFS:Hide()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    labelExport = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    editExport = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editExport:SetAutoFocus(false)
    editExport:SetMaxLetters(999999)
    editExport:SetMultiLine(false)
    btnExport = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnExport:SetText("Select")
    btnExport:SetScript(
        "OnClick",
        function()
            selectEditBox(editExport)
        end
    )
    layoutRow(-44, labelExport, editExport, btnExport)

    local label1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label1:SetText("Website")
    editURL1 = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editURL1:SetAutoFocus(false)
    editURL1:SetText("https://www.guildbankviewer.com")
    btnURL1 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnURL1:SetText("Select")
    btnURL1:SetScript(
        "OnClick",
        function()
            selectEditBox(editURL1)
        end
    )
    layoutRow(-96, label1, editURL1, btnURL1)

    local label2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label2:SetText("Discord")
    editURL2 = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editURL2:SetAutoFocus(false)
    editURL2:SetText("https://discord.gg/eh8hKq992Q")
    btnURL2 = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btnURL2:SetText("Select")
    btnURL2:SetScript(
        "OnClick",
        function()
            selectEditBox(editURL2)
        end
    )
    layoutRow(-148, label2, editURL2, btnURL2)

    helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helpText:SetPoint("BOTTOMLEFT", 16, 12)
    helpText:SetText("Click Select, then press Ctrl+C (Windows) or Apple+C (Mac) to copy.")

    for _, eb in next, {editURL1, editURL2, editExport} do
        eb:SetScript(
            "OnEditFocusGained",
            function(self)
                self:HighlightText()
            end
        )
        eb:SetScript(
            "OnEscapePressed",
            function(self)
                self:ClearFocus()
            end
        )
    end
end

local currentWhere = nil

local function setExportHeader(whereLabel)
    labelExport:SetText(TEXTC .. "Export " .. LINKC .. whereLabel .. ENDC)
    currentWhere = whereLabel
end

local function updateBankVaultError()
    if not frame or not errorFS then
        return
    end
    if currentWhere == "Bank Vault" and not GBV_BankOpen then
        errorFS:SetText(ERRORC .. "Please open your Bank Vault to continue." .. ENDC)
        errorFS:Show()
    else
        errorFS:SetText("")
        errorFS:Hide()
    end
end

local function ShowExportWindow(items, whereLabel)
    ensureFrame()
    frame:Show()
    setExportHeader(whereLabel)
    editExport:SetText(makeExportBlob(whereLabel, items))
    editExport:HighlightText(0, 0)
    editExport:SetCursorPosition(0)
    updateBankVaultError()
end

local _OrigSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
    local ltype, arg = link:match("^(%a+):(.+)$")
    if ltype == "gbv" then
        if arg == "bag" then
            ShowExportWindow(CollectBags(), "Backpack")
        elseif arg == "bank" then
            ShowExportWindow(CollectBank(), "Bank Vault")
        elseif arg == "guildbank" then
            ShowExportWindow(CollectGuildBank(), "Guild Bank Vault")
        end
        return
    end
    return _OrigSetItemRef(link, text, button, chatFrame)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("BANKFRAME_OPENED")
f:RegisterEvent("BANKFRAME_CLOSED")
f:RegisterEvent("GUILDBANKFRAME_OPENED")
f:RegisterEvent("GUILDBANKFRAME_CLOSED")

local function postBagLine()
    if GBV_BankOpen or GBV_GuildBankOpen then
        return
    end
    if isBusyContext() then
        return
    end

    local t = now()
    if t - lastShown.bag < COOLDOWN then
        return
    end
    lastShown.bag = t

    local msg =
        NAMEC ..
        DISPLAY_NAME ..
            SLASHC ..
                " // " ..
                    TEXTC ..
                        "Click to export the contents of your " ..
                            ENDC .. gbvLink("bag", "Backpack") .. TEXTC .. "." .. ENDC

    safeAddMessage(msg)
end

local function postBankLine()
    if isBusyContext() then
        return
    end

    local t = now()
    if t - lastShown.bank < COOLDOWN then
        return
    end
    lastShown.bank = t

    local msg =
        NAMEC ..
        DISPLAY_NAME ..
            SLASHC ..
                " // " ..
                    TEXTC ..
                        "Click to export the contents of your " ..
                            ENDC ..
                                gbvLink("bag", "Backpack") ..
                                    TEXTC .. ", or " .. ENDC .. gbvLink("bank", "Bank Vault") .. TEXTC .. "." .. ENDC

    safeAddMessage(msg)
end

local function postGuildLine()
    if isBusyContext() then
        return
    end

    local t = now()
    if t - lastShown.guild < COOLDOWN then
        return
    end
    lastShown.guild = t

    local msg =
        NAMEC ..
        DISPLAY_NAME ..
            SLASHC ..
                " // " ..
                    TEXTC ..
                        "Click to export the contents of your " ..
                            ENDC ..
                                gbvLink("bag", "Backpack") ..
                                    TEXTC ..
                                        ", or " ..
                                            ENDC .. gbvLink("guildbank", "Guild Bank Vault") .. TEXTC .. "." .. ENDC

    safeAddMessage(msg)
end

local function hookBagOpenSignals()
    if ToggleAllBags and not GBV._hookedToggleAllBags then
        GBV._hookedToggleAllBags = true
        hooksecurefunc(
            "ToggleAllBags",
            function()
                postBagLine()
            end
        )
    end
    if OpenAllBags and not GBV._hookedOpenAllBags then
        GBV._hookedOpenAllBags = true
        hooksecurefunc(
            "OpenAllBags",
            function()
                postBagLine()
            end
        )
    end
    if ToggleBackpack and not GBV._hookedToggleBackpack then
        GBV._hookedToggleBackpack = true
        hooksecurefunc(
            "ToggleBackpack",
            function()
                postBagLine()
            end
        )
    end
    local combined = _G.ContainerFrameCombinedBags
    if combined and not combined._gbvHooked then
        combined._gbvHooked = true
        combined:HookScript(
            "OnShow",
            function()
                postBagLine()
            end
        )
    end
    for i = 1, 14 do
        local cf = _G["ContainerFrame" .. i]
        if cf and not cf._gbvHooked then
            cf._gbvHooked = true
            cf:HookScript(
                "OnShow",
                function()
                    postBagLine()
                end
            )
        end
    end
end

local function hookBankGuildFrames()
    local bf = _G.BankFrame
    if bf and not bf._gbvHooked then
        bf._gbvHooked = true
        bf:HookScript(
            "OnShow",
            function()
                GBV_BankOpen = true
                postBankLine()
                updateBankVaultError()
            end
        )
        bf:HookScript(
            "OnHide",
            function()
                GBV_BankOpen = false
                updateBankVaultError()
            end
        )
    end
    local gbf = _G.GuildBankFrame
    if gbf and not gbf._gbvHooked then
        gbf._gbvHooked = true
        gbf:HookScript(
            "OnShow",
            function()
                GBV_GuildBankOpen = true
                postGuildLine()
            end
        )
        gbf:HookScript(
            "OnHide",
            function()
                GBV_GuildBankOpen = false
            end
        )
    end
end

local function delayedHookSweep()
    hookBagOpenSignals()
    hookBankGuildFrames()
    for n = 1, 4 do
        C_Timer.After(
            0.5 * n,
            function()
                hookBagOpenSignals()
                hookBankGuildFrames()
            end
        )
    end
end

f:SetScript(
    "OnEvent",
    function(_, event)
        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            delayedHookSweep()
        elseif event == "BANKFRAME_OPENED" then
            GBV_BankOpen = true
            postBankLine()
            updateBankVaultError()
        elseif event == "BANKFRAME_CLOSED" then
            GBV_BankOpen = false
            updateBankVaultError()
        elseif event == "GUILDBANKFRAME_OPENED" then
            GBV_GuildBankOpen = true
            postGuildLine()
        elseif event == "GUILDBANKFRAME_CLOSED" then
            GBV_GuildBankOpen = false
        end
    end
)

-- *****************************************************************************
-- * Loot Goblin 2000
-- * A NeatUI-based panel for finding items in surrounding containers.
-- *
-- * Design:
-- *   The window holds one or more "SearchBlock" entries.
-- *   Each block starts in "search" mode (text field + live top-5 results).
-- *   The first result is always "Any items with '<query>'" (partial-match mode).
-- *   The block height grows/shrinks dynamically with the number of results.
-- *   Once an item is selected the block switches to "finding" mode:
-- *     - shows the item name + ID (or partial-match query)
-- *     - highlights green when the item is found in a nearby container
-- *     - shows a remove button to delete this block
-- *     - each found entry shows "Container (Item Name xN)" with
-- *       grab-one / grab-all / locate buttons
-- *       (grab-all is hidden when count == 1; grab-one takes its place)
-- *   The "Add another item" button appears only when the last block is in
-- *   finding mode (prevents creating multiple empty search blocks).
-- *   The window resizes dynamically whenever blocks change height.
-- *   Arrow keys navigate search results; Enter selects the highlighted result
-- *   or (when in finding mode) adds a new search block.
-- *   Window and contents are rendered at 0.7 alpha for a slight transparency.
-- *****************************************************************************

require "LootGoblin2000_SearchBlock"

-- LootGoblin2000 table and LootGoblin2000.UI are created by LootGoblin2000_Helpers / LootGoblin2000_Widgets.
local UI = LootGoblin2000.UI

-- ---------------------------------------------------------------------------
-- LootGoblin2000Window
-- ---------------------------------------------------------------------------

local LootGoblin2000Window = ISPanel:derive("LootGoblin2000Window")

function LootGoblin2000Window:new(x, y)
    local initH = UI.HEADER_H + UI.searchBlockH(0) + UI.PAD
    local o = ISPanel:new(x, y, UI.PANEL_WIDTH, initH)
    setmetatable(o, self)
    self.__index = self
    o.moveWithMouse = false
    o.moving        = false
    o.padding       = UI.PAD
    o.headerHeight  = UI.HEADER_H
    o.blocks        = {}
    return o
end

function LootGoblin2000Window:initialise()
    ISPanel.initialise(self)
end

function LootGoblin2000Window:createChildren()
    -- Close button (NeatUI icon in the header)
    local btnSize   = math.floor(getTextManager():getFontHeight(UIFont.Medium))
    local btnX      = self.width - btnSize - UI.PAD
    local btnY      = math.floor((UI.HEADER_H - btnSize) / 2)
    local closeIcon = getTexture("media/ui/NeatUI/ICON/Icon_False.png")

    self.closeButton = NI_SquareButton:new(btnX, btnY, btnSize, closeIcon, self, self.onCloseClick)
    self.closeButton:initialise()
    self.closeButton:setActive(true)
    self.closeButton:setActiveColor(0.8, 0.2, 0.2)
    self.closeButton:setVisible(not UI.COMPACT)
    self:addChild(self.closeButton)

    -- "Templates" button – centered in the header, always visible
    self.templateButton = UI.IconButton:new(
        math.floor((UI.PANEL_WIDTH - UI.ICON_SIZE) / 2),
        math.floor((UI.HEADER_H - UI.ICON_SIZE) / 2),
        UI.ICON_SIZE,
        getTexture("media/textures/template-menu.png"),
        self,
        function() self:openTemplateMenu() end
    )
    self.templateButton:initialise()
    self.templateButton:setVisible(true)
    self:addChild(self.templateButton)

    -- "Add item" button – centered, hidden until last block is in finding mode
    self.addButton = UI.IconButton:new(
        math.floor((UI.PANEL_WIDTH - UI.ICON_SIZE) / 2),
        0,   -- Y set by reflow
        UI.ICON_SIZE,
        getTexture("media/textures/item-add.png"),
        self,
        function() self:addBlock() end
    )
    self.addButton:initialise()
    self.addButton:setVisible(false)
    self:addChild(self.addButton)

    self:addBlock()
end

-- ---------------------------------------------------------------------------
-- Block management
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:addBlock()
    local block = UI.SearchBlock:new(0, 0, UI.PANEL_WIDTH, self)
    block:initialise()
    self:addChild(block)
    self.blocks[#self.blocks + 1] = block
    self:reflow()
    if block.searchEntry then
        block.searchEntry:focus()
    end
end

function LootGoblin2000Window:removeBlock(block)
    self:removeChild(block)
    for i, b in ipairs(self.blocks) do
        if b == block then
            table.remove(self.blocks, i)
            break
        end
    end
    if #self.blocks == 0 then
        self:addBlock()
        return
    end
    self:reflow()
end

-- ---------------------------------------------------------------------------
-- Template menu
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:openTemplateMenu()
    local context = ISContextMenu.get(0,
        self:getAbsoluteX() + math.floor(UI.PANEL_WIDTH / 2),
        self:getAbsoluteY() + UI.HEADER_H)

    -- ── Load template ──────────────────────────────────────────────────────
    local loadOption = context:addOption(getText("UI_LootGoblin2000_LoadTemplate"), self, nil)
    local names = LootGoblin2000.getTemplateNames()
    if #names == 0 then
        local subLoad = ISContextMenu:getNew(context)
        context:addSubMenu(loadOption, subLoad)
        subLoad:addOption(getText("UI_LootGoblin2000_NoTemplates"), self, nil)
    else
        local subLoad = ISContextMenu:getNew(context)
        context:addSubMenu(loadOption, subLoad)
        for _, name in ipairs(names) do
            subLoad:addOption(name, self, function(win, tplName)
                win:loadTemplate(tplName)
            end, name)
        end
    end

    -- ── Save template ──────────────────────────────────────────────────────
    context:addOption(getText("UI_LootGoblin2000_SaveTemplate"), self, function(win)
        win:openSaveTemplateDialog()
    end)

    -- ── Remove template ────────────────────────────────────────────────────
    local removeOption = context:addOption(getText("UI_LootGoblin2000_RemoveTemplate"), self, nil)
    if #names == 0 then
        local subRemove = ISContextMenu:getNew(context)
        context:addSubMenu(removeOption, subRemove)
        subRemove:addOption(getText("UI_LootGoblin2000_NoTemplates"), self, nil)
    else
        local subRemove = ISContextMenu:getNew(context)
        context:addSubMenu(removeOption, subRemove)
        for _, name in ipairs(names) do
            subRemove:addOption(name, self, function(win, tplName)
                win:openRemoveTemplateDialog(tplName)
            end, name)
        end
    end

    context:render()
end

-- Load a template: clear all blocks and recreate them from saved item data.
function LootGoblin2000Window:loadTemplate(name)
    local items = LootGoblin2000.getTemplate(name)
    if not items or #items == 0 then return end

    -- Remove all existing blocks
    for i = #self.blocks, 1, -1 do
        self:removeChild(self.blocks[i])
    end
    self.blocks = {}

    -- Recreate blocks from template data
    for _, itemData in ipairs(items) do
        local block = UI.SearchBlock:new(0, 0, UI.PANEL_WIDTH, self)
        block:initialise()
        self:addChild(block)
        self.blocks[#self.blocks + 1] = block
        -- Synthesise the itemData table the same way onItemSelected expects it
        local data
        if itemData.isPartial then
            data = { isPartial = true, query = itemData.query }
        else
            data = { displayName = itemData.displayName, fullType = itemData.fullType }
        end
        block:onItemSelected(data, false)
    end

    self:reflow()
    print("[LootGoblin2000] loaded template '" .. name .. "'.")
end

-- ---------------------------------------------------------------------------
-- Save-template dialog (ISTextBox modal)
-- ---------------------------------------------------------------------------

-- Callback: onclick(target=win, button, param1=nil)
-- Text is retrieved from button.parent.entry:getText()
local function onSaveTemplateClick(win, button)
    if button.internal ~= "OK" then return end
    local name = button.parent.entry:getText()
    if not name or name == "" then return end
    LootGoblin2000.saveTemplate(name, win.blocks)
end

function LootGoblin2000Window:openSaveTemplateDialog()
    -- Pass x=0, y=0 so ISTextBox auto-positions at mouse cursor
    local modal = ISTextBox:new(
        0, 0,
        320, 130,
        getText("UI_LootGoblin2000_SaveTemplate_Prompt"),
        "",
        self,
        onSaveTemplateClick
    )
    modal:initialise()
    modal:addToUIManager()
    modal.entry:focus()
end

-- ---------------------------------------------------------------------------
-- Remove-template confirmation dialog
-- ---------------------------------------------------------------------------

-- Callback: onclick(target=win, button, param1=name)
local function onRemoveTemplateClick(win, button, name)
    if button.internal == "YES" then
        LootGoblin2000.removeTemplate(name)
    end
end

function LootGoblin2000Window:openRemoveTemplateDialog(name)
    -- Pass x=0, y=0 so ISModalDialog auto-positions at mouse cursor
    local modal = ISModalDialog:new(
        0, 0,
        320, 110,
        getText("UI_LootGoblin2000_RemoveTemplate_Confirm", name),
        true,
        self,
        onRemoveTemplateClick,
        nil,   -- player
        name   -- param1
    )
    modal:initialise()
    modal:addToUIManager()
end

-- Reflow: stack all blocks below the header, place the add button, resize the window.
-- The add button is shown only when the LAST block is in finding mode.
function LootGoblin2000Window:reflow()
    local y = UI.HEADER_H
    for _, block in ipairs(self.blocks) do
        block:setX(0)
        block:setY(y)
        block:setWidth(UI.PANEL_WIDTH)
        y = y + block.height
    end

    local lastBlock = self.blocks[#self.blocks]
    local showAdd   = lastBlock and lastBlock.state == "finding"

    if showAdd then
        self.addButton:setY(y + UI.PAD)
        self.addButton:setVisible(true)
        y = y + UI.ADD_BTN_ROW_H
    else
        self.addButton:setVisible(false)
        y = y + UI.PAD
    end

    self:setHeight(y)
end

-- ---------------------------------------------------------------------------
-- Update – tick all blocks (debounce + scan)
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:update()
    ISPanel.update(self)
    for _, block in ipairs(self.blocks) do
        block:update()
    end
end

-- ---------------------------------------------------------------------------
-- Dragging via header
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:onMouseDown(x, y)
    if y < self.headerHeight then
        self.moving = true
        self:setCapture(true)
        return true
    end
    return false
end

function LootGoblin2000Window:onMouseMove(dx, dy)
    if self.moving then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        return true
    end
    return false
end

function LootGoblin2000Window:onMouseMoveOutside(dx, dy)
    if self.moving then
        self:setX(self.x + dx)
        self:setY(self.y + dy)
        return true
    end
    return false
end

function LootGoblin2000Window:onMouseUp(x, y)
    if self.moving then
        self.moving = false
        self:setCapture(false)
        return true
    end
    return false
end

function LootGoblin2000Window:onMouseUpOutside(x, y)
    if self.moving then
        self.moving = false
        self:setCapture(false)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Close
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:onCloseClick()
    print("[LootGoblin2000] closing window")
    LootGoblin2000._lastX = self.x
    LootGoblin2000._lastY = self.y
    self:setVisible(false)
    self:removeFromUIManager()
    LootGoblin2000._instance = nil
end

-- ---------------------------------------------------------------------------
-- Grab-all helpers (used by the grab-all hotkey)
-- ---------------------------------------------------------------------------

-- Returns true when at least one finding block has external found items.
function LootGoblin2000Window:hasExternalFound()
    for _, block in ipairs(self.blocks) do
        if block.state == "finding" and block.hasExternal then
            return true
        end
    end
    return false
end

-- Grab all found items from all external containers across all finding blocks.
function LootGoblin2000Window:grabAllFound()
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local playerNum = pl:getPlayerNum()
    for _, block in ipairs(self.blocks) do
        if block.state == "finding" then
            for _, entry in ipairs(block.foundIn) do
                if not entry.isPlayer then
                    LootGoblin2000.grabAllItems(entry, playerNum)
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Key events
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:onKeyRelease(key)
    -- Navigation keys (arrows, enter) are handled exclusively through the
    -- text entry's own callbacks (onPressUp / onPressDown / onCommandEntered)
    -- and only when the entry is focused.
    -- Escape is intentionally not handled here so the game's default
    -- behaviour (opening the pause menu) is preserved.

    -- Grab-all hotkey (always active)
    local grabAllKey = LootGoblin2000.options
                       and LootGoblin2000.options.GrabAllKey
                       and LootGoblin2000.options.GrabAllKey:getValue()
    if grabAllKey and key == grabAllKey and self:hasExternalFound() then
        self:grabAllFound()
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function LootGoblin2000Window:prerender()
    local a = UI.UI_ALPHA

    local mainBG = NinePatchTexture.getSharedTexture("media/ui/NeatUI/DefaultPanel/MainPanelBG_FlatTop.png")
    if mainBG then
        mainBG:render(self:getAbsoluteX(), self:getAbsoluteY() + UI.HEADER_H,
            self.width, self.height - UI.HEADER_H, 0.15, 0.15, 0.15, a)
    else
        self:drawRect(0, UI.HEADER_H, self.width, self.height - UI.HEADER_H, a, 0.12, 0.12, 0.12)
    end

    local titleBG = NinePatchTexture.getSharedTexture("media/ui/NeatUI/DefaultPanel/MainTitle_BG.png")
    if titleBG then
        titleBG:render(self:getAbsoluteX(), self:getAbsoluteY(), self.width, UI.HEADER_H, 0.08, 0.08, 0.08, a)
    else
        self:drawRect(0, 0, self.width, UI.HEADER_H, a, 0.08, 0.08, 0.08)
    end

    self:drawRect(0, UI.HEADER_H - 1, self.width, 1, a, 0, 0, 0)
end

function LootGoblin2000Window:render()
    local title = UI.COMPACT
        and getText("UI_LootGoblin2000_TitleShort")
        or  getText("UI_LootGoblin2000_Title")
    local textY = math.floor((UI.HEADER_H - getTextManager():getFontHeight(UIFont.Medium)) / 2)
    self:drawText(title, UI.PAD, textY, 1, 1, 1, UI.UI_ALPHA, UIFont.Medium)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

LootGoblin2000.options   = nil
LootGoblin2000._instance  = nil
LootGoblin2000._lastX     = nil
LootGoblin2000._lastY     = nil
LootGoblin2000._tickCount = 0

-- Global tick – scan containers every 5 ticks for all finding blocks
Events.OnTick.Add(function()
    local inst = LootGoblin2000._instance
    if not inst or not inst:isVisible() then return end

    LootGoblin2000._tickCount = LootGoblin2000._tickCount + 1
    if LootGoblin2000._tickCount < 5 then return end
    LootGoblin2000._tickCount = 0

    for _, block in ipairs(inst.blocks) do
        if block.state == "finding" then
            block:scanContainers()
        end
    end
end)

function LootGoblin2000.open()
    print("[LootGoblin2000] open() called")
    LootGoblin2000.buildItemCache()
    LootGoblin2000.applyInterfaceScale()

    if LootGoblin2000._instance then
        print("[LootGoblin2000] re-showing existing instance")
        LootGoblin2000._instance:setVisible(true)
        LootGoblin2000._instance:bringToTop()
        local lastBlock = LootGoblin2000._instance.blocks[#LootGoblin2000._instance.blocks]
        if lastBlock and lastBlock.state == "search" and lastBlock.searchEntry then
            lastBlock.searchEntry:focus()
        end
        return
    end

    local x, y
    if LootGoblin2000._lastX and LootGoblin2000._lastY then
        x = LootGoblin2000._lastX
        y = LootGoblin2000._lastY
    else
        local sw   = getCore():getScreenWidth()
        local sh   = getCore():getScreenHeight()
        local initH = UI.HEADER_H + UI.searchBlockH(0) + UI.PAD
        x = math.floor((sw - UI.PANEL_WIDTH) / 2)
        y = math.floor((sh - initH) / 2)
    end

    print("[LootGoblin2000] creating window at " .. x .. "," .. y)

    local win = LootGoblin2000Window:new(x, y)
    win:initialise()
    win:instantiate()
    win:setVisible(true)
    win:addToUIManager()
    win:setWantKeyEvents(true)
    LootGoblin2000._instance = win

    print("[LootGoblin2000] window created and added to UI manager")
end

function LootGoblin2000.close()
    if LootGoblin2000._instance then
        LootGoblin2000._instance:onCloseClick()
    end
end

function LootGoblin2000.toggle()
    print("[LootGoblin2000] toggle() called, instance=" .. tostring(LootGoblin2000._instance))
    if LootGoblin2000._instance and LootGoblin2000._instance:isVisible() then
        LootGoblin2000.close()
    else
        LootGoblin2000.open()
    end
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

require "PZAPI/ModOptions"

LootGoblin2000.options = LootGoblin2000.options or {}

local _modOptions = PZAPI.ModOptions:create("LootGoblin2000", "Loot Goblin 2000")
LootGoblin2000.options.IgnorePlayerContainers = _modOptions:addTickBox("IgnorePlayerContainers", getText("UI_LootGoblin2000_Options_IgnorePlayerContainers_Name"), false, getText("UI_LootGoblin2000_Options_IgnorePlayerContainers_Tooltip"))
LootGoblin2000.options.AlwaysRootInventory = _modOptions:addTickBox("AlwaysRootInventory", getText("UI_LootGoblin2000_Options_AlwaysRootInventory_Name"), false, getText("UI_LootGoblin2000_Options_AlwaysRootInventory_Tooltip"))
LootGoblin2000.options.CompactInterface = _modOptions:addTickBox("CompactInterface", getText("UI_LootGoblin2000_Options_CompactInterface_Name"), false, getText("UI_LootGoblin2000_Options_CompactInterface_Tooltip"))
LootGoblin2000.options.Key               = _modOptions:addKeyBind("Key",               getText("UI_LootGoblin2000_Options_Key_Name"),               Keyboard.KEY_SEMICOLON,  getText("UI_LootGoblin2000_Options_Key_Tooltip"))
LootGoblin2000.options.GrabAllKey        = _modOptions:addKeyBind("GrabAllKey",        getText("UI_LootGoblin2000_Options_GrabAllKey_Name"),        Keyboard.KEY_APOSTROPHE, getText("UI_LootGoblin2000_Options_GrabAllKey_Tooltip"))

-- Applies the currently saved CompactInterface option to UI.COMPACT and recomputes
-- all layout constants.  Safe to call before a window exists.
function LootGoblin2000.applyInterfaceScale()
    local compact = LootGoblin2000.options.CompactInterface
                    and LootGoblin2000.options.CompactInterface:getValue()
                    or false
    LootGoblin2000.UI.COMPACT = compact
    LootGoblin2000.UI.applyScale()
    print("[LootGoblin2000] compact interface: " .. tostring(compact))
end

PZAPI.ModOptions:load()

-- Apply scale once after options are loaded (picks up any saved value).
-- Scale is also re-applied every time the window is opened (see LootGoblin2000.open).
LootGoblin2000.applyInterfaceScale()

-- ---------------------------------------------------------------------------
-- Hotkey
-- ---------------------------------------------------------------------------

Events.OnKeyPressed.Add(function(key)
    if key == LootGoblin2000.options.Key:getValue() then
        local pl = getSpecificPlayer(0)
        if not pl then return end
        LootGoblin2000.toggle()
    end
end)

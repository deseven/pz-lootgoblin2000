-- *****************************************************************************
-- * Loot Goblin 2000 – Widgets
-- * Reusable UI primitives: IconButton, ResultRow, FoundRow.
-- * Loaded before LootGoblin2000_SearchBlock.lua and LootGoblin2000.lua.
-- *****************************************************************************

require "ISUI/ISPanel"
require "LootGoblin2000_Helpers"

-- LootGoblin2000 table is created by LootGoblin2000_Helpers.lua

-- ---------------------------------------------------------------------------
-- Shared layout constants (also used by SearchBlock and LootGoblin2000Window)
-- ---------------------------------------------------------------------------

local FONT_HGT_SMALL  = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)

LootGoblin2000.UI = LootGoblin2000.UI or {}
local UI = LootGoblin2000.UI

-- UI.COMPACT is set by LootGoblin2000.applyInterfaceScale() (called from LootGoblin2000.lua).
-- Default to false so the widgets file is self-contained at load time.
UI.COMPACT = UI.COMPACT or false

-- Recompute all layout constants from the current UI.COMPACT flag.
-- Called once at startup and again whenever the player changes the compact option.
function UI.applyScale()
    local s = UI.COMPACT and 0.85 or 1.0

    -- Panel width is 350 in compact mode, 380 in normal mode.
    UI.PANEL_WIDTH    = UI.COMPACT and 350 or 380
    UI.HEADER_H       = math.floor(FONT_HGT_MEDIUM * 1.28 * s)
    UI.PAD            = math.floor(FONT_HGT_SMALL * 0.5 * s)
    UI.ICON_SIZE      = math.floor(24 * s)
    UI.MAX_RESULTS    = 5
    UI.UI_ALPHA       = 0.7

    -- Search block layout
    UI.SEARCH_BOX_H   = math.floor(FONT_HGT_SMALL * 1.08 * s)
    -- In compact mode rows show a single line (name + [id]), so halve the height.
    UI.ROW_HEIGHT     = UI.COMPACT and math.floor(FONT_HGT_SMALL * 1.4 * s)
                                    or  math.floor(FONT_HGT_SMALL * 2.6 * s)
    UI.ROW_PADDING    = math.floor(FONT_HGT_SMALL * 0.2 * s)

    -- Finding block layout.
    -- In compact mode the header is exactly the icon band (PAD + ICON + PAD) – one line of text.
    -- In normal mode the header must fit two lines (name + ID/subtitle) plus padding.
    UI.FINDING_ITEM_NAME_H      = math.floor(FONT_HGT_MEDIUM * 1.1 * s)
    UI.FINDING_ITEM_ID_H        = UI.COMPACT and 0 or math.floor(FONT_HGT_SMALL * 1.1 * s)
    if UI.COMPACT then
        UI.FINDING_HEADER_H = UI.PAD + UI.ICON_SIZE + UI.PAD
    else
        UI.FINDING_HEADER_H = UI.PAD + UI.FINDING_ITEM_NAME_H + UI.FINDING_ITEM_ID_H + UI.PAD
    end
    UI.FINDING_HEADER_PAD_EXTRA = 0   -- kept for compatibility; no longer adds extra space
    UI.FOUND_ROW_H              = UI.ICON_SIZE + UI.ROW_PADDING * 2
    UI.MAX_FOUND_LINES          = 20
    UI.ADD_BTN_ROW_H            = UI.ICON_SIZE + UI.PAD * 2
end

-- Apply defaults immediately so constants are valid before LootGoblin2000.lua runs.
UI.applyScale()

-- Height of a search block with N result rows (0 = just the input)
function UI.searchBlockH(numRows)
    local n = numRows or 0
    local h = UI.PAD + UI.SEARCH_BOX_H + UI.PAD
    if n > 0 then
        h = h + n * (UI.ROW_HEIGHT + UI.ROW_PADDING) + UI.PAD
    end
    return h
end

-- Height of a finding block.
-- When nothing is found yet (numFound == 0) we show only the item name + ID.
-- When items are found we show name + ID + separator + found-container rows.
function UI.findingBlockH(numFound)
    local n = numFound or 0
    -- Header is always the icon band height (PAD + ICON_SIZE + PAD).
    local h = UI.FINDING_HEADER_H
    if n > 0 then
        -- separator only in normal mode; equal padding above and below the rows
        local sepH = UI.COMPACT and 0 or (1 + UI.PAD)
        h = h + sepH
             + UI.FOUND_ROW_H * n
             + UI.PAD
    end
    return h
end

-- ---------------------------------------------------------------------------
-- Shared text-truncation helper
-- Truncates `text` so it fits within `maxW` pixels (UIFont.Small).
-- Returns the (possibly truncated) string.
-- ---------------------------------------------------------------------------

function UI.truncate(text, maxW)
    local w = getTextManager():MeasureStringX(UIFont.Small, text)
    if w <= maxW then return text end
    repeat
        text = text:sub(1, -2)
        w    = getTextManager():MeasureStringX(UIFont.Small, text .. "...")
    until w <= maxW or #text <= 1
    return text .. "..."
end

-- Same but for UIFont.Medium
function UI.truncateMedium(text, maxW)
    local w = getTextManager():MeasureStringX(UIFont.Medium, text)
    if w <= maxW then return text end
    repeat
        text = text:sub(1, -2)
        w    = getTextManager():MeasureStringX(UIFont.Medium, text .. "...")
    until w <= maxW or #text <= 1
    return text .. "..."
end

-- ---------------------------------------------------------------------------
-- NinePatch background helper – draws the standard inner-panel background
-- or falls back to a plain rect.
-- ---------------------------------------------------------------------------

function UI.drawSlotBG(element, x, y, w, h, r, g, b, a)
    local slotBG = NinePatchTexture.getSharedTexture("media/ui/NeatUI/DefaultPanel/InnerPanel_BG.png")
    if slotBG then
        slotBG:render(element:getAbsoluteX() + x, element:getAbsoluteY() + y, w, h, r, g, b, a)
    else
        element:drawRect(x, y, w, h, a, r, g, b)
    end
end

-- ---------------------------------------------------------------------------
-- IconButton
-- Plain icon button – draws a texture without any NeatUI square background.
-- ---------------------------------------------------------------------------

local IconButton = ISUIElement:derive("IconButton")

function IconButton:new(x, y, size, texture, parent, callback)
    local o = ISUIElement:new(x, y, size, size)
    setmetatable(o, self)
    self.__index = self
    o._texture  = texture
    o._callback = callback
    o._parent   = parent
    o._hovered  = false
    return o
end

function IconButton:initialise()
    ISUIElement.initialise(self)
end

function IconButton:onMouseMove()        self._hovered = true;  return true end
function IconButton:onMouseMoveOutside() self._hovered = false; return true end
function IconButton:onMouseDown(x, y)   return true end

function IconButton:onMouseUp(x, y)
    if self._hovered and self._callback then
        self._callback()
    end
    return true
end

function IconButton:render()
    if not self._texture then return end
    local alpha = self._hovered and UI.UI_ALPHA or UI.UI_ALPHA * 0.75
    self:drawTextureScaled(self._texture, 0, 0, self.width, self.height, alpha, 1, 1, 1)
end

-- Export so other files can use it
UI.IconButton = IconButton

-- ---------------------------------------------------------------------------
-- ResultRow
-- One search-result entry: display name on line 1, item ID on line 2.
-- ---------------------------------------------------------------------------

local ResultRow = ISUIElement:derive("ResultRow")

function ResultRow:new(x, y, w, h)
    local o = ISUIElement:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.itemData    = nil
    o.onSelect    = nil
    o.selectBtn   = nil
    o.highlighted = false
    return o
end

function ResultRow:initialise()
    ISUIElement.initialise(self)

    local btnX = self.width - UI.ICON_SIZE - UI.PAD
    local btnY = math.floor((self.height - UI.ICON_SIZE) / 2)
    local icon = getTexture("media/textures/item-select.png")

    self.selectBtn = IconButton:new(btnX, btnY, UI.ICON_SIZE, icon, self, function()
        if self.itemData and self.onSelect then
            self.onSelect(self.itemData)
        end
    end)
    self.selectBtn:initialise()
    self:addChild(self.selectBtn)
end

function ResultRow:setItemData(data)
    self.itemData = data
    if self.selectBtn then
        self.selectBtn:setVisible(data ~= nil)
    end
end

function ResultRow:onMouseMove()        return true end
function ResultRow:onMouseMoveOutside() return true end
function ResultRow:onMouseDown(x, y)   return true end

function ResultRow:onMouseUp()
    if self.itemData and self.onSelect then
        self.onSelect(self.itemData)
    end
    return true
end

function ResultRow:prerender()
    if not self.itemData then return end
    local r, g, b = 0.18, 0.18, 0.18
    local hovered = self:isMouseOver() or self.highlighted
    if hovered then r, g, b = 0.30, 0.30, 0.30 end
    if self.itemData.isPartial then
        r = hovered and 0.28 or 0.20
        g = hovered and 0.32 or 0.24
        b = hovered and 0.28 or 0.20
    elseif self.itemData.isTemplate then
        r = hovered and 0.28 or 0.20
        g = hovered and 0.28 or 0.20
        b = hovered and 0.36 or 0.28
    end
    if self.highlighted and not self:isMouseOver() then
        r, g, b = r + 0.08, g + 0.08, b + 0.08
    end
    UI.drawSlotBG(self, 0, 0, self.width, self.height, r, g, b, UI.UI_ALPHA)
end

function ResultRow:render()
    if not self.itemData then return end

    local maxTextW = self.width - UI.PAD * 3 - UI.ICON_SIZE
    local a        = UI.UI_ALPHA

    if self.itemData.isPartial then
        local label = UI.truncate(getText("UI_LootGoblin2000_AnyItems", self.itemData.query), maxTextW)
        local textY = math.floor((self.height - FONT_HGT_SMALL) / 2)
        self:drawText(label, UI.PAD * 2, textY, 0.75, 1.0, 0.75, a, UIFont.Small)
        return
    end

    if self.itemData.isTemplate then
        local label = UI.truncate(getText("UI_LootGoblin2000_LoadTemplateResult", self.itemData.name), maxTextW)
        local textY = math.floor((self.height - FONT_HGT_SMALL) / 2)
        self:drawText(label, UI.PAD * 2, textY, 0.75, 0.85, 1.0, a, UIFont.Small)
        return
    end

    local textY = math.floor((self.height - FONT_HGT_SMALL) / 2)

    if UI.COMPACT then
        -- Single line: "Name [fullType]"
        local combined = self.itemData.displayName .. " [" .. self.itemData.fullType .. "]"
        local label = UI.truncate(combined, maxTextW)
        self:drawText(label, UI.PAD * 2, textY, 1, 1, 1, a, UIFont.Small)
    else
        -- Two lines: name on top, dimmed ID below
        local lineSpacing = math.floor(FONT_HGT_SMALL * 0.15)
        local totalH      = FONT_HGT_SMALL * 2 + lineSpacing
        local startY      = math.floor((self.height - totalH) / 2)

        local name = UI.truncate(self.itemData.displayName, maxTextW)
        self:drawText(name, UI.PAD * 2, startY, 1, 1, 1, a, UIFont.Small)

        local idStr = UI.truncate(self.itemData.fullType, maxTextW)
        self:drawText(idStr, UI.PAD * 2, startY + FONT_HGT_SMALL + lineSpacing, 0.5, 0.5, 0.5, a * 0.85, UIFont.Small)
    end
end

UI.ResultRow = ResultRow

-- ---------------------------------------------------------------------------
-- FoundRow
-- One found-container entry with grab-one / grab-all / locate buttons.
-- ---------------------------------------------------------------------------

local FoundRow = ISUIElement:derive("FoundRow")

function FoundRow:new(x, y, w, h)
    local o = ISUIElement:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.entryData  = nil
    o.playerNum  = 0
    o.grabOneBtn = nil
    o.grabAllBtn = nil
    o.locateBtn  = nil
    return o
end

function FoundRow:initialise()
    ISUIElement.initialise(self)

    local btnY     = math.floor((self.height - UI.ICON_SIZE) / 2)
    local locateX  = self.width - UI.ICON_SIZE - UI.PAD
    local grabOneX = locateX - UI.ICON_SIZE - UI.PAD
    local grabAllX = grabOneX - UI.ICON_SIZE - UI.PAD

    self.grabAllBtn = IconButton:new(grabAllX, btnY, UI.ICON_SIZE,
        getTexture("media/textures/item-grab-all.png"), self, function()
            if self.entryData then LootGoblin2000.grabAllItems(self.entryData, self.playerNum) end
        end)
    self.grabAllBtn:initialise()
    self:addChild(self.grabAllBtn)

    self.grabOneBtn = IconButton:new(grabOneX, btnY, UI.ICON_SIZE,
        getTexture("media/textures/item-grab.png"), self, function()
            if self.entryData then LootGoblin2000.grabOneItem(self.entryData, self.playerNum) end
        end)
    self.grabOneBtn:initialise()
    self:addChild(self.grabOneBtn)

    self.locateBtn = IconButton:new(locateX, btnY, UI.ICON_SIZE,
        getTexture("media/textures/item-locate.png"), self, function()
            if self.entryData then LootGoblin2000.locateItem(self.entryData, self.playerNum) end
        end)
    self.locateBtn:initialise()
    self:addChild(self.locateBtn)
end

-- showButtons = false hides all action buttons (used for player-inventory rows)
function FoundRow:setData(entryData, playerNum, showButtons)
    self.entryData = entryData
    self.playerNum = playerNum
    local btnsOn   = entryData ~= nil and (showButtons ~= false)

    if self.locateBtn  then self.locateBtn:setVisible(btnsOn)  end
    if self.grabOneBtn then self.grabOneBtn:setVisible(btnsOn) end

    if self.grabAllBtn then
        local showGrabAll = btnsOn and entryData ~= nil and (entryData.count or 0) > 1
        self.grabAllBtn:setVisible(showGrabAll)
    end
end

function FoundRow:onMouseMove()        return true end
function FoundRow:onMouseMoveOutside() return true end
function FoundRow:onMouseUp()          return true end
function FoundRow:onMouseDown(x, y)    return true end

function FoundRow:prerender()
    if not self.entryData then return end
    local r, g, b = 0.18, 0.18, 0.18
    if self:isMouseOver() then r, g, b = 0.28, 0.28, 0.28 end
    UI.drawSlotBG(self, 0, 0, self.width, self.height, r, g, b, UI.UI_ALPHA)
end

function FoundRow:render()
    if not self.entryData then return end
    local textY    = math.floor((self.height - FONT_HGT_SMALL) / 2)
    local btnAreaW = self.entryData.isPlayer and 0 or ((UI.ICON_SIZE + UI.PAD) * 3 + UI.PAD)
    local maxTextW = self.width - UI.PAD * 2 - btnAreaW

    local itemLabel = self.entryData.itemName or ""
    local label
    if itemLabel ~= "" then
        label = self.entryData.containerName .. " | " .. tostring(self.entryData.count) .. "x [" .. itemLabel .. "]"
    else
        label = self.entryData.containerName .. " | x" .. tostring(self.entryData.count)
    end
    label = UI.truncate(label, maxTextW)

    local r = self.entryData.isPlayer and 0.7  or 0.85
    local g = self.entryData.isPlayer and 0.85 or 1.0
    local b = self.entryData.isPlayer and 1.0  or 0.85
    self:drawText(label, UI.PAD, textY, r, g, b, UI.UI_ALPHA, UIFont.Small)
end

UI.FoundRow = FoundRow

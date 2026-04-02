-- *****************************************************************************
-- * Loot Goblin 2000 – SearchBlock
-- * One item-search/finding unit inside the main window.
-- * Loaded after LootGoblin2000_Widgets.lua and before LootGoblin2000.lua.
-- *****************************************************************************

require "LootGoblin2000_Widgets"

local UI = LootGoblin2000.UI

-- ---------------------------------------------------------------------------
-- SearchBlock
-- ---------------------------------------------------------------------------

local SearchBlock = ISUIElement:derive("SearchBlock")

function SearchBlock:new(x, y, w, window)
    local h = UI.searchBlockH(0)
    local o = ISUIElement:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self

    o.blockWindow     = window   -- parent LootGoblin2000Window
    o.state           = "search" -- "search" | "finding"
    o.searchQuery     = ""
    o.searchResults   = {}
    o.templateMatch   = nil      -- matched template name, or nil
    o.targetItem      = nil      -- { displayName, fullType } or { isPartial=true, query=... } or { isTemplate=true, name=... }
    o.isPartialMode   = false
    o.foundIn         = {}
    o.hasPlayer       = false
    o.hasExternal     = false
    o.foundRows       = {}
    o.selectedRowIdx  = 0        -- 0 = none, 1..N = highlighted result row
    o.visibleRowCount = 0
    return o
end

function SearchBlock:initialise()
    ISUIElement.initialise(self)

    -- Search text entry
    self.searchEntry = ISTextEntryBox:new("", UI.PAD, UI.PAD, self.width - UI.PAD * 2, UI.SEARCH_BOX_H)
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self.searchEntry:setClearButton(true)
    self.searchEntry.font = UIFont.Small
    self.searchEntry.onTextChange = function(entry)
        self:onSearchTextChange(entry)
    end
    -- Enter/Return is dispatched via onCommandEntered (not onOtherKey).
    self.searchEntry.onCommandEntered = function(entry)
        self:handleKey(Keyboard.KEY_RETURN)
    end
    -- Escape: unfocus the field and destroy this block regardless of content.
    -- Escape is not delivered via onCommandEntered, so we use onOtherKey.
    self.searchEntry.onOtherKey = function(entry, key)
        if key == Keyboard.KEY_ESCAPE then
            Core.UnfocusActiveTextEntryBox()
            self.blockWindow:removeBlock(self)
        end
    end
    -- Arrow-up / arrow-down have dedicated callbacks in ISTextEntryBox.
    self.searchEntry.onPressUp = function(entry)
        self:handleKey(Keyboard.KEY_UP)
    end
    self.searchEntry.onPressDown = function(entry)
        self:handleKey(Keyboard.KEY_DOWN)
    end
    -- When the text entry loses focus (user clicked elsewhere) and the field
    -- is empty, remove this block so the add button reappears.
    self.searchEntry.onLostFocus = function(entry)
        self:onSearchEntryLostFocus()
    end
    self:addChild(self.searchEntry)

    -- Result rows (pre-created, shown/hidden as needed)
    -- +1 for the partial-match sentinel, +1 for the template-match sentinel
    self.resultRows = {}
    local rowsStartY = UI.PAD + UI.SEARCH_BOX_H + UI.PAD
    for i = 1, UI.MAX_RESULTS + 2 do
        local rowY = rowsStartY + (i - 1) * (UI.ROW_HEIGHT + UI.ROW_PADDING)
        local row  = UI.ResultRow:new(UI.PAD, rowY, self.width - UI.PAD * 2, UI.ROW_HEIGHT)
        row:initialise()
        row.onSelect = function(itemData) self:onItemSelected(itemData) end
        self:addChild(row)
        self.resultRows[i] = row
    end

    -- Pre-create FoundRow widgets
    for i = 1, UI.MAX_FOUND_LINES do
        local row = UI.FoundRow:new(UI.PAD, 0, self.width - UI.PAD * 2, UI.FOUND_ROW_H)
        row:initialise()
        row:setVisible(false)
        self:addChild(row)
        self.foundRows[i] = row
    end

    -- Remove button (finding mode) – top-right of the block
    local removeIcon = getTexture("media/textures/item-remove.png")
    self.removeBtn = UI.IconButton:new(
        self.width - UI.ICON_SIZE - UI.PAD,
        UI.PAD,
        UI.ICON_SIZE,
        removeIcon,
        self,
        function() self.blockWindow:removeBlock(self) end
    )
    self.removeBtn:initialise()
    self.removeBtn:setVisible(false)
    self:addChild(self.removeBtn)

    self:updateResultRows()
end

-- ---------------------------------------------------------------------------
-- Search logic
-- ---------------------------------------------------------------------------

function SearchBlock:onSearchTextChange(entry)
    self.searchQuery    = entry:getInternalText() or ""
    self.selectedRowIdx = 0
    self:runSearch()
end

function SearchBlock:runSearch()
    self.pendingSearch  = false
    self.searchResults  = LootGoblin2000.searchItems(self.searchQuery)
    self.templateMatch  = LootGoblin2000.searchTemplate(self.searchQuery)
    self:updateResultRows()
    -- Count visible rows: partial sentinel + optional template row + item results
    local extra = (self.searchQuery ~= "" and 1 or 0)
                + (self.templateMatch and 1 or 0)
    local visibleRows = #self.searchResults + extra
    self.visibleRowCount = visibleRows
    -- Pre-select the first result so arrow-down immediately goes to the second.
    if visibleRows > 0 then
        self.selectedRowIdx = 1
        self:syncRowHighlights()
    end
    self:setHeight(UI.searchBlockH(visibleRows))
    self.blockWindow:reflow()
end

function SearchBlock:updateResultRows()
    local query  = self.searchQuery
    local rowIdx = 1

    -- Row 1: partial-match sentinel (only when there is a query)
    if query ~= "" then
        self.resultRows[rowIdx]:setItemData({ isPartial = true, query = query })
        self.resultRows[rowIdx]:setVisible(true)
        rowIdx = rowIdx + 1
    end

    -- Row 2 (optional): template-match sentinel
    if self.templateMatch then
        self.resultRows[rowIdx]:setItemData({ isTemplate = true, name = self.templateMatch })
        self.resultRows[rowIdx]:setVisible(true)
        rowIdx = rowIdx + 1
    end

    -- Remaining rows: exact item search results
    for _, data in ipairs(self.searchResults) do
        if rowIdx > UI.MAX_RESULTS + 2 then break end
        self.resultRows[rowIdx]:setItemData(data)
        self.resultRows[rowIdx]:setVisible(true)
        rowIdx = rowIdx + 1
    end

    -- Hide unused rows
    for i = rowIdx, UI.MAX_RESULTS + 2 do
        self.resultRows[i]:setItemData(nil)
        self.resultRows[i]:setVisible(false)
    end

    self.visibleRowCount = rowIdx - 1
    self:syncRowHighlights()
end

-- ---------------------------------------------------------------------------
-- Keyboard navigation
-- ---------------------------------------------------------------------------

function SearchBlock:syncRowHighlights()
    for i, row in ipairs(self.resultRows) do
        row.highlighted = (i == self.selectedRowIdx)
    end
end

-- Returns true if the key was consumed.
-- Only called when the search entry is focused (via onCommandEntered /
-- onPressUp / onPressDown).  Escape is intentionally not handled here
-- so the game's default Escape behaviour (opening the menu) is preserved.
function SearchBlock:handleKey(key)
    if self.state ~= "search" then return false end

    if key == Keyboard.KEY_UP then
        if self.visibleRowCount > 0 then
            self.selectedRowIdx = self.selectedRowIdx <= 1
                and self.visibleRowCount
                or  self.selectedRowIdx - 1
            self:syncRowHighlights()
        end
        return true

    elseif key == Keyboard.KEY_DOWN then
        if self.visibleRowCount > 0 then
            self.selectedRowIdx = self.selectedRowIdx >= self.visibleRowCount
                and 1
                or  self.selectedRowIdx + 1
            self:syncRowHighlights()
        end
        return true

    elseif key == Keyboard.KEY_RETURN or key == Keyboard.KEY_NUMPADENTER then
        local targetIdx = self.selectedRowIdx
        if targetIdx == 0 and self.visibleRowCount > 0 and self.searchQuery ~= "" then
            targetIdx = 1
        end
        if targetIdx > 0 and self.resultRows[targetIdx] then
            local row = self.resultRows[targetIdx]
            if row.itemData and row.onSelect then
                -- Pass fromKeyboard=true so onItemSelected can open a new
                -- search block automatically after confirming this one.
                self:onItemSelected(row.itemData, true)
            end
        end
        return true
    end

    return false
end

-- Called when the search text entry loses focus (user clicked elsewhere).
-- If the mouse is over one of our result rows we do nothing – the row's
-- onMouseUp / onSelect will fire immediately after and handle the selection.
-- If the field has content, just leave it – the user can come back to it.
-- If the field is empty, remove this block (the add button will reappear).
function SearchBlock:onSearchEntryLostFocus()
    if self.state ~= "search" then return end
    -- Allow result-row clicks to proceed normally.
    for _, row in ipairs(self.resultRows) do
        if row:isVisible() and row:isMouseOver() then return end
    end
    -- If the field has content, just leave it – the user can come back to it.
    if self.searchQuery ~= "" then return end
    -- Empty field: always remove this block so the add button reappears.
    self.blockWindow:removeBlock(self)
end

-- ---------------------------------------------------------------------------
-- Item selected → switch to finding mode (or load template)
-- ---------------------------------------------------------------------------

-- fromKeyboard: when true the selection came from Enter, so we automatically
-- open a new search block and focus it for quick successive searches.
function SearchBlock:onItemSelected(itemData, fromKeyboard)
    -- Template shortcut: delegate to the window's loadTemplate and remove this block.
    if itemData.isTemplate then
        print("[LootGoblin2000] loading template '" .. itemData.name .. "' from search result")
        self.blockWindow:loadTemplate(itemData.name)
        return
    end

    self.targetItem     = itemData
    self.isPartialMode  = itemData.isPartial == true
    self.state          = "finding"
    self.foundIn        = {}
    self.hasPlayer      = false
    self.hasExternal    = false
    self.selectedRowIdx = 0

    self:setHeight(UI.findingBlockH(0))

    self.searchEntry:setVisible(false)
    for _, row in ipairs(self.resultRows) do row:setVisible(false) end
    for _, row in ipairs(self.foundRows)  do row:setVisible(false) end

    self.removeBtn:setVisible(true)

    self:scanContainers()
    self.blockWindow:reflow()

    if self.isPartialMode then
        print("[LootGoblin2000] block searching for partial '" .. itemData.query .. "'")
    else
        print("[LootGoblin2000] block searching for " .. itemData.fullType)
    end

    -- When confirmed via keyboard, open a new search block immediately so
    -- the user can keep adding items without touching the mouse.
    if fromKeyboard then
        self.blockWindow:addBlock()
    end
end

-- ---------------------------------------------------------------------------
-- Container scanning
-- ---------------------------------------------------------------------------

function SearchBlock:scanContainers()
    if self.state ~= "finding" or not self.targetItem then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local playerNum = pl:getPlayerNum()
    local prevCount = #self.foundIn

    if self.isPartialMode then
        self.foundIn, self.hasPlayer, self.hasExternal =
            LootGoblin2000.scanContainersForPartial(self.targetItem.query, playerNum)
    else
        self.foundIn, self.hasPlayer, self.hasExternal =
            LootGoblin2000.scanContainersForItem(self.targetItem.fullType, playerNum)
    end

    if #self.foundIn ~= prevCount then
        self:updateFoundRows()
        self:setHeight(UI.findingBlockH(#self.foundIn))
        self.blockWindow:reflow()
    else
        self:updateFoundRows()
    end
end

-- ---------------------------------------------------------------------------
-- Position and populate FoundRow widgets
-- ---------------------------------------------------------------------------

function SearchBlock:updateFoundRows()
    if not self.targetItem then return end
    local pl = getSpecificPlayer(0)
    local playerNum = pl and pl:getPlayerNum() or 0
    -- Header is always FINDING_HEADER_H; in normal mode add separator + equal padding above rows.
    local sepH  = UI.COMPACT and 0 or (1 + UI.PAD)
    local baseY = UI.FINDING_HEADER_H + sepH

    for i, row in ipairs(self.foundRows) do
        local entry = self.foundIn[i]
        if entry then
            row:setY(baseY + (i - 1) * UI.FOUND_ROW_H)
            row:setData(entry, playerNum, not entry.isPlayer)
            row:setVisible(true)
        else
            row:setData(nil, 0, false)
            row:setVisible(false)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Update (debounce)
-- ---------------------------------------------------------------------------

function SearchBlock:update()
    ISUIElement.update(self)
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function SearchBlock:prerender()
    local r, g, b, a = 0.12, 0.12, 0.12, UI.UI_ALPHA
    if self.state == "finding" then
        if self.hasExternal then
            r, g, b = 0.05, 0.18, 0.05   -- green: found externally
        elseif self.hasPlayer then
            r, g, b = 0.05, 0.08, 0.20   -- blue: found in player inventory only
        end
    end
    self:drawRect(0, 0, self.width, self.height, a, r, g, b)
    self:drawRect(0, self.height - 1, self.width, 1, a * 0.6, 0.25, 0.25, 0.25)
end

function SearchBlock:render()
    if self.state == "search" then
        self:renderSearch()
    else
        self:renderFinding()
    end
end

function SearchBlock:renderSearch()
    if #self.searchResults == 0 and self.searchQuery == "" then
        local hint = getText("UI_LootGoblin2000_Hint")
        local hintY = UI.PAD + UI.SEARCH_BOX_H + UI.PAD
        if hintY + getTextManager():getFontHeight(UIFont.Small) <= self.height then
            self:drawText(hint, UI.PAD, hintY, 0.5, 0.5, 0.5, UI.UI_ALPHA * 0.8, UIFont.Small)
        end
    end
end

function SearchBlock:renderFinding()
    local x        = UI.PAD
    local a        = UI.UI_ALPHA
    local maxNameW = self.width - UI.PAD * 3 - UI.ICON_SIZE

    -- In compact mode: one line, vertically centred in the icon band.
    -- In normal mode: name at PAD from top, ID below it (header is sized to fit both).
    local nameH = getTextManager():getFontHeight(UIFont.Medium)
    local nameY
    if UI.COMPACT then
        nameY = math.floor(UI.PAD + (UI.ICON_SIZE - nameH) / 2)
    else
        nameY = UI.PAD
    end

    -- Separator / found-rows start right after the header band.
    local sepY = UI.FINDING_HEADER_H

    if self.isPartialMode then
        local queryLabel = UI.truncateMedium('"' .. (self.targetItem and self.targetItem.query or "") .. '"', maxNameW)
        self:drawText(queryLabel, x, nameY, 0.75, 1.0, 0.75, a, UIFont.Medium)
        -- In normal mode show "partial match" subtitle; omit it in compact mode
        if not UI.COMPACT and UI.FINDING_ITEM_ID_H > 0 then
            local idY = nameY + nameH
            self:drawText(getText("UI_LootGoblin2000_PartialMatch"), x, idY, 0.55, 0.55, 0.55, a * 0.9, UIFont.Small)
        end
    else
        local liveName = self.foundIn and self.foundIn[1] and self.foundIn[1].itemName
        local name = UI.truncateMedium(liveName or (self.targetItem and self.targetItem.displayName) or "?", maxNameW)
        self:drawText(name, x, nameY, 1, 1, 1, a, UIFont.Medium)
        -- Show item ID below name only in normal (non-compact) mode
        if not UI.COMPACT and UI.FINDING_ITEM_ID_H > 0 then
            local idY = nameY + nameH
            local idLabel = self.targetItem and self.targetItem.fullType or ""
            self:drawText(idLabel, x, idY, 0.55, 0.55, 0.55, a * 0.9, UIFont.Small)
        end
    end

    -- Draw separator only in normal mode
    if #self.foundIn > 0 and not UI.COMPACT then
        self:drawRect(UI.PAD, sepY, self.width - UI.PAD * 2, 1, a * 0.5, 0.4, 0.4, 0.4)
    end
end

-- Export
LootGoblin2000.UI.SearchBlock = SearchBlock

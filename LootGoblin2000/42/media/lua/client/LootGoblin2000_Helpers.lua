-- *****************************************************************************
-- * Loot Goblin 2000 – Helpers
-- * Non-UI logic: item cache, search, container scanning, item transfer.
-- * Loaded before LootGoblin2000.lua (alphabetical order ensures this).
-- *****************************************************************************

require "TimedActions/ISInventoryTransferUtil"

LootGoblin2000 = LootGoblin2000 or {}

-- ---------------------------------------------------------------------------
-- Template persistence (ModData)
-- ---------------------------------------------------------------------------

local MOD_DATA_KEY = "LootGoblin2000Templates"

-- Returns the templates table { [name] = { items = { {displayName, fullType, isPartial, query}, ... } } }
function LootGoblin2000.getTemplates()
    local md = ModData.getOrCreate(MOD_DATA_KEY)
    if not md.templates then
        md.templates = {}
    end
    return md.templates
end

-- Returns a sorted list of template names.
function LootGoblin2000.getTemplateNames()
    local templates = LootGoblin2000.getTemplates()
    local names = {}
    for name, _ in pairs(templates) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

-- Saves the current list of finding-mode blocks as a named template.
-- blocks: array of SearchBlock objects (only "finding" state blocks are saved).
function LootGoblin2000.saveTemplate(name, blocks)
    if not name or name == "" then return end
    local templates = LootGoblin2000.getTemplates()
    local items = {}
    for _, block in ipairs(blocks) do
        if block.state == "finding" and block.targetItem then
            items[#items + 1] = {
                displayName = block.targetItem.displayName,
                fullType    = block.targetItem.fullType,
                isPartial   = block.isPartialMode == true,
                query       = block.targetItem.query,
            }
        end
    end
    templates[name] = { items = items }
    ModData.add(MOD_DATA_KEY, ModData.getOrCreate(MOD_DATA_KEY))
    print("[LootGoblin2000] saved template '" .. name .. "' with " .. #items .. " item(s).")
end

-- Removes a named template.
function LootGoblin2000.removeTemplate(name)
    if not name or name == "" then return end
    local templates = LootGoblin2000.getTemplates()
    templates[name] = nil
    ModData.add(MOD_DATA_KEY, ModData.getOrCreate(MOD_DATA_KEY))
    print("[LootGoblin2000] removed template '" .. name .. "'.")
end

-- Returns the items array for a named template, or nil.
function LootGoblin2000.getTemplate(name)
    local templates = LootGoblin2000.getTemplates()
    return templates[name] and templates[name].items or nil
end

-- Returns the first template name whose name contains `query` (case-insensitive),
-- or nil if no match.
function LootGoblin2000.searchTemplate(query)
    if not query or query == "" then return nil end
    local lq = query:lower()
    local names = LootGoblin2000.getTemplateNames()
    for _, name in ipairs(names) do
        if name:lower():find(lq, 1, true) then
            return name
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Cached item list (built once per session)
-- ---------------------------------------------------------------------------

local cachedItems = nil

function LootGoblin2000.buildItemCache()
    if cachedItems then return end
    cachedItems = {}
    local allItems = getScriptManager():getAllItems()
    for i = 0, allItems:size() - 1 do
        local scriptItem = allItems:get(i)
        local dn = scriptItem:getDisplayName()
        local ft = scriptItem:getFullName()
        if dn and dn ~= "" and ft and ft ~= "" then
            cachedItems[#cachedItems + 1] = {
                displayName = dn,
                fullType    = ft,
                lowerName   = dn:lower(),
                lowerType   = ft:lower(),
            }
        end
    end
    table.sort(cachedItems, function(a, b) return a.lowerName < b.lowerName end)
    print("[LootGoblin2000] cached " .. #cachedItems .. " items.")
end

-- ---------------------------------------------------------------------------
-- Search helper
-- ---------------------------------------------------------------------------

local MAX_RESULTS = 5

function LootGoblin2000.searchItems(query)
    local results = {}
    if not query or query == "" then return results end
    local lq = query:lower()
    for _, entry in ipairs(cachedItems) do
        if entry.lowerName:find(lq, 1, true) or entry.lowerType:find(lq, 1, true) then
            results[#results + 1] = entry
            if #results >= MAX_RESULTS then break end
        end
    end
    return results
end

-- ---------------------------------------------------------------------------
-- Container scanning helpers
-- ---------------------------------------------------------------------------

-- Exact-type scan.
-- Returns { found, hasPlayer, hasExternal }
-- Each entry in `found` has { containerName, itemName, fullType, count, isPlayer, inventory }.
-- Items that share the same display name (e.g. left/right wrist watch variants) are
-- grouped into a single entry, matching how the vanilla inventory displays them.
function LootGoblin2000.scanContainersForItem(fullType, playerNum)
    local found       = {}
    local hasPlayer   = false
    local hasExternal = false
    local ignorePlayer = LootGoblin2000.options
                         and LootGoblin2000.options.IgnorePlayerContainers
                         and LootGoblin2000.options.IgnorePlayerContainers:getValue()

    -- Resolve the canonical display name for the requested fullType once.
    -- We use this to also count items of other fullTypes that share the same
    -- display name (e.g. WristWatch_Left_DigitalBlack and _Right_DigitalBlack
    -- both show as "Digital Watch" in the inventory).
    local targetDisplayName = nil
    do
        local scriptItem = getScriptManager():getItem(fullType)
        if scriptItem then
            targetDisplayName = scriptItem:getDisplayName()
        end
    end

    local function scanContainer(container, playerObj)
        local items = container:getItems()
        -- Group by display name so variants with the same name are merged.
        -- Key = display name, value = { count, itemName, fullType (first seen) }
        local groups = {}
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local itemFT = item:getFullType()
            -- Match the requested fullType OR any item whose display name equals
            -- the target display name (covers left/right variants, etc.)
            local dn = item:getDisplayName()
            local matches = (itemFT == fullType)
                         or (targetDisplayName and dn == targetDisplayName)
            if matches then
                local key = dn or itemFT
                if not groups[key] then
                    groups[key] = {
                        count    = 0,
                        itemName = item:getName(playerObj) or dn,
                        fullType = itemFT,
                    }
                end
                groups[key].count = groups[key].count + 1
            end
        end
        return groups
    end

    local function checkBp(bp, isPlayer)
        if not bp or not bp.inventory then return end
        local playerObj = getSpecificPlayer(playerNum)
        local ok, groups = pcall(scanContainer, bp.inventory, playerObj)
        if not ok or not groups then return end
        local label = (bp.name and bp.name ~= "") and bp.name
                      or getText("UI_LootGoblin2000_PlayerInventory")
        for _, g in pairs(groups) do
            if g.count > 0 then
                found[#found + 1] = {
                    containerName = label,
                    itemName      = g.itemName,
                    fullType      = g.fullType,
                    count         = g.count,
                    isPlayer      = isPlayer,
                    inventory     = bp.inventory,
                }
                if isPlayer then
                    hasPlayer = true
                else
                    hasExternal = true
                end
            end
        end
    end

    if not ignorePlayer then
        local invPage = getPlayerInventory(playerNum)
        if invPage and invPage.inventoryPane and invPage.inventoryPane.inventoryPage then
            for _, bp in ipairs(invPage.inventoryPane.inventoryPage.backpacks) do
                checkBp(bp, true)
            end
        end
    end

    local lootPage = getPlayerLoot(playerNum)
    if lootPage and lootPage.inventoryPane and lootPage.inventoryPane.inventoryPage then
        for _, bp in ipairs(lootPage.inventoryPane.inventoryPage.backpacks) do
            if bp and bp.inventory then
                local parent = bp.inventory:getParent()
                local skip = false
                if parent and instanceof(parent, "IsoThumpable") then
                    local pl = getSpecificPlayer(playerNum)
                    if pl and parent:isLockedToCharacter(pl) then
                        skip = true
                    end
                end
                if not skip then checkBp(bp, false) end
            end
        end
    end

    return found, hasPlayer, hasExternal
end

-- Partial-name scan.
-- Scans all containers for items whose display name contains `query` (case-insensitive).
-- Returns flat list of entries: { containerName, itemName, fullType, count, isPlayer, inventory }
-- Each unique (container, displayName) pair becomes one entry, matching how the vanilla
-- inventory groups items by display name (e.g. left/right watch variants merged into one row).
function LootGoblin2000.scanContainersForPartial(query, playerNum)
    local found       = {}
    local hasPlayer   = false
    local hasExternal = false
    local lq          = query:lower()
    local ignorePlayer = LootGoblin2000.options
                         and LootGoblin2000.options.IgnorePlayerContainers
                         and LootGoblin2000.options.IgnorePlayerContainers:getValue()

    local function scanContainer(bp, isPlayer)
        if not bp or not bp.inventory then return end
        local container = bp.inventory
        local ok, items = pcall(function() return container:getItems() end)
        if not ok or not items then return end

        local parent = container:getParent()
        if parent and instanceof(parent, "IsoThumpable") then
            local pl = getSpecificPlayer(playerNum)
            if pl and parent:isLockedToCharacter(pl) then return end
        end

        local label = (bp.name and bp.name ~= "") and bp.name
                      or getText("UI_LootGoblin2000_PlayerInventory")

        local playerObj = getSpecificPlayer(playerNum)

        -- Accumulate counts per display name within this container.
        -- Items that share a display name (e.g. left/right wrist watch variants)
        -- are merged into one entry, matching vanilla inventory grouping.
        local counts   = {}  -- displayName → count
        local names    = {}  -- displayName → resolved item name (from getName())
        local firstFTs = {}  -- displayName → fullType of first seen item (for grab/locate)
        for i = 0, items:size() - 1 do
            local item = items:get(i)
            local dn   = item:getDisplayName()
            local resolved = item:getName(playerObj) or dn
            if resolved and resolved:lower():find(lq, 1, true) then
                if not counts[dn] then
                    counts[dn]   = 0
                    names[dn]    = resolved
                    firstFTs[dn] = item:getFullType()
                end
                counts[dn] = counts[dn] + 1
            end
        end

        for dn, cnt in pairs(counts) do
            found[#found + 1] = {
                containerName = label,
                itemName      = names[dn],
                fullType      = firstFTs[dn],
                count         = cnt,
                isPlayer      = isPlayer,
                inventory     = container,
            }
            if isPlayer then hasPlayer = true else hasExternal = true end
        end
    end

    if not ignorePlayer then
        local invPage = getPlayerInventory(playerNum)
        if invPage and invPage.inventoryPane and invPage.inventoryPane.inventoryPage then
            for _, bp in ipairs(invPage.inventoryPane.inventoryPage.backpacks) do
                scanContainer(bp, true)
            end
        end
    end

    local lootPage = getPlayerLoot(playerNum)
    if lootPage and lootPage.inventoryPane and lootPage.inventoryPane.inventoryPage then
        for _, bp in ipairs(lootPage.inventoryPane.inventoryPage.backpacks) do
            scanContainer(bp, false)
        end
    end

    return found, hasPlayer, hasExternal
end

-- ---------------------------------------------------------------------------
-- Item-transfer action helpers
-- ---------------------------------------------------------------------------

function LootGoblin2000.grabOneItem(entry, playerNum)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local alwaysRoot = LootGoblin2000.options
                       and LootGoblin2000.options.AlwaysRootInventory
                       and LootGoblin2000.options.AlwaysRootInventory:getValue()
    local playerInv = alwaysRoot and playerObj:getInventory() or getPlayerInventory(playerNum).inventory
    if not playerInv then return end
    local srcContainer = entry.inventory
    if not srcContainer then return end
    local fullType = entry.fullType

    local items = srcContainer:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == fullType then
            ISTimedActionQueue.add(
                ISInventoryTransferUtil.newInventoryTransferAction(
                    playerObj, item, srcContainer, playerInv
                )
            )
            return
        end
    end
end

function LootGoblin2000.grabAllItems(entry, playerNum)
    local playerObj = getSpecificPlayer(playerNum)
    if not playerObj then return end
    local alwaysRoot = LootGoblin2000.options
                       and LootGoblin2000.options.AlwaysRootInventory
                       and LootGoblin2000.options.AlwaysRootInventory:getValue()
    local playerInv = alwaysRoot and playerObj:getInventory() or getPlayerInventory(playerNum).inventory
    if not playerInv then return end
    local srcContainer = entry.inventory
    if not srcContainer then return end
    local fullType = entry.fullType

    local toTransfer = {}
    local items = srcContainer:getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:getFullType() == fullType then
            toTransfer[#toTransfer + 1] = item
        end
    end

    for _, item in ipairs(toTransfer) do
        ISTimedActionQueue.add(
            ISInventoryTransferUtil.newInventoryTransferAction(
                playerObj, item, srcContainer, playerInv
            )
        )
    end
end

function LootGoblin2000.locateItem(entry, playerNum)
    local srcContainer = entry.inventory
    if not srcContainer then return end
    local fullType = entry.fullType

    local invPage  = getPlayerInventory(playerNum)
    local lootPage = getPlayerLoot(playerNum)
    if invPage and not invPage:getIsVisible() then
        invPage:setVisible(true)
        if lootPage then lootPage:setVisible(true) end
    end

    local page = entry.isPlayer and invPage or lootPage
    if not page then return end

    local invPageObj = page.inventoryPane and page.inventoryPane.inventoryPage
    if not invPageObj then return end

    local pane = nil
    for _, btn in ipairs(invPageObj.backpacks) do
        if btn.inventory == srcContainer then
            invPageObj:selectContainer(btn)
            invPageObj:setForceSelectedContainer(srcContainer, 1000)
            pane = invPageObj.inventoryPane
            break
        end
    end

    if pane and pane.itemslist then
        local row = 1
        for _, group in ipairs(pane.itemslist) do
            local matched = false
            for _, item in ipairs(group.items) do
                if instanceof(item, "InventoryItem") and item:getFullType() == fullType then
                    matched = true
                    break
                end
            end
            if matched then
                pane.selected = {}
                pane.selected[row] = group
                local targetY = -((row - 1) * pane.itemHgt)
                pane.smoothScrollTargetY = targetY
                pane.smoothScrollY = pane:getYScroll()
                break
            end
            local isCollapsed = (pane.collapsed == nil) or (pane.collapsed[group.name] ~= false)
            if isCollapsed then
                row = row + 1
            else
                row = row + #group.items
            end
        end
    end
end

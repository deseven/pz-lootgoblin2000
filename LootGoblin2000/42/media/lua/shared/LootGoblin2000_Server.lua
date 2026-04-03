-- *****************************************************************************
-- * Loot Goblin 2000 – Server-side ModData relay
-- * Runs in the "shared" context so it executes on the server in multiplayer.
-- * Handles persisting and broadcasting the templates ModData key so that
-- * each player's templates survive logout/login in multiplayer.
-- *****************************************************************************

local MOD_DATA_KEY = "LootGoblin2000Templates"

-- Called on the server when the world initialises.
-- Creates the ModData entry if it doesn't exist yet and broadcasts it to all
-- connected clients so they can load their templates immediately.
local function onInitGlobalModData(is_new_game)
    if not isServer() then return end
    print("[LootGoblin2000][Server] onInitGlobalModData fired, is_new_game=" .. tostring(is_new_game))
    local md = ModData.getOrCreate(MOD_DATA_KEY)
    ModData.add(MOD_DATA_KEY, md)
    ModData.transmit(MOD_DATA_KEY)
    print("[LootGoblin2000][Server] Transmitted initial ModData to all clients.")
end

-- Called on the server when a client sends updated ModData via ModData.transmit().
-- Persists the new data and re-broadcasts it to all clients.
local function onReceiveGlobalModData(key, data)
    if key ~= MOD_DATA_KEY then return end
    print("[LootGoblin2000][Server] onReceiveGlobalModData received for key=" .. tostring(key))
    -- PZ transmits empty tables as `false`; normalise to an empty table.
    if data == false or data == nil then
        data = {}
    end
    -- Only transmit if the data actually changed to avoid unnecessary traffic.
    local md = ModData.get(MOD_DATA_KEY)
    ModData.add(MOD_DATA_KEY, data)
    ModData.transmit(MOD_DATA_KEY)
    print("[LootGoblin2000][Server] Persisted and re-transmitted updated templates.")
end

if isServer() then
    Events.OnInitGlobalModData.Add(onInitGlobalModData)
    Events.OnReceiveGlobalModData.Add(onReceiveGlobalModData)
end

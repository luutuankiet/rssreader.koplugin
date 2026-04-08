-- rssreader_cache.lua
-- Simple file-based cache for RSS feed data.
-- Reduces network requests on memory/CPU constrained devices (Kindle PW3).

local json = require("common/json")
local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local logger = require("logger")

local Cache = {}

local CACHE_DIR = DataStorage:getSettingsDir() .. "/rssreader_cache"

local DEFAULT_TTL = 1800 -- 30 minutes

local function ensureCacheDir()
    local settings_dir = DataStorage:getSettingsDir()
    lfs.mkdir(settings_dir)
    lfs.mkdir(CACHE_DIR)
end

local function cacheKeyToPath(key)
    -- Replace non-alphanumeric chars with underscores, cap length
    local safe = key:gsub("[^%w%-_]", "_"):sub(1, 200)
    return CACHE_DIR .. "/" .. safe .. ".json"
end

--- Get cached data for a key. Returns nil if expired or missing.
-- @param key string Cache key
-- @param ttl number Time-to-live in seconds (default 1800)
-- @return table|nil Cached data or nil
function Cache.get(key, ttl)
    ttl = ttl or DEFAULT_TTL
    local path = cacheKeyToPath(key)
    local attr = lfs.attributes(path)
    if not attr then
        return nil
    end
    local age = os.time() - attr.modification
    if age > ttl then
        os.remove(path)
        logger.dbg("RSSReader cache expired:", key, "age:", age, "s")
        return nil
    end
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then
        os.remove(path)
        return nil
    end
    local ok, data = pcall(json.decode, content)
    if not ok or not data then
        os.remove(path)
        return nil
    end
    logger.dbg("RSSReader cache hit:", key, "age:", age, "s")
    return data
end

--- Store data in cache.
-- @param key string Cache key
-- @param data table Data to cache (must be JSON-serializable)
-- @return boolean Success
function Cache.set(key, data)
    ensureCacheDir()
    local path = cacheKeyToPath(key)
    local ok, encoded = pcall(json.encode, data)
    if not ok or not encoded then
        logger.warn("RSSReader cache encode failed:", key)
        return false
    end
    local f = io.open(path, "w")
    if not f then
        logger.warn("RSSReader cache write failed:", key, path)
        return false
    end
    f:write(encoded)
    f:close()
    logger.dbg("RSSReader cache set:", key)
    return true
end

--- Remove a specific cache entry.
function Cache.invalidate(key)
    local path = cacheKeyToPath(key)
    os.remove(path)
    logger.dbg("RSSReader cache invalidated:", key)
end

--- Invalidate all cache entries matching a prefix.
function Cache.invalidatePrefix(prefix)
    local safe_prefix = prefix:gsub("[^%w%-_]", "_")
    local count = 0
    for entry in lfs.dir(CACHE_DIR) do
        if entry ~= "." and entry ~= ".." and entry:sub(1, #safe_prefix) == safe_prefix then
            os.remove(CACHE_DIR .. "/" .. entry)
            count = count + 1
        end
    end
    if count > 0 then
        logger.dbg("RSSReader cache invalidated", count, "entries with prefix:", prefix)
    end
end

--- Remove all cache entries.
function Cache.clear()
    local count = 0
    local ok, iter, dir_obj = pcall(lfs.dir, CACHE_DIR)
    if not ok then
        return 0
    end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            os.remove(CACHE_DIR .. "/" .. entry)
            count = count + 1
        end
    end
    logger.info("RSSReader cache cleared:", count, "entries")
    return count
end

--- Get cache stats for diagnostics.
function Cache.stats()
    local count = 0
    local total_size = 0
    local ok, iter, dir_obj = pcall(lfs.dir, CACHE_DIR)
    if not ok then
        return { entries = 0, total_bytes = 0 }
    end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." then
            local attr = lfs.attributes(CACHE_DIR .. "/" .. entry)
            if attr then
                count = count + 1
                total_size = total_size + (attr.size or 0)
            end
        end
    end
    return { entries = count, total_bytes = total_size }
end

return Cache

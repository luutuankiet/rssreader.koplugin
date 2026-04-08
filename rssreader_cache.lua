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
local DEFAULT_MAX_ENTRIES = 50 -- max cached articles before LRU eviction

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
    -- ttl == 0 means never expire (permanent cache)
    if ttl > 0 then
        local age = os.time() - attr.modification
        if age > ttl then
            os.remove(path)
            logger.dbg("RSSReader cache expired:", key, "age:", age, "s")
            return nil
        end
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
--- Evict oldest entries when a prefix exceeds max_entries.
-- Sorts by mtime (oldest first), removes the oldest half.
local function evictIfNeeded(prefix, max_entries)
    max_entries = max_entries or DEFAULT_MAX_ENTRIES
    local safe_prefix = prefix:gsub("[^%w%-_]", "_")
    local entries = {}
    local ok, iter, dir_obj = pcall(lfs.dir, CACHE_DIR)
    if not ok then return end
    for entry in iter, dir_obj do
        if entry ~= "." and entry ~= ".." and entry:sub(1, #safe_prefix) == safe_prefix then
            local full_path = CACHE_DIR .. "/" .. entry
            local attr = lfs.attributes(full_path)
            if attr then
                table.insert(entries, { path = full_path, mtime = attr.modification })
            end
        end
    end
    if #entries <= max_entries then return end
    -- Sort oldest first
    table.sort(entries, function(a, b) return a.mtime < b.mtime end)
    -- Remove oldest half
    local to_remove = math.floor(#entries / 2)
    for i = 1, to_remove do
        os.remove(entries[i].path)
    end
    logger.info("RSSReader cache evicted", to_remove, "oldest", prefix, "entries (", #entries, "exceeded", max_entries, ")")
end

--- Store data in cache. Runs LRU eviction if prefix limit exceeded.
-- @param key string Cache key
-- @param data table Data to cache (must be JSON-serializable)
-- @param max_entries number Optional max entries for this key prefix (default 50)
-- @return boolean Success
function Cache.set(key, data, max_entries)
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
    -- Run LRU eviction based on key prefix (everything before first ':')
    local prefix = key:match("^([^:]+)") or key
    evictIfNeeded(prefix, max_entries)
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

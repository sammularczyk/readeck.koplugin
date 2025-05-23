local CacheSQLite = require("cachesqlite")
local LuaSettings = require("luasettings")

local defaults = require("defaultsettings")
local logger = require("logger")

--- @todo this could be much better optimized by using lua-ljsqlite3 directly
local ReadeckCache = {
    -- Mandatory
    settings = LuaSettings,
}

function ReadeckCache:getSetting(setting)
    return self.settings:readSetting(setting, defaults[setting])
end

function ReadeckCache:new(o)
    o = o or {}
    if not o.settings then
        return nil, "Missing constructor parameters"
    end

    setmetatable(o, self)
    self.__index = self
    if o.init then o:init() end
    return o
end

function ReadeckCache:init()
    self.cache = CacheSQLite:new{
        size = self:getSetting("_cache_size"),
        db_path = self:getSetting("data_dir") .. "/cache.sqlite"
    }
end

function ReadeckCache:cacheBookmarkList(key, bookmarks)
    self.cache.auto_close = false

    local bookmark_ids = {}

    for i, b in ipairs(bookmarks) do
        -- Add to list of bookmarks in this collection
        table.insert(bookmark_ids, b.id)

        -- Cache bookmark data
        -- TODO compare last modified dates so we can decide whether the entry should be updated?
        if not self.cache:check(b.id) then
            self.cache:insert(b.id, b)
        end
    end

    self.cache:insert(key, bookmark_ids)

    self.cache.auto_close = true
    self.cache:closeDB()
end

function ReadeckCache:getCachedBookmarksFromList(key)
    self.cache.auto_close = false

    local bookmark_ids = self.cache:get(key)
    if not bookmark_ids then
        self.cache.auto_close = true
        self.cache:closeDB()
        return nil
    end

    local bookmarks = {}

    for i, id in ipairs(bookmark_ids) do
        local b = self.cache:get(id)
        if b then
            table.insert(bookmarks, b)
        end
    end

    self.cache.auto_close = true
    self.cache:closeDB()

    return bookmarks
end

-- Labels
function ReadeckCache:cacheLabelList(labels)
    self.cache:insert("labels", labels)
end

function ReadeckCache:getCachedLabelList()
    return self.cache:get("labels")
end

function ReadeckCache:cacheLabelBookmarks(label, bookmarks)
    self:cacheBookmarkList("l-" .. label.name, bookmarks)
end

function ReadeckCache:getCachedLabelBookmarks(label)
    return self:getCachedBookmarksFromList("l-" .. label.name)
end

-- Collections
function ReadeckCache:cacheCollectionList(collections)
    self.cache:insert("collections", collections)
end

function ReadeckCache:getCachedCollectionList()
    local result = self.cache:get("collections")
    return result
end

function ReadeckCache:cacheCollectionBookmarks(collection, bookmarks)
    self:cacheBookmarkList(collection.id, bookmarks)
end

function ReadeckCache:getCachedCollectionBookmarks(collection)
    return self:getCachedBookmarksFromList(collection.id)
end

return ReadeckCache

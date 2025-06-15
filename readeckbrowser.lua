local BookList = require("ui/widget/booklist")
local Cache = require("cache")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")

local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local ReadeckApi = require("readeckapi")

local CatalogCache = Cache:new {
    -- Make it 20 slots, with no storage space constraints
    slots = 20,
}

--------====== PATHS ======--------

local MenuPath = {
    browser = nil,
    title = nil,
    subtitle = nil,
    item_table = nil,
    itemnumber = nil,
}

function MenuPath:extend(subclass_prototype)
    local o = subclass_prototype or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function MenuPath:new(o)
    o = self:extend(o)
    if o.init then o:init() end
    return o
end

function MenuPath:buildItemTable()
    return nil, T("Readeck: MenuPath:buildItemTable(): Method was not overriden for %1. Returning empty item table.", self.title or "nil")
end

function MenuPath:getItemTable()
    if not self.item_table then
        local result, err = self:buildItemTable()
        if not result then
            return nil, err
        end

        self.item_table = result
    end

    return self.item_table
end

-- -- Bookmarks path

local BookmarksPath = MenuPath:extend{
    -- Queries parameters are directly used for https://[yourreadeck]/docs/api#get-/bookmarks
    query = {},
    -- The entry id to get or save the bookmark list to
    cache_entry = nil,
}

function BookmarksPath:buildItemTable()
    local bookmarks, err = self.browser.api:bookmarkList(self.query, self.cache_entry)
    if not bookmarks then
        return nil, err
    end

    local item_table = {}
    for i, b in ipairs(bookmarks) do
        item_table[i] = {
            text = b.title,
            mandatory_func = function()
                local progress_str
                if self.browser.api:bookmarkDownloaded(b) then
                    local book_info = BookList.getBookInfo(self.browser.api:getBookmarkFilename(b))
                    local local_progress = 100 * util.round_decimal(book_info.percent_finished or 0, 2)

                    progress_str = local_progress == b.read_progress
                                    and local_progress .. "%  " -- FontAwesome download icon
                                    or T("%1%  %2% ", local_progress, b.read_progress)
                else
                    progress_str = b.read_progress .. "% " -- FontAwesome cloud icon
                end

                return T("%1, %2min", progress_str, b.reading_time)
            end,
            bookmark = b,
        }
    end

    return item_table
end

function BookmarksPath:onMenuSelect(item)
    local downloading_dialog = InfoMessage:new{
        text = T(_(self.browser.api:bookmarkDownloaded(item.bookmark)
                    and "Opening bookmark...\n%1"
                    or "Downloading bookmark...\n%1"), item.bookmark.title)
    }
    UIManager:show(downloading_dialog)

    local file, already_downloaded = self.browser.api:downloadBookmark(item.bookmark)
    if not file then
        local err = already_downloaded

        UIManager:close(downloading_dialog)
        UIManager:show(InfoMessage:new{ text = T(_"Error downloading bookmark: %1", err), })
        return nil
    end

    UIManager:close(downloading_dialog)
    ReaderUI:showReader(file)
end

-- -- LabelsPath

local LabelsPath = MenuPath:extend{
    title = _"Readeck labels"
}

function LabelsPath:buildItemTable()
    local item_table = {}

    local labels, err = self.browser.api:labelList()
    if not labels then
        return nil, err
    end
    for i, l in ipairs(labels) do
        item_table[i] = {
            text = l.name,
            mandatory = l.count,
            path = BookmarksPath:new{
                browser = self.browser,
                query = { labels = '"' .. l.name .. '"' },
                cache_entry = "l-" .. l.name,
            },
        }
    end

    return item_table
end

function LabelsPath:onMenuSelect(item)
    self.browser:pushPath(item.path)
    return item.path
end

-- -- RootPath

local RootPath = MenuPath:extend{
    title = _"Readeck bookmarks"
}

function RootPath:buildItemTable()
    local item_table = {
        {
            text = _"Unread Bookmarks",
            -- TODO mandatory = get amount somehow
            path = BookmarksPath:new{
                browser = self.browser,
                query = { is_archived = false },
                cache_entry = "Unread",
            }
        }, {
            text = _"Archived Bookmarks",
            -- TODO mandatory = get amount somehow
            path = BookmarksPath:new{
                browser = self.browser,
                query = { is_archived = true },
                cache_entry = "Archived",
            }
        }, {
            text = _"Favorite Bookmarks",
            path = BookmarksPath:new{
                browser = self.browser,
                query = { is_marked = true },
                cache_entry = "Favorite",
            }
        }, {
            text = _"All Bookmarks",
            path = BookmarksPath:new{
                browser = self.browser,
                query = {},
                cache_entry = "All",
            }
        }, {
            text = _"Labels",
            path = LabelsPath:new{ browser = self.browser }
        },
    }

    local collections, err = self.browser.api:collectionList()
    if not collections then
        logger.warn("ReadeckBrowser : Couldn't load collections: " .. err)
        return item_table, err
    end

    for i, c in pairs(collections) do
        local collection_id = c.id
        -- NOTE: THIS IS ASSUMING NONE OF THE FIELDS OTHER THAN id RETURNED IN
        -- collectionDetails CONTAINS ANY FIELDS RELEVANT FOR THE bookmarkList's
        -- QUERY, AND WILL BE IGNORED, LEADING TO THE EXPECTED RESULT
        c.id = nil -- So the collection id doesn't conflict with the bookmark query
        local item = {
            text = T(_"Collection: %1", c.name),
            path = BookmarksPath:new{
                browser = self.browser,
                query = c,
                cache_entry = collection_id
            }
        }
        table.insert(item_table, item)
    end

    return item_table
end

function RootPath:onLeftButtonTap()
    -- TODO search for bookmark
end

function RootPath:onMenuSelect(item)
    local new_path = item.path
    new_path.title = new_path.title or item.text
    self.browser:pushPath(new_path)
    return new_path
end


--------====== BROWSER WINDOW ======--------

local Browser = Menu:extend{
    -- Mandatory
    api = ReadeckApi,
    settings = LuaSettings,
}

function Browser:new(o)
    print(o.api)
    print(o.settings)
    if not (o and o.api and o.settings) then
        logger.warn("Browser:new() : Missing constructor parameters")
        return nil, "Missing constructor parameters"
    end
    return getmetatable(self).new(self, o)
end

function Browser:init()
    self.no_title = false
    self.is_borderless = true
    self.is_popout = false
    self.parent = nil
    self.covers_full_screen = true
    self.return_arrow_propagation = false

    self.title_bar_left_icon = "appbar.search"

    self.root_path = RootPath:new { browser = self }
    self.item_table = self.root_path:getItemTable()
    self.title = self.root_path.title
    self.subtitle = self.root_path.subtitle

    self.refresh_callback = function()
        --UIManager:setDirty(...?)
        self.ui:onRefresh()
    end
    Menu.init(self) -- call parent's init()
end

function Browser:getCurrentPath()
    return self.paths[#self.paths] or self.root_path
end

function Browser:pushPath(path)
    local new_item_table, err = path:getItemTable()
    if not new_item_table then
        UIManager:show(InfoMessage:new{
            text = T(_"Couldn't load menu '%1':\n%2", path.title, err or _"Unknown error"),
            timeout = 5,
        })
        return self.paths[#self.paths]
    end

    table.insert(self.paths, path)
    self:switchItemTable(path.title, path:getItemTable(), path.itemnumber, nil, path.subtitle)
    return path
end

-- -- UI EVENT HANDLING -- --
-- Menu overrides --
function Browser:onMenuSelect(item)
    return self:getCurrentPath():onMenuSelect(item)
end

function Browser:onReturn()
    table.remove(self.paths)
    local path = self.paths[#self.paths] or self.root_path
    -- return to root path
    self:switchItemTable(path.title, path:getItemTable(), path.itemnumber, nil, path.subtitle)
    return path
end

-- Menu action on return-arrow long-press (return to root path)
function Browser:onHoldReturn()
    self.paths = {}
    self:switchItemTable(self.root_path.title, self.root_path:getItemTable(),
                            self.root_path.itemnumber, nil, self.root_path.subtitle)
    return self.root_path
end

function Browser:onLeftButtonTap()
    self:getCurrentPath():onLeftButtonTap()
end

return Browser

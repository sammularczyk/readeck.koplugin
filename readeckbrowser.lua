local BD = require("ui/bidi")
local ButtonDialog = require("ui/widget/buttondialog")
local Cache = require("cache")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local url = require("socket.url")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local defaults = require("defaultsettings")

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
    logger.dbg("Readeck: MenuPath:buildItemTable(): Method was not overriden. Returning empty item table.")
    return {}
end

function MenuPath:getItemTable()
    return self.item_table or self:buildItemTable()
end

-- Bookmarks path

local BookmarksPath = MenuPath:extend{
    -- Queries parameters are directly used for https://[yourreadeck]/docs/api#get-/bookmarks
    query = {}
}

function BookmarksPath:buildItemTable()
    self.item_table = {}

    -- TODO handle errors and internet connection
    local bookmarks = self.browser.api:bookmarkList(self.query)
    for i, b in ipairs(bookmarks) do
        self.item_table[i] = {
            text = _(b.title),
            mandatory = _(b.read_progress .. "%"),
            bookmark = b,
        }
    end

    return self.item_table
end

function BookmarksPath:onMenuSelect(item)
    -- TODO check for file already downloaded
    local dir = self.browser.settings:readSetting("data_dir", defaults.data_dir)
    util.makePath(dir)
    local file = dir .. "/"
        .. util.getSafeFilename(item.bookmark.id  .. "-" .. item.bookmark.title .. ".epub", dir)

    local header, err = self.browser.api:bookmarkExport(file, item.bookmark.id)
    if err then
        UIManager:show(InfoMessage:new{
            text = _("Error: " .. err),
        })
    else
        UIManager:show(InfoMessage:new{
            text = T(_("%1 downloaded to %2"), item.bookmark.title, file)
        })
    end
end


-- RootPath

local RootPath = MenuPath:extend{
    title = _("Redeck bookmarks")
}

function RootPath:buildItemTable()
    self.item_table = { {
            text = _("Unread Bookmarks"),
            -- TODO mandatory = get amount somehow
            path = BookmarksPath:new{ browser = self.browser, query = { read_status = "unread", --[[ is_archived = false? ]] } }
        }, {
            text = _("Archived Bookmarks"),
            -- TODO mandatory = get amount somehow
            path = BookmarksPath:new{ browser = self.browser, query = { is_archived = true } }
        }, {
            text = _("Favorite Bookmarks"),
            path = BookmarksPath:new{ browser = self.browser, query = { is_marked = true } }
        }, {
            text = _("All Bookmarks"),
            path = BookmarksPath:new{ browser = self.browser, query = {} }
        }, {
            text = _("Labels"),
            -- TODO get label list
        }, }
    for cid, cname in pairs(self.browser:getCollections()) do
        local citem = {
            text = _(cname),
            collection_id = cid
        }
        table.insert(self.item_table, citem)
    end
    return self.item_table
end

function RootPath:onLeftButtonTap()
    -- TODO search for bookmark
end

function RootPath:onMenuSelect(item)
    local new_path = item.path
    new_path.title = _(new_path.title or item.text)
    self.browser:pushPath(new_path)
    return new_path
end


--------====== BROWSER WINDOW ======--------

local Browser = Menu:extend {
    api = nil,
    settings = nil,
}

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
    self.title = _(self.root_path.title)
    self.subtitle = _(self.root_path.subtitle)

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
    table.insert(self.paths, path)
    self:switchItemTable(path.title, path:getItemTable(), path.itemnumber, nil, path.subtitle)
    return path
end

-- @return A collection id, name table
function Browser:getCollections()
    -- TODO
    return {}
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

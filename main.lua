--[[--
@module koplugin.readeck
]]

local logger = require("logger")

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Event = require("ui/event")
local BD = require("ui/bidi")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FFIUtil = require("ffi/util")
local FileManager = require("apps/filemanager/filemanager")
local InputDialog = require("ui/widget/inputdialog")
local Math = require("optmath")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local ReadHistory = require("readhistory")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = FFIUtil.template


local ReadeckApi = require("readeckapi")
local ReadeckBrowser = require("readeckbrowser")

local defaults = require("defaultsettings")

local Readeck = WidgetContainer:extend {
    name = "readeck",
}

function Readeck:onDispatcherRegisterActions()
    -- TODO do I need actions for anything?
    Dispatcher:registerAction("helloworld_action", {
        category="none",
        event="HelloWorld",
        title=_("Hello World"),
        general=true,
    })
end

function Readeck:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readeck.lua")
    -- TODO remove debug
    logger:setLevel(logger.levels.dbg)

    -- TODO
    --if not self.settings:readSetting("api_token") then
    --    self:authenticate()
    --end
    self.api = ReadeckApi:new({
        url = self.settings:readSetting("server_url", defaults.server_url),
        token = self.settings:readSetting("api_token", defaults.api_token)
    })
    if not self.api then
        logger.err("Readeck error: Couldn't load API.")
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.link then
        self.ui.link:addToExternalLinkDialog("22_readeck", function(this, link_url)
            return {
                text = _("Add to Readeck"),
                callback = function()
                    UIManager:close(this.external_link_dialog)
                    this.ui:handleEvent(Event:new("AddArticleToReadeck", link_url))
                end,
            }
        end)
    end
end

function Readeck:onAddArticleToReadeck(article_url)
    -- TODO option to add labels, custom title, etc.
    if not NetworkMgr:isOnline() then
        -- TODO store article link to upload on next sync
        UIManager:show(InfoMessage:new{
            text = T(_("Not connected to the internet. Couldn't add article:\n%1"), BD.url(article_url)),
            timeout = 1,
        })
        return nil, "Not connected"
    end

    local bookmark_id, err
    local dialog
    dialog = MultiInputDialog:new {
        title = T(_("Create bookmark for %1"), BD.url(article_url)),
        fields = {
            {
                description = _("Bookmark title"),
                text = _(""),
                hint = _("Custom title (optional)"),
            },
            {
                description = _("Labels"),
                text = _(""),
                hint = _("label 1, label 2, ... (optional)"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end
                },
                {
                    text = _("OK"),
                    id = "ok",
                    callback = function()
                        local fields = dialog:getFields()
                        local title = fields[1]
                        local labels_str = fields[2]
                        local labels = {}
                        for label in labels_str:gmatch("[^,%s]+") do
                            table.insert(labels, label)
                        end

                        bookmark_id, err = self.api:bookmarkCreate(article_url, title, labels)

                        UIManager:close(dialog)

                        -- TODO ask if the user wants to open the bookmark now, or favorite it, or archive it
                        UIManager:show(InfoMessage:new {
                            text =
                                bookmark_id
                                and T(_("Bookmark for\n%1\nsuccessfully created."), BD.url(article_url))
                                or T(_("Failed to create bookmark: %1"), err),
                        })
                        return  bookmark_id, err
                    end
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()

    return bookmark_id, err
end

function Readeck:addToMainMenu(menu_items)
    menu_items.readeck = {
        text = _("Readeck"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("DEBUG: Bookmark List"),
                callback = function()
                    local result, err = self.api:bookmarkList()
                    local text = ""
                    if result then
                        for key, value in pairs(result) do
                            text = text .. " " .. key .. ": { " .. value.title .. " }"
                        end
                    else
                        text = err
                    end
                    UIManager:show(InfoMessage:new{
                        text = _(text),
                    })
                end,
            },
            {
                text = _("DEBUG: Add example bookmark"),
                callback = function()
                    local result, err = self.api:bookmarkCreate("https://koreader.rocks/", "", { "Testing", "koplugin" })
                    if result then
                        result = self.api:bookmarkDetails(result)
                        local text = ""
                        for key, value in pairs(result) do
                            text = text .. tostring(key) .. ": " .. tostring(value) .. ",\n"
                        end
                        UIManager:show(InfoMessage:new{
                            text = _(text),
                        })
                        UIManager:show(InfoMessage:new{
                            text = _("Created bookmark " .. tostring(result)),
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = _(err),
                        })
                    end
                end,
            },
            {
                text = _("DEBUG: Download example bookmark"),
                callback = function()
                    local bookmarks = self.api:bookmarkList()
                    local choice = bookmarks[1]

                    local dir = self.settings:readSetting("data_dir", defaults.data_dir)
                    local file = dir .. "/" .. util.getSafeFilename(choice.title .. ".epub", dir)

                    util.makePath(dir)
                    local header, err = self.api:bookmarkExport(file, choice.id)
                    if err then
                        UIManager:show(InfoMessage:new{
                            text = _("Error: " .. err),
                        })
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Downloaded %1 to %2"), choice.title, file)
                        })
                    end
                end
            },
            {
                text = _("Bookmarks"),
                callback = function()
                    self.browser = ReadeckBrowser:new{ api = self.api, settings = self.settings }
                    UIManager:show(self.browser)
                end
            },
        },
    }
end

function Readeck:onHelloWorld()
    local popup = InfoMessage:new{
        text = _("Hello World"),
    }
    UIManager:show(popup)
end

return Readeck

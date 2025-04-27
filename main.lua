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
        title=_"Hello World",
        general=true,
    })
end

function Readeck:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/readeck.lua")
    -- TODO remove debug
    logger:setLevel(logger.levels.dbg)

    self.api = ReadeckApi:new({
        settings = self.settings,
    })

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    if self.ui.link then
        self.ui.link:addToExternalLinkDialog("22_readeck", function(this, link_url)
            return {
                text = _"Add to Readeck",
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
            text = T(_"Not connected to the internet. Couldn't add article:\n%1", BD.url(article_url)),
            timeout = 1,
        })
        return nil, "Not connected"
    end

    local bookmark_id, err
    local dialog
    dialog = MultiInputDialog:new {
        title = T(_"Create bookmark for %1", BD.url(article_url)),
        fields = {
            {
                description = _"Bookmark title",
                text = "",
                hint = _"Custom title (optional)",
            },
            {
                description = _"Labels",
                text = "",
                hint = _"label 1, label 2, ... (optional)",
            },
        },
        buttons = {
            {
                {
                    text = _"Cancel",
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end
                },
                {
                    text = _"OK",
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
                                and T(_"Bookmark for\n%1\nsuccessfully created.", BD.url(article_url))
                                or T(_"Failed to create bookmark: %1", err),
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
        text = _"Readeck",
        sorting_hint = "search",
        sub_item_table = {
            {
                text = _"Settings",
                callback = function()
                    return nil
                end,
                sub_item_table = {
                    {
                        text = _"Configure Readeck server",
                        keep_menu_open = true,
                        callback = function()
                            return self:severConfigDialog()
                        end,
                    }
                },
            }, {
                text = _"Bookmarks",
                callback = function()
                    self.browser = ReadeckBrowser:new{ api = self.api, settings = self.settings }
                    UIManager:show(self.browser)
                end
            },
        },
    }
end

function Readeck:getSetting(setting)
    return self.settings:readSetting(setting, defaults[setting])
end

function Readeck:severConfigDialog()
    local text_info = T(_[[
If you don't want your password being stored in plaintext, you can erase the password field and save the settings after logging in and getting your API token.

You can also edit the configuration file directly in your settings folder:
%1
and then restart KOReader.]], self.settings.file)

    local dialog
    local function saveSettings(fields)
        self.settings:saveSetting("server_url", fields[1]:gsub("/*$", "")) -- remove all trailing slashes
            :saveSetting("username", fields[2])
            :saveSetting("password", fields[3])
            :saveSetting("api_token", fields[4])
            :flush()
    end

    dialog = MultiInputDialog:new{
        title = _"Readeck server settings",
        fields = {
            {
                text = self:getSetting("server_url"),
                hint = _"Server URL"
            }, {
                text = self:getSetting("username"),
                hint = _"Username (if no API Token is given)"
            }, {
                text = self:getSetting("password"),
                text_type = "password",
                hint = _"Password (if no API Token is given)"
            }, {
                text = self:getSetting("api_token"),
                description = _"API Token",
                text_type = "password",
                hint = _"Will be acquired automatically if Username and Password are given."
            },
        },
        buttons = {
            {
                {
                    text = _"Cancel",
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end
                }, {
                    text = _"Info",
                    callback = function()
                        UIManager:show(InfoMessage:new{ text = text_info })
                    end
                }, {
                    text = _"Save",
                    callback = function()
                        saveSettings(dialog:getFields())
                        UIManager:close(dialog)
                    end
                },
            }, {
                {
                    text = _"Sign in (generate API token) and save",
                    callback = function()
                        local fields = dialog:getFields()
                        local token, err = self.api:authenticate(fields[2], fields[3])
                        if not token then
                            UIManager:show(InfoMessage:new{ text = _(err) })
                            return
                        end

                        fields[4] = token
                        UIManager:show(InfoMessage:new{ text = _"Logged in successfully." })

                        saveSettings(fields)
                        UIManager:close(dialog)
                    end
                }
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return Readeck

--[[--
@module koplugin.readeck
]]

local _ = require("gettext")
local logger = require("logger")

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Event = require("ui/event")

local Api = require("readeckapi")

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
    self.api = Api:new({
        url = self.settings:readSetting("server_url", defaults.server_url),
        token = self.settings:readSetting("api_token", defaults.api_token)
    })
    if not self.api then
        logger.err("Readeck error: Couldn't load API.")
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Readeck:addToMainMenu(menu_items) 
    menu_items.readeck = {
        text = _("Readeck"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Bookmark List"),
                callback = function()
                    -- TODO this is just debugging
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
                text = _("Add bookmark"),
                callback = function()
                    -- TODO this is just debugging
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

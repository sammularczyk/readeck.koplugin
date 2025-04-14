--[[--
@module koplugin.readeck
--]]--

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Readeck = WidgetContainer:extend {
    name = "readeck",
}

function Readeck:onDispatcherRegisterActions()
    Dispatcher:registerAction("helloworld_action", {category="none", event="HelloWorld", title=_("Hello World"), general=true,})
end

function Readeck:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function Readeck:addToMainMenu(menu_items)
    menu_items.hello_world = {
        text = _("Readeck"),
        sorting_hint = "tools",
        -- a callback when tapping
        callback = function()
            UIManager:show(InfoMessage:new{
                text = _("Hello, plugin world"),
            })
        end,
    }
end

function Readeck:onHelloWorld()
    local popup = InfoMessage:new{
        text = _("Hello World"),
    }
    UIManager:show(popup)
end

return Readeck

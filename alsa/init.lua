-------------------------------------------------------------------------
-- @author Sébastien Gross &lt;seb•ɱɩɲʋʃ•awesome•ɑƬ•chezwam•ɖɵʈ•org&gt
-- @copyright 2009 Sebastien Gross
-- @release @AWESOME_VERSION@
-------------------------------------------------------------------------

local mouse = mouse
local widget = widget
local wibox = wibox
local screen = screen
local timer = timer

local beautiful = require("beautiful")
local a_util = require("awful.util")
local a_menu = require("awful.menu")
local a_w_progressbar = require("awful.widget.progressbar")
local a_button = require("awful.button")
local a_tooltip = require("awful.tooltip")
local a_w_layout = require("awful.widget.layout")
local lib = {
    misc = require("obvious.lib.misc")
}

local tonumber = tonumber
local setmetatable = setmetatable
local print = print
local ipairs = ipairs
local pairs = pairs
local string = {
    format = string.format,
    }
local table = table
local io = {
    lines = io.lines,
    popen = io.popen
}

--- alsa module for awesome.
-- Allow full access to alsa playback controls.
-- <p>To use it:<br/>
-- <code>alsa = obvious.alsa({})</code><br/>
-- Then attach the obvious.alsa widgets to the status bar:<br/>
-- <code>alsa:get_widgets()</code><br/></p>
-- <p>Usage<br/>
-- <ul>
--      <li>Button 1: launch mixer.</li>
--      <li>Button 2: toggle mute.</li>
--      <li>Button 3: toggle menu.</li>
--      <li>Button 4: raise volume.</li>
--      <li>Button 5: lower volume.</li>
-- </ul>
-- Volume factor is:
-- <ul>
--      <li>No modifier: 1<li>
--      <li><code>Control</code> 5</li>
--      <li><code>Shift</code> 10</li>
-- </ul>
-- If <code>Mod4</code> is held, volume is only changed on channel which mouse
-- hovers.</p>
-- <p>Configuration<br/>
-- Color for minimum volume<br/>
-- <code>theme.obvious_alsa_colors_min = "#007fff"</code><br/>
-- Color for maximum volume<br/>
-- <code>theme.obvious_alsa_colors_max = "#ffffff"</code><br/>
-- Color for active channel<br/>
-- <code>theme.obvious_alsa_colors_active = "#00ff00"</code><br/>
-- Color for muted channel<br/>
-- <code>theme.obvious_alsa_colors_muted = "#ff0000"</code><br/>
-- Progress bar height<br/>
-- <code>theme.obvious_alsa_height = 13</code><br/>
-- Progress bar width<br/>
-- <code>theme.obvious_alsa_width = 5</code><br/>
-- Alsa proc card list<br/>
-- <code>theme.obvious_cards_file = "/proc/asound/cards"</code><br/>
-- Menu width<br/>
-- <code>theme.obvious_alsa_menu_width = 175</code><br/>
-- Widgets update frequency<br/>
-- <code>theme.obvious_timeout = 10</code><br/>
-- Mixer command<br/>
-- <code>theme.obvious_mixer_cmd = "x-terminal-emulator -T Mixer -e alsamixer"</code><br/>
module("obvious.alsa")

-- private data
local data = setmetatable({}, { __mode = 'k' })

--- obvious.alsa object definition.
-- @name obvious.alsa
-- @class table

-- obvious.alsa private data tree
-- Configuration variables:
--      colors: Colors list.
--          min: Color for progressbar min value.
--          max: Color for progressbar min value.
--          active: Color for active channel.
--          muted: Color for muted channel.
--      height: Progress bar height.
--      width: Progress bar width.
--      menu_width: Menu width.
--      cards_file: Alsa cards list file.
--      timeout: timeout for values updates.
--      mixer_cmd: Command to launch mixer.
-- Internal varialbles:
--      widgets: List of widgets
--          pb_left: Left progress bar.
--          pb_right: Right progress bar.
--          spacer: Spacer between progress bars and label.
--          label: Label text widget.
--      cur_card: Current selected card.
--      cur_control: Current selected control.
--      cur_values: Current values.
--          Left: Current values of Left channel.
--              percent: Volume percentage.
--              volume: Volume in dB.
--              status: on, off, unknown.
--          Right: Current values of Left channel.
--              (same as Left channel)
--      card_list: List of all alsa cards and controls.
--          <NUM>: Card number.
--              model: model name.
--              vendor: card vendor.
--              controls: List of card controls.

--- Set default options.
-- @param self A obvious.alsa object.
local function set_default(self)
    -- colors
    data[self].colors = {}
    data[self].colors.min = beautiful.obvious_alsa_colors_min or "#007fff"
    data[self].colors.max = beautiful.obvious_alsa_colors_max or "#ffffff"
    data[self].colors.active = beautiful.obvious_alsa_colors_active or "#00ff00"
    data[self].colors.muted = beautiful.obvious_alsa_colors_muted or "#ff0000"
    -- sizes
    data[self].height = beautiful.obvious_alsa_height or 13
    data[self].width = beautiful.obvious_alsa_width or 5 
    data[self].menu_width = beautiful.obvious_alsa_menu_width or 175
    -- files
    data[self].cards_file = beautiful.cards_file or "/proc/asound/cards"
    -- timeout
    data[self].timeout = beautiful.timeout or 10
    -- command
    data[self].mixer_cmd = beautiful.mixer_cmd or "x-terminal-emulator -T Mixer -e alsamixer"
end

--- Update tooltip text.
-- @param self A obvious.alsa object.
local function set_tt_text(self)
    local c_name = data[self].card_list[data[self].cur_card].model
    local c_controler = data[self].cur_control
    local l, r

    if data[self].cur_values.Left.status == "off" then
        l = "muted"
    else
        l = data[self].cur_values.Left.percent .. "% " ..
            data[self].cur_values.Left.volume .. "dB"
    end
    if data[self].cur_values.Right.status == "off" then
        r = "muted"
    else
        r = data[self].cur_values.Right.percent .. "% " ..
            data[self].cur_values.Right.volume .. "dB"
    end

    ret = " " .. c_name .. " [" .. c_controler .. "] " ..
        "\n Left: " .. l .. " " ..
        "\n Right: " .. r .. " "
    return ret
end

--- Update all values.
-- @param self A obvious.alsa object.
local function update_values(self)
    local fd = io.popen("amixer -c " .. data[self].cur_card ..
        " -- sget " .. data[self].cur_control, "r")
    if not fd then return end
    local line_status = {
        Mono = nil,
        Left = nil,
        Right = nil,
    }
    -- Get control values for all channels
    while true do
        local line = fd:read()
        if not line then break end
        if line:match(".*Mono:") then
            line_status.Mono = line end
        if line:match(".*Left:") then
            line_status.Left = line end
        if line:match(".*Right:") then
            line_status.Right = line end
    end
    fd:close()
    local p, v, s
    for k in pairs(line_status) do 
        if line_status[k] ~= nil then
            p, v, s = line_status[k]:match(".*" .. k .. 
                ":.*%[(%d+)%%%] %[(.+)dB%] %[(.+)%]")
            -- if the channel could not be muted
            if not p then
                p, v = line_status[k]:match(".*" .. k ..
                    ":.*%[(%d+)%%%] %[(.+)dB%]")
                s = "unknown"
            end
            if p then
                -- set label
                -- Mute is applied to both left and right channels
                local c_1 = data[self].colors.active
                if s == "off" then
                    c_1 = data[self].colors.muted
                end
                data[self].widgets.label.text = '<span color="' .. 
                    c_1 .. '">☊</span>'
                -- store current values
                if k == "Mono" or k == "Left" then
                    data[self].cur_values.Left = {
                        percent = tonumber(p),
                        volume = tonumber(v),
                        status = s
                    }
                end
                if k == "Mono" or k == "Right" then
                    data[self].cur_values.Right = {
                        percent = tonumber(p),
                        volume = tonumber(v),
                        status = s
                    }
                end
            end
        end
    end

    -- Update progress bars
    data[self].widgets.pb_left:set_value(data[self].cur_values.Left.percent/100)
    c = lib.misc.calculate_gradient(data[self].colors.min, data[self].colors.max, data[self].cur_values.Left.percent)
    data[self].widgets.pb_left:set_color(c)
    --
    data[self].widgets.pb_right:set_value(data[self].cur_values.Right.percent/100)
    c = lib.misc.calculate_gradient(data[self].colors.min, data[self].colors.max, data[self].cur_values.Right.percent)
    data[self].widgets.pb_right:set_color(c)

    -- Update tooltip
    data[self].tooltip:set_text(set_tt_text(self))
end

--- Raise volume of current controler for current card.
-- @param self A obvious.alsa object.
-- @param v Volume amont.
local function raise(self, l, r)
    a_util.spawn("amixer -q -c " .. data[self].cur_card .. " -- sset '" ..
        data[self].cur_control .."' " .. l .. "," .. r , false)
    data[self].update_values()
end

--- Lower volume of current controler for current card.
-- @param self A obvious.alsa object.
-- @param v Volume amont.
local function lower(self, l, r)
    raise(self, l, r)
end

--- Toggle mute of current controler for current card.
-- @param self A obvious.alsa object.
local function mute(self)
    a_util.spawn("amixer -q -c " .. data[self].cur_card .. " -- sset '" ..
      data[self].cur_control .. "' toggle", false)
    data[self].update_values()
end

--- Set the default alsa contoler.
-- @param self A obvious.alsa object.
-- @param card The card ID.
-- @param control The contoler name.
local function set_contol(self, card, control)
    data[self].cur_card = card
    data[self].cur_control = control
    data[self].update_values()
end

--- Read the cards information and build menu.
-- @param self A obvious.alsa object.
local function read_cards(self)
    if not a_util.file_readable(data[self].cards_file) then return end
    data[self].card_list = {}
    local c_menu = { cards = {} }
    -- Get all alsa cards
    for line in io.lines(data[self].cards_file) do
        local id, vendor, model = line:match("^%s*(%d+)%s*%[(.-)%s*%]:%s*(.-)%s*$")
        if not id then break end
        id = tonumber(id)
        data[self].card_list[id] = {
            vendor = vendor,
            model = model,
            controls = {}}
        c_menu[id] = {}
        -- List all card controls
        local fd = io.popen("amixer -c " .. id .. " scontrols", "r")
        while true do
            local control = fd:read()
            if not control then break end
            local name, cid = control:match("^.*'%s*([^']+)%s*',(%d+).*$")
            if not name then break end
            cid = tonumber(cid)
            local fd_c = io.popen("amixer -c " .. id .. " sget '" .. 
                name .. "," .. cid .."'", "r")
            -- skip non playback controls
            local is_pb = false
            while true do
                local c_attr = fd_c:read()
                if not c_attr then break end
                if c_attr:match("%spvolume") then
                    is_pb = true
                    break
                end
            end
            fd_c:close()
            -- create menu entry for playback controls
            if is_pb then
                if not data[self].card_list[id].controls[name] then
                    data[self].card_list[id].controls[name] = { cid }
                else
                    table.insert(data[self].card_list[id].controls[name], cid)
                end
                local display = name
                if cid > 0 then display = display .. " " .. cid end
                table.insert(c_menu[id], { display, function()
                        set_contol(self, id, name .. "," .. cid)
                    end} )
            end
        end
        fd:close()
        table.insert(c_menu.cards, { model, c_menu[id]})
    end
    return c_menu.cards
end

--- Return obvious.alsa widget list suitable for wibox.widgets.
-- @param self A obvious.alsa object.
-- @return List of wigets.
local function get_widgets(self)
    return {
        data[self].widgets.pb_right.widget,
        data[self].widgets.spacer,
        data[self].widgets.pb_left.widget,
        data[self].widgets.spacer,
        data[self].widgets.label,
        layout = a_w_layout.horizontal.rightleft
    }
end

--- Create a new obvious.alsa object
-- @param args Arguments for alsa creation may containt:<br/>
-- <code>card</code> The default card (default: 0).<br/>
-- <code>control</code> The default card (default: Master,0).<br/>
-- @return The created obvious.alsa.
local function new(args)
    args = args or { }
    local self = { }

    -- private data
    data[self] = {
        widgets = {
            pb_left = a_w_progressbar.new({
                layout = a_w_layout.horizontal.rightleft }),
            pb_right = a_w_progressbar.new({
                layout = a_w_layout.horizontal.rightleft }),
            label = widget({ type = "textbox", name = "alsa_label",}),
            spacer = widget({type = "textbox",name = "spacer"}),
        },
        -- card 0 and control Master,0 should be present on almost all alsa
        -- cards.
        cur_card = args.cards or 0,
        cur_control = args.control or 'Master,0',
        cur_values = {
            Left = {},
            Right = {},
        },
    }
    -- Load default values
    set_default(self)
    -- Setup timer / tooltip
    data[self].timer = timer { timeout = data[self].timeout }
    data[self].tooltip = a_tooltip({
            timer_function = function() return set_tt_text(self) end,
            timeout = data[self].timeout
        })
    -- Setup progress bars
    for _, i in ipairs({
        data[self].widgets.pb_left,
        data[self].widgets.pb_right}) do
        i:set_vertical(true)
        i:set_height(data[self].height)
        i:set_width(data[self].width)
    end
    -- 1px should be enough to separate progress bars
    data[self].widgets.spacer.width = 1
    

    -- setup menu items
    local menu = a_menu.new({
        id = "alsa",
        width = data[self].menu_width,
        items = read_cards(self), 
    })

    -- Setup mouse buttons and tooltip
    for _, i in ipairs({
        data[self].widgets.pb_left.widget,
        data[self].widgets.pb_right.widget,
        data[self].widgets.spacer,
        data[self].widgets.label}) do
        i:buttons(a_util.table.join(
            a_button({}, 1, function() a_util.spawn(data[self].mixer_cmd, false) end),
            a_button({}, 3, function() menu:toggle() end),
            a_button({}, 2, function() mute(self) end),
            a_button({}, 4, function() raise(self, "1+", "1+") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4"}, 4, function() lower(self, "1+", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4"}, 4, function() lower(self, "0+", "1+") end) or nil,
            a_button({}, 5, function() lower(self, "1-", "1-") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4"}, 5, function() lower(self, "1-", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4"}, 5, function() lower(self, "0+", "1-") end) or nil,
            a_button({"Control"}, 4, function() raise(self, "5+", "5+") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4", "Control"}, 4, function() lower(self, "5+", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4", "Control"}, 4, function() lower(self, "0+", "5+") end) or nil,
            a_button({"Control"}, 5, function() lower(self, "5-", "5-") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4", "Control"}, 5, function() lower(self, "5-", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4", "Control"}, 5, function() lower(self, "0+", "5-") end) or nil,
            a_button({"Shift"}, 4, function() raise(self, "10+", "10+") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4", "Shift"}, 4, function() lower(self, "10+", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4", "Shift"}, 4, function() lower(self, "0+", "10+") end) or nil,
            a_button({"Shift"}, 5, function() lower(self, "10-", "10-") end),
            i == data[self].widgets.pb_left.widget and a_button({"Mod4", "Shift"}, 5, function() lower(self, "10-", "0+") end) or nil,
            i == data[self].widgets.pb_right.widget and a_button({"Mod4", "Shift"}, 5, function() lower(self, "0+", "10-") end) or nil
        ))
        data[self].tooltip:add_to_object(i)
    end

    -- update values
    data[self].update_values = function() update_values(self) end
    data[self].update_values()

    -- make sure widget is up to date
    data[self].timer:add_signal("timeout", function() data[self].update_values() end)
    data[self].timer:start()

    -- Export functions
    self.get_widgets = get_widgets
    return self
end

setmetatable(_M, { __call = function(_, ...) return new(...) end })

-- vim: ft=lua:et:sw=4:ts=4:sts=4:enc=utf-8:tw=78

------------------------------------
-- Author: Gregor Best            --
-- Copyright 2009 Gregor Best     --
-- Copyright 2009 Sébastien Gross --
------------------------------------

local tonumber = tonumber
local string = {
    format = string.format
}

module("obvious.lib.misc")

--- Calculate gradient color between 2 RGB colors.
-- @param a First color string in #RRGGBB format.
-- @param b Second color string in #RRGGBB format.
-- @param factor Percentage from first color (0-100).
-- @return Color string in #RRGGBB.
function calculate_gradient(a, b, factor)
    -- obvious computations
    if factor >= 100 then return b end
    if factor <= 0 then return a end
    -- Make sure both a&b are in #RRGGBB format
    a = string.format("%.6x", tonumber(a:sub(2), 16))
    b = string.format("%.6x", tonumber(b:sub(2), 16))
    local b_a = {
        tonumber(b:sub(1,2), 16),
        tonumber(b:sub(3,4), 16),
        tonumber(b:sub(5,6), 16), }
    local a_a = {
        tonumber(a:sub(1,2), 16),
        tonumber(a:sub(3,4), 16),
        tonumber(a:sub(5,6), 16), }
    local f = factor / 100
    local fb = 1 - f
    local g = {
        a_a[1]*fb + b_a[1]*f,
        a_a[2]*fb + b_a[2]*f,
        a_a[3]*fb + b_a[3]*f,
    }
    return string.format("#%.2x%.2x%.2x", g[1], g[2], g[3])
end

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=4:softtabstop=4:encoding=utf-8:textwidth=80

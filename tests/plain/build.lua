--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]
if lfs.currentdir():match("lua%-widow%-control$") then
    prefix = "./"
else
    prefix = "../../"
end

dofile(prefix .. "tests/test-config.lua")

local common = abspath(prefix .. "tests/common")

-- Plain
specialformats = { plain = {
    luatex = {
        binary = "luatex",
        format = "luatex"
    },
    -- luametatex = {
    --     binary = common .. "/luametatex-wrapper",
    --     format = "luametaplain"
    -- },
}}

checkengines = { "luatex", --[["luametatex"]] }
checkformat = "plain"
testfiledir = prefix .. "tests/plain"

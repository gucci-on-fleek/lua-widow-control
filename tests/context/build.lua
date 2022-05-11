--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]
--[[ Temporarily broken
-- Common
module = "lua-widow-control"

local prefix
if lfs.currentdir():match("lua%-widow%-control$") then
    prefix = "./"
else
    prefix = "../../"
end

testsuppdir = prefix .. "tests/common"
tdsdirs = { [prefix .. "texmf"] = "." }
maxprintline = 10000

-- ConTeXt
checkengines = { "luatex" }
checkformat = "context"
testfiledir = prefix .. "tests/context"
]]

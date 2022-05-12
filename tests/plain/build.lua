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

-- Plain
checkengines = { "luatex" }
checkformat = "tex"
testfiledir = prefix .. "tests/plain"

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

-- LaTeX
specialformats = { lualatex = {
    lualatex = {
        binary = "lualatex",
        format = ""
    },
    ["lualatex-dev"] = {
        binary = "lualatex-dev",
        format = ""
    },
}}

checkengines = { "lualatex", "lualatex-dev" }
checkformat = "lualatex"
testfiledir = prefix .. "tests/latex"

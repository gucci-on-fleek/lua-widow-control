--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]
module = "lua-widow-control"

testsuppdir = prefix .. "tests/common"
tdsdirs = { [prefix .. "texmf"] = "." }
maxprintline = 10000

test_types = {
    pdftotext = {
        test = ".lvtext",
        generated = ".pdf",
        reference = ".tltext",
        rewrite = function(source, result)
            os.execute(
                "pdftotext -bbox-layout " .. source .. " -" ..
                "| xsltproc --novalid --output " .. result ..
                " " .. prefix .. "tests/transform.xslt -"
            )
        end,
    },
}

test_order = { "pdftotext", "log" }

if options.target == "check" then
    require "l3build-variables.lua"
end

--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]
-- Initialization
module = "lua-widow-control"

local orig_targets = target_list
target_list = {}

-- Tagging
target_list.tag = orig_targets.tag
tagfiles = { "source/*.*", "docs/**/*.*", "README.md" }

function update_tag(name, content, version, date)
    if not version then
        print("No version provided. Exiting")
        os.exit(1)
    end

    if name:match("%.pdf$") then
        return content
    end

    content = content:gsub(
        "(%d%.%d%.%d)([^\n]*)%%%%version",
        version .. "%2%%%%version"
    ):gsub(
        "(%d%d%d%d%-%d%d%-%d%d)([^\n]*)%%%%dashdate",
        date .. "%2%%%%dashdate"
    ):gsub(
        "(%d%d%d%d/%d%d/%d%d)([^\n]*)%%%%slashdate",
        date:gsub("-", "/") .. "%2%%%%slashdate"
    )

    return content
end

-- Bundle
target_list.bundle = {}
target_list.bundle.desc = "Creates the package zipfiles"

function target_list.bundle.func()
    local newzip = require "l3build-zip"
    local tdszipname = module .. ".tds.zip"

    local tdszip = newzip("./" .. tdszipname)
    local ctanzip = newzip("./" .. module .. ".ctan.zip")

    for _, path in ipairs(tree("texmf", "**/*.*")) do
        tdszip:add(
            path.cwd, -- outer
            path.src:sub(3), -- inner
            path.src:match("pdf") -- binary
        )
        ctanzip:add(
            path.cwd, -- outer
            module .. "/" .. basename(path.src), -- inner
            path.src:match("pdf") -- binary
        )
    end

    tdszip:close()

    ctanzip:add("./" .. tdszipname, tdszipname, true)
    ctanzip:close()

    return 0
end

-- Documentation
target_list.doc = {}
target_list.doc.desc = "Builds the documentation"

local l3_run = run
local function run(cwd, cmd)
    local error = l3_run(cwd, cmd)
    if error ~= 0 then
        print(("\n"):rep(5))
        print("Error code " .. error .. " for command " .. cmd .. ".")
        print("\n")
        os.exit(error)
    end
end

function target_list.doc.func()
    mkdir("./docs/manual/tmp")
    run("./docs/manual", "context  lwc-manual")

    run("./docs/articles", "context  tb133chernoff-widows-figure.ctx")
    run("./docs/articles", "lualatex tb133chernoff-widows.ltx")
    run("./docs/articles", "bibtex tb133chernoff-widows")
    run("./docs/articles", "lualatex tb133chernoff-widows.ltx")
    run("./docs/articles", "lualatex tb133chernoff-widows.ltx")

    run("./docs/articles", "lualatex tb135chernoff-lwc.ltx")
    run("./docs/articles", "pdfunite tb133chernoff-widows.pdf tb135chernoff-lwc.pdf /dev/stdout | sponge tb133chernoff-widows.pdf")

    run("./docs/articles", "context  lwc-zpravodaj-figure.ctx")
    run("./docs/articles", "lualatex lwc-zpravodaj.ltx")
    run("./docs/articles", "biber lwc-zpravodaj")
    run("./docs/articles", "lualatex lwc-zpravodaj.ltx")
    run("./docs/articles", "lualatex lwc-zpravodaj.ltx")

    return error
end

-- Tests
target_list.check = orig_targets.check
target_list.save = orig_targets.save

os.setenv("diffexe", "git diff --no-index -w --word-diff --text")

checkconfigs = {}
for _, path in ipairs(tree(".", "./tests/*/build.lua")) do
    checkconfigs[#checkconfigs+1] = path.src
end

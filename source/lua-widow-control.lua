--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]

lwc = {}
lwc.name = "lua-widow-control"

--[[
    \lwc/ is intended to be format-agonistic. It only runs on Lua\TeX{},
    but there are still some slight differences between formats. Here, we
    detect the format name then set some flags for later processing.
  ]]
local format = tex.formatname
local context, latex, plain

if format:find('cont') then -- cont-en, cont-fr, cont-nl, ...
    context = true
elseif format:find('latex') then -- lualatex, lualatex-dev, ...
    latex = true
elseif format == 'luatex' then -- Plain
    plain = true
end

--[[
    Save some local copies of the node library to reduce table lookups.
    This is probably a useless micro-optimization, but it can't hurt.
  ]]
local last = node.slide
local copy = node.copy_list
local par_id = node.id("par")
local glue_id = node.id("glue")
local set_attribute = node.set_attribute
local has_attribute = node.has_attribute
local flush_list = node.flush_list or node.flushlist
local free = node.free
local min_col_width = tex.sp("25em")
local maxdimen = 1073741823 -- \\maxdimen in sp

--[[
    This error is raised in the following circumstances:
      - When the user manually loads the Lua module without loading Lua\TeX{}Base
      - When the package is used with an unsupported format
    Both of these are pretty unlikely, but it can't hurt to check.
  ]]
assert(context or luatexbase, [[
    
    This module requires a supported callback library. Please
    follow the following format-dependant instructions:
      - LaTeX: Use a version built after 2015-01-01, or include
              `\usepackage{luatexbase}' before loading this module.
      - Plain: Include `\input ltluatex' before loading this module.
      - ConTeXt: Use LuaMetaTeX/Mark XL.
]])

--[[
    Package/module initialization
  ]]
local warning, info, attribute, contrib_head, stretch_order, pagenum

if context then
    warning = logs.reporter("module", lwc.name)
    info = logs.reporter("module", lwc.name)
    attribute = attributes.public(lwc.name)
    contrib_head = 'contributehead' -- For \LuaMetaTeX{}
    stretch_order = "stretchorder"
    pagenum = function() return tex.count["realpageno"] end
elseif plain or latex then
    luatexbase.provides_module {
        name = lwc.name,
        date = "2022/02/15", --%%date
        version = "1.1.5", --%%version
        description = [[

    This module provides a LuaTeX-based solution to prevent
    widows and orphans from appearing in a document. It does
    so by increasing or decreasing the lengths of previous
    paragraphs.
        ]],
    }
    warning = function(str) luatexbase.module_warning(lwc.name, str) end
    info = function(str) luatexbase.module_info(lwc.name, str) end
    attribute = luatexbase.new_attribute(lwc.name)
    contrib_head = 'contrib_head' -- For \LuaTeX{}
    stretch_order = "stretch_order"
    pagenum = function() return tex.count[0] end
else -- uh oh
    error [[
        Unsupported format.

        Please use (Lua)LaTeX, Plain (Lua)TeX, or ConTeXt (MKXL/LMTX)
    ]]
end

local paragraphs = {} -- List to hold the alternate paragraph versions

if tex.brokenpenalty ~= 0 then
    warning [[
\brokenpenalty is set to a non-zero value.
This may prevent lua-widow-control from
properly functioning.
]]
end

--[[
    Function definitions
  ]]

--- Create a table of functions to enable or disable a given callback
--- @param t table Parameters of the callback to create
---     callback: str = The \LuaTeX{} callback name
---     func: function = The function to call
---     name: str = The name/ID of the callback
---     category: str = The category for a \ConTeXt{} "Action"
---     position: str = The "position" for a \ConTeXt{} "Action"
---     lowlevel: bool = If we should use a lowlevel \LuaTeX{} callback instead of a
---                      \ConTeXt{} "Action"
--- @return table t Enablers/Disablers for the callback
---     enable: function = Enable the callback
---     disable: function = Disable the callback
local function register_callback(t)
    if plain or latex then -- Both use \LuaTeX{}Base for callbacks
        return {
            enable = function()
                luatexbase.add_to_callback(t.callback, t.func, t.name)
            end,
            disable = function()
                luatexbase.remove_from_callback(t.callback, t.name)
            end,
        }
    elseif context and not t.lowlevel then
        return {
            -- Register the callback when the table is created,
            -- but activate it when `enable()` is called.
            enable = nodes.tasks.appendaction(t.category, t.position, "lwc." .. t.name)
                or function()
                    nodes.tasks.enableaction(t.category, "lwc." .. t.name)
                end,
            disable = function()
                nodes.tasks.disableaction(t.category, "lwc." .. t.name)
            end,
        }
    elseif context and t.lowlevel then
        --[[
            Some of the callbacks in \ConTeXt{} have no associated "actions". Unlike
            with \LuaTeX{}base, \ConTeXt{} leaves some \LuaTeX{} callbacks unregistered
            and unfrozen. Because of this, we need to register some callbacks at the
            engine level. This is fragile though, because a future \ConTeXt{} update
            may decide to register one of these functions, in which case 
            \lwc/ will crash with a cryptic error message.
          ]]
        return {
            enable = function() callback.register(t.callback, t.func) end,
            disable = function() callback.register(t.callback, nil) end,
        }
    end
end

--- Saves each paragraph, but lengthened by 1 line
function lwc.save_paragraphs(head)
    -- Prevent the "underfull hbox" warnings when we store a potential paragraph
    lwc.callbacks.disable_box_warnings.enable()

    -- Ensure that we were actually given a par (only under \ConTeXt{} for some reason)
    if head.id ~= par_id and context then
        return head
    end

    -- We need to return the unmodified head at the end, so we make a copy here
    local new_head = copy(head)

    -- Prevent ultra-short last lines (\TeX{}Book p. 104), except with narrow columns
    local parfillskip = last(new_head)
    if parfillskip.id == glue_id and tex.hsize > min_col_width then
        parfillskip[stretch_order] = 0
        parfillskip.stretch = 0.8 * tex.hsize -- Last line must be at least 20% long
    end

    -- Break the paragraph 1 line longer than natural
    local long_node, long_info = tex.linebreak(new_head, {
        looseness = 1,
        emergencystretch = tex.dimen.lwcemergencystretch,
    })

    -- Break the natural paragraph so we know how long it was
    local natural_node, natural_info = tex.linebreak(copy(head))
    flush_list(natural_node)

    lwc.callbacks.disable_box_warnings.disable()

    -- If we can't lengthen the paragraph, assign a \emph{very} large demerit value
    local long_demerits
    if long_info.prevgraf == natural_info.prevgraf then
        long_demerits = maxdimen
    else
        long_demerits = long_info.demerits
    end

    -- Offset the accumulated \\prevdepth
    local prevdepth = node.new("glue")
    prevdepth.width = natural_info.prevdepth - long_info.prevdepth
    last(long_node).next = prevdepth

    table.insert(paragraphs, { demerits = long_demerits, node = long_node })

    -- \LuaMetaTeX{} crashes if we return `true`
    return head
end

--- Tags the beginning and the end of each paragraph as it is added to the page.
---
--- We add an attribute to the first and last node of each paragraph. The ID is
--- some arbitrary number for \lwc/, and the value corresponds to the
--- paragraphs index, which is negated for the end of the paragraph.
function lwc.mark_paragraphs(head)
    set_attribute(head, attribute, #paragraphs)
    set_attribute(last(head), attribute, -1 * #paragraphs)

    return head
end

--- A "safe" version of the last/slide function.
---
--- Sometimes the node list can form a loop. Since there is no last element
--- of a looped linked-list, the `last()` function will never terminate. This
--- function provides a "safe" version of the `last()` function that will break
--- the loop at the end if the list is circular.
local function safe_last(head)
    local ids = {}
    local prev

    while head.next do
        local id = node.is_node(head) -- Returns the internal node id

        if ids[id] then
            warning [[Circular node list detected!
This should never happen. I'll try and recover, but your output may be 
corrupted. As a workaround, disable lua-widow-control for the
affected paragraph or change the page breaks in your document.]]

            prev.next = nil
            return prev
        end

        ids[id] = true
        head.prev = prev
        prev = head
        head = head.next
    end

    return head
end

--- Remove the widows and orphans from the page, just after the output routine.
---
--- This function holds the "meat" of the module. It is called just after the
--- end of the output routine, before the page is shipped out. If the output
--- penalty indicates that the page was broken at a widow or an orphan, we
--- replace one paragraph with the same paragraph, but lengthened by one line.
--- Then, we can push the bottom line of the page to the next page.
function lwc.remove_widows(head)
    local penalty = tex.outputpenalty - tex.interlinepenalty

    --[[
        We only need to process pages that have orphans or widows. If `paragraphs`
        is empty, then there is nothing that we can do.

        The list of penalties is from:
        https://tug.org/TUGboat/tb39-3/tb123mitt-widows-code.pdf#subsection.0.2.1
      ]]
    if (penalty == tex.widowpenalty or
        penalty == tex.displaywidowpenalty or
        penalty == tex.clubpenalty or
        penalty == tex.clubpenalty + tex.widowpenalty or
        penalty == tex.clubpenalty + tex.displaywidowpenalty) and
        #paragraphs >= 1 then
    else
        return head
    end

    info("Widow/orphan detected. Attempting to remove.")

    local head_save = head -- Save the start of the `head` linked-list

    --[[
        Find the paragraph on the page with the minimum penalty.

        This would be a 1-liner in Python or JavaScript, but Lua is pretty low-level,
        so there's quite a bit of code here.
      ]]
    local paragraph_index = 1
    local minimum_demerits = paragraphs[paragraph_index].demerits

    -- We find the current "best" replacement, then free the unused ones
    for i, paragraph in pairs(paragraphs) do
        if paragraph.demerits < minimum_demerits and i <= #paragraphs - 1 then
            flush_list(paragraphs[paragraph_index].node)
            paragraphs[paragraph_index].node = nil
            paragraph_index, minimum_demerits = i, paragraph.demerits
        elseif i > 1 then
            -- Not sure why `i > 1` is required?
            flush_list(paragraph.node)
            paragraph.node = nil
        end
    end

    local target_node = paragraphs[paragraph_index].node
    local clear_flag = false

    -- Loop through all of the nodes on the page
    while head do
        -- Insert the start of the replacement paragraph
        if has_attribute(head, attribute, paragraph_index) then
            safe_last(target_node) -- Remove any loops

            head.prev.next = target_node
            clear_flag = true
        end

        -- Insert the end of the replacement paragraph
        if has_attribute(head, attribute, -1 * paragraph_index) then
            safe_last(target_node).next = head.next
            clear_flag = false
        end

        -- Start of final paragraph
        if has_attribute(head, attribute, #paragraphs) then
            local last_line = copy(last(head))

            last(last_line).next = copy(tex.lists[contrib_head])

            last(head).prev.prev.next = nil
            -- Move the last line to the next page
            tex.lists[contrib_head] = last_line
            info(
            "Widow/orphan successfully removed at paragraph "
                .. paragraph_index
                .. " on page "
                .. pagenum()
                .. "."
            )
        end

        if clear_flag then
            head = free(head)
        else
            head = head.next
        end
    end

    paragraphs = {} -- Clear paragraphs array at the end of the page

    return head_save
end

-- Add all of the callbacks
lwc.callbacks = {
    disable_box_warnings = register_callback({
        callback = "hpack_quality",
        func = function() end,
        name = "disable_box_warnings",
        lowlevel = true,
    }),
    remove_widows = register_callback({
        callback = "pre_output_filter",
        func = lwc.remove_widows,
        name = "remove_widows",
        lowlevel = true,
    }),
    save_paragraphs = register_callback({
        callback = "pre_linebreak_filter",
        func = lwc.save_paragraphs,
        name = "save_paragraphs",
        category = "processors",
        position = "after",
    }),
    mark_paragraphs = register_callback({
        callback = "post_linebreak_filter",
        func = lwc.mark_paragraphs,
        name = "mark_paragraphs",
        category = "finalizers",
        position = "after",
    }),
}


local enabled = false
function lwc.enable_callbacks()
    if not enabled then
        lwc.callbacks.remove_widows.enable()
        lwc.callbacks.save_paragraphs.enable()
        lwc.callbacks.mark_paragraphs.enable()

        enabled = true
    else
        warning("Already enabled")
    end
end

function lwc.disable_callbacks()
    if enabled then
        lwc.callbacks.save_paragraphs.disable()
        lwc.callbacks.mark_paragraphs.disable()
        --[[
            We do \emph{not} disable `remove_widows` callback, since we still want
            to expand any of the previously-saved paragraphs if we hit an orphan
            or a widow.
          ]]

        enabled = false
    else
        warning("Already disabled")
    end
end

function lwc.if_lwc_enabled()
    if enabled then
        tex.sprint("\\iftrue")
    else
        tex.sprint("\\iffalse")
    end
end

return lwc

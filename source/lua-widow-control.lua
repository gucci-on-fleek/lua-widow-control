--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]

--- Tell the linter about node attributes
--- @class node
--- @field prev node
--- @field next node
--- @field id integer
--- @field subtype integer
--- @field penalty integer
--- @field height integer
--- @field depth integer

-- Set some default variables
lwc = lwc or {}
lwc.name = "lua-widow-control"
lwc.nobreak_behaviour = "keep"

-- Locals for `debug_print`
local write_nl = texio.write_nl
local string_rep = string.rep
local write_log
if status.luatex_engine == "luametatex" then
    write_log = "logfile"
else
    write_log = "log"
end

--- Prints debugging messages to the log, only if `debug` is set to `true`.
--- @param title string The "title" to use
--- @param text string? The "content" to print
--- @return nil
local function debug_print(title, text)
    if not lwc.debug then return end

    -- The number of spaces we need
    local filler = 15 - #title

    if text then
        write_nl(write_log, "LWC (" .. title .. string_rep(" ", filler) .. "): " .. text)
    else
        write_nl(write_log, "LWC: " .. string_rep(" ", 18) .. title)
    end
end

--[[
    \lwc/ is intended to be format-agonistic. It only runs on Lua\TeX{},
    but there are still some slight differences between formats. Here, we
    detect the format name then set some flags for later processing.
  ]]
local format = tex.formatname
local context, latex, plain, optex, lmtx

if format:find("cont") then -- cont-en, cont-fr, cont-nl, ...
    context = true
    if status.luatex_engine == "luametatex" then
        lmtx = true
    end
elseif format:find("latex") then -- lualatex, lualatex-dev, ...
    latex = true
elseif format == "luatex" or format == "luahbtex" then -- Plain
    plain = true
elseif format:find("optex") then -- OpTeX
    optex = true
end

--[[
    Save some local copies of the node library to reduce table lookups.
    This is probably a useless micro-optimization, but it can't hurt.
  ]]
-- Node ID's
local baselineskip_subid = 2
local glue_id = node.id("glue")
local glyph_id = node.id("glyph")
local hlist_id = node.id("hlist")
local line_subid = 1
local linebreakpenalty_subid = 1
local par_id = node.id("par") or node.id("local_par")
local penalty_id = node.id("penalty")

-- Local versions of globals
local copy = node.copy_list or node.copylist
local find_attribute = node.find_attribute or node.findattribute
local flush_list = node.flush_list or node.flushlist
local free = node.free
local getattribute = node.get_attribute or node.getattribute
local insert_token = token.put_next or token.putnext
local last = node.slide
local new_node = node.new
local node_id = node.is_node or node.isnode
local set_attribute = node.set_attribute or node.setattribute
local string_char = string.char
local traverse = node.traverse
local traverseid = node.traverse_id or node.traverseid

-- Misc. Constants
local iffalse = token.create("iffalse")
local iftrue = token.create("iftrue")
local INFINITY = 10000
local min_col_width = tex.sp("250pt")
local SINGLE_LINE = 50
local PAGE_MULTIPLE = 100

--[[
    Package/module initialization
  ]]
local attribute,
      contrib_head,
      emergencystretch,
      info,
      max_cost,
      pagenum,
      stretch_order,
      warning

if lmtx then
    -- LMTX has removed underscores from most of the Lua parts
    debug_print("LMTX")
    contrib_head = "contributehead"
    stretch_order = "stretchorder"
else
    contrib_head = "contrib_head"
    stretch_order = "stretch_order"
end

if context then
    debug_print("ConTeXt")

    warning = logs.reporter(lwc.name, "warning")
    local _info = logs.reporter(lwc.name, "info")
    info = function (text)
        logs.pushtarget("logfile")
        _info(text)
        logs.poptarget()
    end
    attribute = attributes.public(lwc.name)
    pagenum = function() return tex.count["realpageno"] end

    -- Dimen names
    emergencystretch = "lwc_emergency_stretch"
    max_cost = "lwc_max_cost"
elseif plain or latex or optex then
    pagenum = function() return tex.count[0] end

    -- Dimen names
    if tex.isdimen("g__lwc_emergencystretch_dim") then
        emergencystretch = "g__lwc_emergencystretch_dim"
        max_cost = "g__lwc_maxcost_int"
    else
        emergencystretch = "lwcemergencystretch"
        max_cost = "lwcmaxcost"
    end

    if plain or latex then
        debug_print("Plain/LaTeX")
        luatexbase.provides_module {
            name = lwc.name,
            date = "2022/05/14", --%%dashdate
            version = "2.1.0", --%%version
            description = [[

This module provides a LuaTeX-based solution to prevent
widows and orphans from appearing in a document. It does
so by increasing or decreasing the lengths of previous
paragraphs.]],
        }
        warning = function(str) luatexbase.module_warning(lwc.name, str) end
        info = function(str) luatexbase.module_info(lwc.name, str) end
        attribute = luatexbase.new_attribute(lwc.name)
    elseif optex then
        debug_print("OpTeX")

        warning = function(str) write_nl(lwc.name .. " Warning: " .. str) end
        info = function(str) write_nl("log", lwc.name .. " Info: " .. str) end
        attribute = alloc.new_attribute(lwc.name)
    end
else -- This shouldn't ever happen
    error [[Unsupported format.

Please use LaTeX, Plain TeX, ConTeXt or OpTeX.]]
end

local paragraphs = {} -- List to hold the alternate paragraph versions

--- Gets the current paragraph and page locations
--- @return string
local function get_location()
    return "At " .. pagenum() .. "/" .. #paragraphs
end

--[[
    Function definitions
  ]]

--- Prints the initial glyphs and glue of an hlist
--- @param head node
--- @return nil
local function get_chars(head)
    if not lwc.debug then return end

    local chars = ""
    for n in traverse(head) do
        if n.id == glyph_id then
            if n.char < 127 then -- Only ASCII
                chars = chars .. string_char(n.char)
            else
                chars = chars .. "#"  -- Replacement for an unknown glyph
            end
        elseif n.id == glue_id then
            chars = chars .. " " -- Any glue goes to a space
        end
        if #chars > 25 then
            break
        end
    end

    debug_print(get_location(), chars)
end

--- The "cost function" to use. See the manual.
--- @param demerits number The demerits of the broken paragraph
--- @param lines number The number of lines in the broken paragraph
--- @return number The cost of the broken paragraph
function lwc.paragraph_cost(demerits, lines)
    return demerits / math.sqrt(lines)
end

--- Checks if the ConTeXt "grid snapping" is active
--- @return boolean
local function grid_mode_enabled()
    -- Compare the token "mode" to see if `\\ifgridsnapping` is `\\iftrue`
    return token.create("ifgridsnapping").mode == iftrue.mode
end

--- Gets the next node of a type/subtype in a node list
--- @param head node The head of the node list
--- @param id number The node type
--- @param args table?
---     subtype: number = The node subtype
---     reverse: bool = Whether we should iterate backwards
--- @return node
local function next_of_type(head, id, args)
    args = args or {}
    if lmtx or not args.reverse then
        for n, subtype in traverseid(id, head, args.reverse) do
            if (subtype == args.subtype) or (args.subtype == nil) then
                return n
            end
        end
    else -- Only LMTX has the built-in backwards traverser
        while head do
            if head.id == id and
               (head.subtype == args.subtype or args.subtype == nil)
            then
                return head
            end
            head = head.prev
        end
    end
end

--- Saves each paragraph, but lengthened by 1 line
---
--- Called by the `pre_linebreak_filter` callback
---
--- @param head node
--- @return node
function lwc.save_paragraphs(head)
    if (head.id ~= par_id and context) or -- Ensure that we were actually given a par
        status.output_active -- Don't run during the output routine
    then
        return head
    end

    -- Prevent the "underfull hbox" warnings when we store a potential paragraph
    local renable_box_warnings
    if (context or optex) or
       #luatexbase.callback_descriptions("hpack_quality") == 0
    then -- See #18 and michal-h21/linebreaker#3
        renable_box_warnings = true
        lwc.callbacks.disable_box_warnings.enable()
    end

    -- We need to return the unmodified head at the end, so we make a copy here
    local new_head = copy(head)

    -- Prevent ultra-short last lines (\TeX{}Book p. 104), except with narrow columns
    -- Equivalent to \\parfillskip=0pt plus 0.8\\hsize
    local parfillskip
    if lmtx or last(new_head).id ~= glue_id then
        -- LMTX does not automatically add the \\parfillskip glue
        parfillskip = new_node("glue", "parfillskip")
    else
        parfillskip = last(new_head)
    end

    if tex.hsize > min_col_width then
        parfillskip[stretch_order] = 0
        parfillskip.stretch = 0.8 * tex.hsize -- Last line must be at least 20% long
    end

    if lmtx or last(new_head).id ~= glue_id then
        last(new_head).next = parfillskip
    end

    -- Break the paragraph 1 line longer than natural
    local long_node, long_info = tex.linebreak(new_head, {
        looseness = 1,
        emergencystretch = tex.getdimen(emergencystretch),
    })

    -- Break the natural paragraph so we know how long it was
    nat_head = copy(head)

    if lmtx then
        parfillskip = new_node("glue", "parfillskip")
        parfillskip[stretch_order] = 1
        parfillskip.stretch = 1 -- 0pt plus 1fil
        last(nat_head).next = parfillskip
    end

    local natural_node, natural_info = tex.linebreak(nat_head)
    flush_list(natural_node)

    if renable_box_warnings then
        lwc.callbacks.disable_box_warnings.disable()
    end

    if not grid_mode_enabled() then
        -- Offset the accumulated \\prevdepth
        local prevdepth = new_node("glue")
        prevdepth.width = natural_info.prevdepth - long_info.prevdepth
        last(long_node).next = prevdepth
    end

    local long_cost = lwc.paragraph_cost(long_info.demerits, long_info.prevgraf)

    if long_info.prevgraf == natural_info.prevgraf + 1 and
       long_cost > 10 -- Any paragraph that is "free" to expand is suspicious
    then
        table.insert(paragraphs, {
            cost = long_cost,
            node = next_of_type(long_node, hlist_id, { subtype = line_subid })
        })
    end

    -- Print some debugging information
    get_chars(head)
    debug_print(get_location(), "nat  lines    " .. natural_info.prevgraf)
    debug_print(
        get_location(),
        "nat  cost " ..
        lwc.paragraph_cost(natural_info.demerits, natural_info.prevgraf)
    )
    debug_print(get_location(), "long lines    " .. long_info.prevgraf)
    debug_print(
        get_location(),
        "long cost " ..
        lwc.paragraph_cost(long_info.demerits, long_info.prevgraf)
    )

    -- \ConTeXt{} crashes if we return `true`
    return head
end

--- Tags the beginning and the end of each paragraph as it is added to the page.
---
--- We add an attribute to the first and last node of each paragraph. The ID is
--- some arbitrary number for \lwc/, and the value corresponds to the
--- paragraphs index, which is negated for the end of the paragraph. Called by the
--- `post_linebreak_filter` callback.
---
--- @param head node
--- @return node
function lwc.mark_paragraphs(head)
    if not status.output_active then -- Don't run during the output routine
        -- Get the start and end of the paragraph
        local top_para = next_of_type(head, hlist_id, { subtype = line_subid })
        local bottom_para = last(head)

        if top_para ~= bottom_para then
            set_attribute(
                top_para,
                attribute,
                #paragraphs + (PAGE_MULTIPLE * pagenum())
            )
            set_attribute(
                bottom_para,
                attribute,
                -1 * (#paragraphs + (PAGE_MULTIPLE * pagenum()))
            )
        else
            -- We need a special tag for a 1-line paragraph since the node can only
            -- have one attribute value
            set_attribute(
                top_para,
                attribute,
                #paragraphs + (PAGE_MULTIPLE * pagenum()) + SINGLE_LINE
            )
        end
    end

    return head
end

--- A "safe" version of the last/slide function.
---
--- Sometimes the node list can form a loop. Since there is no last element
--- of a looped linked-list, the `last()` function will never terminate. This
--- function provides a "safe" version of the `last()` function that will break
--- the loop at the end if the list is circular. Called by the `pre_output_filter`
--- callback.
---
--- @param head node The start of a node list
--- @return node The last node in a list
local function safe_last(head)
    local ids = {}
    local prev

    while head.next do
        local id = node_id(head)

        if ids[id] then
            warning [[Circular node list detected!
This should never happen. I'll try and
recover, but your output may be corrupted.
(Internal Error)]]
            prev.next = nil
            debug_print("safe_last", node.type(head.id) .. " " .. node.type(prev.id))

            return prev
        end

        ids[id] = true
        head.prev = prev
        prev = head
        head = head.next
    end

    return head
end

--- Checks to see if a penalty matches the widow/orphan/broken penalties
--- @param penalty number
--- @return boolean
function is_matching_penalty(penalty)
    local widowpenalty = tex.widowpenalty
    local clubpenalty = tex.clubpenalty
    local displaywidowpenalty = tex.displaywidowpenalty
    local brokenpenalty = tex.brokenpenalty

    --[[
        We only need to process pages that have orphans or widows. If `paragraphs`
        is empty, then there is nothing that we can do.

        The list of penalties is from:
        https://tug.org/TUGboat/tb39-3/tb123mitt-widows-code.pdf#subsection.0.2.1
      ]]
    penalty = penalty - tex.interlinepenalty

    return penalty ~= 0 and
           penalty <  INFINITY and (
               penalty == widowpenalty or
               penalty == displaywidowpenalty or
               penalty == clubpenalty or
               penalty == clubpenalty + widowpenalty or
               penalty == clubpenalty + displaywidowpenalty or
               penalty == brokenpenalty or
               penalty == brokenpenalty + widowpenalty or
               penalty == brokenpenalty + displaywidowpenalty or
               penalty == brokenpenalty + clubpenalty or
               penalty == brokenpenalty + clubpenalty + widowpenalty or
               penalty == brokenpenalty + clubpenalty + displaywidowpenalty
           )
end

--- Remove the widows and orphans from the page, just after the output routine.
---
--- This function holds the "meat" of the module. It is called just after the
--- end of the output routine, before the page is shipped out. If the output
--- penalty indicates that the page was broken at a widow or an orphan, we
--- replace one paragraph with the same paragraph, but lengthened by one line.
--- Then, we can push the bottom line of the page to the next page.
---
--- @param head node
--- @return node
function lwc.remove_widows(head)
    local head_save = head -- Save the start of the `head` linked-list

    debug_print("outputpenalty", tex.outputpenalty .. " " .. #paragraphs)

    if not is_matching_penalty(tex.outputpenalty) or
       #paragraphs == 0
    then
        paragraphs = {}
        return head_save
    end

    info("Widow/orphan/broken hyphen detected. Attempting to remove")

    --[[
        Find the paragraph on the page with the least cost.
      ]]
    local paragraph_index = 1
    local best_cost = paragraphs[paragraph_index].cost

    local last_paragraph
    local head_last = last(head)
    -- Find the last paragraph on the page, starting at the end, heading in reverse
    while head_last do
        local value = getattribute(head_last, attribute)
        if value then
            last_paragraph = value % PAGE_MULTIPLE
            break
        end

        head_last = head_last.prev
    end

    local first_paragraph
    -- Find the first paragraph on the page, from the top
    local first_attribute_val, first_attribute_head = find_attribute(head, attribute)
    if first_attribute_val // 100 == pagenum() - 1 then
        -- If the first complete paragraph on the page was initially broken on the
        -- previous page, then we can't expand it here so we need to skip it.
        first_paragraph = find_attribute(
            first_attribute_head.next,
            attribute
        ) % PAGE_MULTIPLE
    else
        first_paragraph = first_attribute_val % PAGE_MULTIPLE
    end

    -- We find the current "best" replacement, then free the unused ones
    for i, paragraph in pairs(paragraphs) do
        if paragraph.cost < best_cost and
           i <  last_paragraph and
           i >= first_paragraph
        then
            -- Clear the old best paragraph
            flush_list(paragraphs[paragraph_index].node)
            paragraphs[paragraph_index].node = nil
            -- Set the new best paragraph
            paragraph_index, best_cost = i, paragraph.cost
        elseif i > 1 then
            -- Not sure why `i > 1` is required?
            flush_list(paragraph.node)
            paragraph.node = nil
        end
    end

    debug_print(
        "selected para",
        pagenum() ..
        "/" ..
        paragraph_index ..
        " (" ..
        best_cost ..
        ")"
    )

    if best_cost > tex.getcount(max_cost) or
       paragraph_index == last_paragraph
    then
        -- If the best replacement is too bad, we can't do anything
        warning("Widow/Orphan/broken hyphen NOT removed on page " .. pagenum())
        paragraphs = {}
        return head_save
    end

    local target_node = paragraphs[paragraph_index].node

    -- Start of final paragraph
    debug_print("remove_widows", "moving last line")

    -- Here we check to see if the widow/orphan was preceded by a large penalty
    head = last(head_save).prev
    local big_penalty_found, last_line, hlist_head
    while head do
        if head.id == glue_id then
            -- Ignore any glue nodes
        elseif head.id == penalty_id and head.penalty >= INFINITY then
            -- Infinite break penalty
            big_penalty_found = true
        elseif big_penalty_found and head.id == hlist_id then
            -- Line before the penalty
            if lwc.nobreak_behaviour == "keep" then
                hlist_head = head
                big_penalty_found = false
            elseif lwc.nobreak_behaviour == "split" then
                head = last(head_save)
                break
            elseif lwc.nobreak_behaviour == "warn" then
                warning("Widow/Orphan/broken hyphen NOT removed on page " .. pagenum())
                paragraphs = {}
                return head_save
            end
        else
            -- Not found
            if hlist_head then
                head = hlist_head
            else
                head = last(head_save)
            end
            break
        end
        head = head.prev
    end

    local potential_penalty = head.prev.prev

    if potential_penalty and
       potential_penalty.id      == penalty_id and
       potential_penalty.subtype == linebreakpenalty_subid and
       is_matching_penalty(potential_penalty.penalty)
    then
        warning("Making a new widow/orphan/broken hyphen on page " .. pagenum())
    end


    last_line = copy(head)
    last(last_line).next = copy(tex.lists[contrib_head])

    head.prev.prev.next = nil
    -- Move the last line to the next page
    tex.lists[contrib_head] = last_line

    local free_next_nodes = false

    -- Loop through all of the nodes on the page with the lwc attribute
    head = head_save
    while head do
        local value
        value, head = find_attribute(head, attribute)

        if not head then
            break
        end

        debug_print("remove_widows", "found " .. value)

        -- Insert the start of the replacement paragraph
        if value == paragraph_index + (PAGE_MULTIPLE * pagenum()) or
           value == paragraph_index + (PAGE_MULTIPLE * pagenum()) + SINGLE_LINE
        then
            debug_print("remove_widows", "replacement start")
            safe_last(target_node) -- Remove any loops

            -- Fix the `\\baselineskip` glue between paragraphs
            height_difference = (
                next_of_type(head, hlist_id, { subtype = line_subid }).height -
                next_of_type(target_node, hlist_id, { subtype = line_subid }).height
            )

            local prev_bls = next_of_type(
                head,
                glue_id,
                { subtype = baselineskip_subid, reverse = true }
            )

            if prev_bls then
                prev_bls.width = prev_bls.width + height_difference
            end

            head.prev.next = target_node
            free_next_nodes = true
        end

        -- Insert the end of the replacement paragraph
        if value == -1 * (paragraph_index + (PAGE_MULTIPLE * pagenum())) or
           value ==       paragraph_index + (PAGE_MULTIPLE * pagenum()) + SINGLE_LINE
        then
            debug_print("remove_widows", "replacement end")
            local target_node_last = safe_last(target_node)

            if grid_mode_enabled() then
                -- Account for the difference in depth
                local after_glue = new_node("glue")
                after_glue.width = head.depth - target_node_last.depth
                target_node_last.next = after_glue

                after_glue.next = head.next
            else
                target_node_last.next = head.next
            end

            break
        end

        if free_next_nodes then
            head = free(head)
        else
            head = head.next
        end
    end

    info(
        "Widow/orphan/broken hyphen successfully removed at paragraph "
        .. paragraph_index
        .. " on page "
        .. pagenum()
    )

    paragraphs = {} -- Clear paragraphs array at the end of the page

    return head_save
end

--- Create a table of functions to enable or disable a given callback
--- @param t table Parameters of the callback to create
---     callback: string = The \LuaTeX{} callback name
---     func: function = The function to call
---     name: string = The name/ID of the callback
---     category: string = The category for a \ConTeXt{} "Action"
---     position: string = The "position" for a \ConTeXt{} "Action"
---     lowlevel: boolean = If we should use a lowlevel \LuaTeX{} callback instead of a
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
    elseif optex then -- Op\TeX{} is very similar to luatexbase
        return {
            enable = function()
                callback.add_to_callback(t.callback, t.func, t.name)
            end,
            disable = function()
                callback.remove_from_callback(t.callback, t.name)
            end,
        }
    end
end

-- Add all of the callbacks
lwc.callbacks = {
    disable_box_warnings = register_callback({
        callback = "hpack_quality",
        func     = function() end,
        name     = "disable_box_warnings",
        lowlevel = true,
    }),
    remove_widows = register_callback({
        callback = "pre_output_filter",
        func     = lwc.remove_widows,
        name     = "remove_widows",
        lowlevel = true,
    }),
    save_paragraphs = register_callback({
        callback = "pre_linebreak_filter",
        func     = lwc.save_paragraphs,
        name     = "save_paragraphs",
        category = "processors",
        position = "after",
    }),
    mark_paragraphs = register_callback({
        callback = "post_linebreak_filter",
        func     = lwc.mark_paragraphs,
        name     = "mark_paragraphs",
        category = "finalizers",
        position = "after",
    }),
}


local enabled = false
--- Enable the paragraph callbacks
function lwc.enable_callbacks()
    debug_print("callbacks", "enabling")
    if not enabled then
        lwc.callbacks.save_paragraphs.enable()
        lwc.callbacks.mark_paragraphs.enable()

        enabled = true
    else
        info("Already enabled")
    end
end

--- Disable the paragraph callbacks
function lwc.disable_callbacks()
    debug_print("callbacks", "disabling")
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
        info("Already disabled")
    end
end

function lwc.if_lwc_enabled()
    debug_print("iflwc")
    if enabled then
        insert_token(iftrue)
    else
        insert_token(iffalse)
    end
end

--- Mangles a macro name so that it's suitable for a specific format
--- @param name string The plain name
--- @param args table<string> The TeX types of the function arguments
--- @return string The mangled name
local function mangle_name(name, args)
    if plain then
        return "lwc@" .. name:gsub("_", "@")
    elseif optex then
        return "_lwc_" .. name
    elseif context then
        return "lwc_" .. name
    elseif latex then
        return "__lwc_" .. name .. ":" .. string_rep("n", #args)
    end
end

--- Creates a TeX command that evaluates a Lua function
--- @param name string The name of the csname to define
--- @param func function
--- @param args table<string> The TeX types of the function arguments
--- @return nil
local function register_tex_cmd(name, func, args)
    local scanning_func
    name = mangle_name(name, args)

    if not context then
        local scanners = {}
        for _, arg in ipairs(args) do
            scanners[#scanners+1] = token['scan_' .. arg]
        end

        scanning_func = function()
            local values = {}
            for _, scanner in ipairs(scanners) do
                values[#values+1] = scanner()
            end

            func(table.unpack(values))
        end
    end

    if optex then
        define_lua_command(name, scanning_func)
        return
    elseif plain or latex then
        local index = luatexbase.new_luafunction(name)
        lua.get_functions_table()[index] = scanning_func
        token.set_lua(name, index)
    elseif context then
        interfaces.implement {
            name = name,
            public = true,
            arguments = args,
            actions = func
        }
    end
end

register_tex_cmd("if_enabled", lwc.if_lwc_enabled, {})
register_tex_cmd("enable", lwc.enable_callbacks, {})
register_tex_cmd("disable", lwc.disable_callbacks, {})
register_tex_cmd(
    "nobreak",
    function(str)
        lwc.nobreak_behaviour = str
    end,
    { "string" }
)
register_tex_cmd(
    "debug",
    function(str)
        lwc.debug = str ~= "0" and str ~= "false" and str ~= "stop"
    end,
    { "string" }
)

--- Silence the luatexbase "Enabling/Removing <callback>" info messages
---
--- Every time that a paragraph is typeset, \lwc/ hooks in
--- and typesets the paragraph 1 line longer. Some of these longer paragraphs
--- will have pretty bad badness values, so TeX will issue an over/underfull
--- hbox warning. To block these warnings, we hook into the `hpack_quality`
--- callback and disable it so that no warning is generated.
---
--- However, each time that we enable/disable the null `hpack_quality` callback,
--- luatexbase puts an info message in the log. This completely fills the log file
--- with useless error messages, so we disable it here.
---
--- This uses the Lua `debug` library to internally modify the log upvalue in the
--- `add_to_callback` function. This is almost certainly a terrible idea, but I don't
--- know of a better way.
local function silence_luatexbase()
    local nups = debug.getinfo(luatexbase.add_to_callback).nups

    for i = 1, nups do
        local name, func = debug.getupvalue(luatexbase.add_to_callback, i)
        if name == "luatexbase_log" then
            debug.setupvalue(
                luatexbase.add_to_callback,
                i,
                function(text)
                    if text:match("^Inserting") or text:match("^Removing") then
                        return
                    else
                        func(text)
                    end
                end
            )
            return
        end
    end
end

-- Activate \lwc/
if plain or latex then
    silence_luatexbase()
end

lwc.callbacks.remove_widows.enable()

return lwc

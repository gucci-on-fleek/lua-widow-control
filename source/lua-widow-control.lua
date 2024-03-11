--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2022 Max Chernoff
  ]]

--- Tell the linter about node attributes
--- @class node
--- @field depth integer
--- @field height integer
--- @field id integer
--- @field list node
--- @field next node
--- @field penalty integer
--- @field prev node
--- @field subtype integer

-- Initial setup
lwc = lwc or {}
lwc.name = "lua-widow-control"

-- Locals for `debug_print`
local string_rep = string.rep
local write_nl = texio.write_nl

local write_log
if status.luatex_engine == "luametatex" then
    write_log = "logfile"
else
    write_log = "log"
end

--- Prints debugging messages to the log, only if `debug` is set to `true`.
---
--- @param title string The "title" to use
--- @param text string? The "content" to print
--- @return nil
local function debug(title, text)
    if not lwc.debug then return end

    -- The number of spaces we need
    local filler = 15 - #title

    if text then
        write_nl(
            write_log,
            "LWC (" ..
            title ..
            string_rep(" ", filler) ..
            "): " ..
            text
        )
    else
        write_nl(write_log, "LWC: " .. string_rep(" ", 18) .. title)
    end
end


--[[
    \lwc/ is intended to be format-agonistic. It only runs on Lua\TeX{} and
    LuaMeta\TeX{}, but there are still some slight differences between formats.
    Here, we detect the format name then set some flags for later processing.
  ]]
local format = tex.formatname
local context, latex, plain, optex, lmtx

if status.luatex_engine == "luametatex" then
    lmtx = true
end

if format:find("cont") then -- cont-en, cont-fr, cont-nl, ...
    context = true
elseif format:find("latex") then -- lualatex, lualatex-dev, ...
    latex = true
elseif format == "luatex" or
       format == "luahbtex" or
       format:find("plain")
then -- Plain
    plain = true
elseif format:find("optex") then -- OpTeX
    optex = _G.optex
end

--[[
    Save some local copies of the node library to reduce table lookups.
    This is probably a useless micro-optimization, but it is done in all of the
    ConTeXt and expl3 Lua code, so I should probably do it here too.
  ]]
-- Node ID's
-- (We need to hardcode the subid's sadly)
local id_from_name = node.id
local baselineskip_subid = 2
local glue_id = id_from_name("glue")
local glyph_id = id_from_name("glyph")
local hlist_id = id_from_name("hlist")
local insert_id = id_from_name("insert") or id_from_name("ins")
local line_subid = 1
local linebreakpenalty_subid = 1
local par_id = id_from_name("par") or id_from_name("local_par")
local penalty_id = id_from_name("penalty")
local parfill_subids = {
    parfillleftskip = 17,
    parfillrightskip = 16,
    parinitleftskip = 19,
    parinitrightskip = 18,
}
local vlist_id = id_from_name("vlist")

-- Local versions of globals
local abs = math.abs
local copy = node.copy
local copy_list = node.copy_list or node.copylist
local effective_glue = node.effective_glue or node.effectiveglue
local find_attribute = node.find_attribute or node.findattribute
local free = node.free
local free_list = node.flush_list or node.flushlist
local get_attribute = node.get_attribute or node.getattribute
local hpack = node.hpack
local insert_token = token.put_next or token.putnext
local is_node = node.is_node or node.isnode
local last = node.slide
local linebreak = tex.linebreak
local new_node = node.new
local remove = node.remove
local set_attribute = node.set_attribute or node.setattribute
local str_byte = string.byte
local str_char = string.char
local str_format = string.format
local subtype = node.subtype
local tex_box = tex.box
local tex_count = tex.count
local tex_dimen = tex.dimen
local tex_lists = tex.lists
local traverse = node.traverse
local traverse_id = node.traverse_id or node.traverseid
local vpack = node.vpack

-- Misc. Constants
local iffalse = token.create("iffalse")
local iftrue = token.create("iftrue")
local INFINITY = 10000
local INSERT_CLASS_MULTIPLE = 1000 * 1000
local INSERT_FIRST_MULTIPLE = 1000
local PAGE_MULTIPLE = 100
local SINGLE_LINE = 50

lwc.colours = {
    expanded = {0.00, 0.70, 0.25},
    failure  = {0.90, 0.00, 0.25},
    moved    = {0.25, 0.25, 1.00},
    cost     = {0.50, 0.50, 0.50},
}


--[[ Package/module initialization.

     Here, we replace any format/engine-specific variables/functions with some
     generic equivalents. This way, we can write the rest of the module without
     worrying about any format/engine differences.
  ]]
local contrib_head,
      draft_offset,
      emergencystretch,
      hold_head,
      info,
      insert_attribute,
      max_cost,
      page_head,
      paragraph_attribute,
      set_whatsit_field,
      shrink_order,
      stretch_order,
      warning

if lmtx then
    -- LMTX has removed underscores from most of the Lua parts
    debug("LMTX")
    contrib_head = "contributehead"
    shrink_order = "shrinkorder"
    stretch_order = "stretchorder"
    hold_head = "holdhead"
    page_head = "pagehead"
    set_whatsit_field = node.setwhatsitfield
else
    contrib_head = "contrib_head"
    shrink_order = "shrink_order"
    stretch_order = "stretch_order"
    hold_head = "hold_head"
    page_head = "page_head"
    set_whatsit_field = node.setfield
end

if context then
    debug("ConTeXt")

    warning = logs.reporter(lwc.name, "warning")
    local _info = logs.reporter(lwc.name, "info")
    --[[ We don't want the info messages on the terminal, but ConTeXt doesn't
         provide any logfile-only reporters, so we need this hack.
      ]]
    info = function (text)
        logs.pushtarget("logfile")
        _info(text)
        logs.poptarget()
    end
    paragraph_attribute = attributes.public(lwc.name .. "_paragraph")
    insert_attribute = attributes.public(lwc.name .. "_insert")

    -- Dimen/count names
    emergencystretch = "lwc_emergency_stretch"
    draft_offset = "lwc_draft_offset"
    max_cost = "lwc_max_cost"
elseif plain or latex or optex then
    -- Dimen names
    if tex.isdimen("g__lwc_emergencystretch_dim") then
        emergencystretch = "g__lwc_emergencystretch_dim"
        draft_offset = "g__lwc_draftoffset_dim"
        max_cost = "g__lwc_maxcost_int"
    else
        emergencystretch = "lwcemergencystretch"
        draft_offset = "lwcdraftoffset"
        max_cost = "lwcmaxcost"
    end

    if plain or latex then
        debug("Plain/LaTeX")
        luatexbase.provides_module {
            name = lwc.name,
            date = "2024/03/11", --%%slashdate
            version = "3.0.1", --%%version
            description = [[

This module provides a LuaTeX-based solution to prevent
widows and orphans from appearing in a document. It does
so by increasing or decreasing the lengths of previous
paragraphs.]],
        }
        warning = function(str) luatexbase.module_warning(lwc.name, str) end
        info = function(str) luatexbase.module_info(lwc.name, str) end
        paragraph_attribute = luatexbase.new_attribute(lwc.name .. "_paragraph")
        insert_attribute = luatexbase.new_attribute(lwc.name .. "_insert")
    elseif optex then
        debug("OpTeX")

        warning = function(str) write_nl(lwc.name .. " Warning: " .. str) end
        info = function(str) write_nl("log", lwc.name .. " Info: " .. str) end
        paragraph_attribute = alloc.new_attribute(lwc.name .. "_paragraph")
        insert_attribute = alloc.new_attribute(lwc.name .. "_insert")
    end
else -- This shouldn't ever happen
    error [[Unsupported format.

Please use LaTeX, Plain TeX, ConTeXt or OpTeX.]]
end

-- We can't get the value of \\horigin from Lua, but we can guess it
-- based on the format.
local horigin
if optex or (lmtx and context) then
    horigin = 0
else
    horigin = tex.sp("1in")
end

-- Plain is the only format without a `pre_shipout_filter`
if plain then
    luatexbase.create_callback('pre_shipout_filter', 'list')
end


--[[ Select the fonts

     We want to use cmr6 for the draft mode cost displays, and the easiest
     way to do so is to just hardcode the font id's. This relies on some
     implementation details; however, it is very unlikely to ever be an issue.
  ]]
local SMALL_FONT
if plain then
    SMALL_FONT = 5
elseif latex then
    SMALL_FONT = 6
elseif optex then
    SMALL_FONT = 8
elseif context then
    SMALL_FONT = fonts.definers.define({
        name = "LMRoman6-Regular",
        size = tex.sp("6pt"),
    })
end

-- Global variables
local paragraphs = {} -- The expanded paragraphs on each page
local inserts = {} -- Copies of all the inserts on each page
local costs = {} -- All of the paragraph costs for the document
local pagenum = 1 -- The current page/column number

--[[ Function definitions
  ]]

--- Gets the current paragraph and page locations
--- @return string
local function get_location()
    return "At " .. pagenum .. "/" .. #paragraphs
end


--- Prints the starting glyphs and glue of an `hlist`.
---
--- Useful for debugging purposes.
---
--- @param head node
--- @return nil
local function get_chars(head)
    if not lwc.debug then return end

    local chars = ""
    for n in traverse(head) do
        if n.id == glyph_id then
            if n.char < 127 then -- Only ASCII
                chars = chars .. str_char(n.char)
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

    debug(get_location(), chars)
end


--- The "cost function" to use. Users can redefine this if they wish.
---
--- @param demerits number The demerits of the broken paragraph
--- @param lines number The number of lines in the broken paragraph
--- @param nat_demerits number The demerits of the naturally-broken paragraph
--- @param nat_lines number The number of lines in the naturally-broken paragraph
--- @param head node The head of the broken paragraph
--- @return number cost The cost of the broken paragraph
function lwc.paragraph_cost(demerits, lines, nat_demerits, nat_lines, head)
    return demerits / math.sqrt(lines)
end


--- Checks if the ConTeXt "grid snapping" is active
---
--- @return boolean
local function grid_mode_enabled()
    -- Compare the token "mode" to see if `\\ifgridsnapping` is `\\iftrue`
    return token.create("ifgridsnapping").mode == iftrue.mode
end


--- Gets the next node of a specified type/subtype in a node list
---
--- @param head node The head of the node list
--- @param id number The node type
--- @param args table?
---     subtype: number = The node subtype
---     reverse: bool = Whether we should iterate backwards
--- @return node?
local function next_of_type(head, id, args)
    args = args or {}

    if lmtx or not args.reverse then
        for n, subtype in traverse_id(id, head, args.reverse) do
            if (subtype == args.subtype) or (args.subtype == nil) then
                return n
            end
        end
    else
        -- Only LMTX has the built-in backwards traverser, so we need to do
        -- it manually otherwise.
        while head do
            if head.id == id and
               (head.subtype == args.subtype or args.subtype == nil)
            then
                return head
            end
            head = head.prev
        end
    end

    -- Needed for the special `tex.lists` nodes
    if head and head.id == id and
       (head.subtype == args.subtype or args.subtype == nil)
    then
        return head
    end
end


--- Ensures that a paragraph is ready to be broken
---
--- Only applies to LuaMetaTeX
---
--- @param head node
--- @return nil
local function prepare_linebreak(head)
    if not lmtx then
        return
    end

    -- See how many of the par[left/right][init/fill]skips we have
    local parfills = {}
    local count = 0
    for name, subid in pairs(parfill_subids) do
        parfills[name] = next_of_type(head, glue_id, { subtype = subid })
        if parfills[name] then
            count = count + 1
        end
    end

    if count == 0 then
        -- Usual case
        tex.preparelinebreak(head)
    elseif count == 4 then
        -- Already prepared for some reason, ignored
    else
        -- Uh oh
        warning("Weird par(fill/init)skips found!")
        tex.preparelinebreak(head) -- Try to fix it
    end
end


--- Breaks a paragraph one line longer than natural
---
--- @param head node The unbroken paragraph
--- @param parfillskip table<number> The {width, stretch, shrink,
---                                  stretch_order, shrink_order} to set
---                                  for the \\parfillskip
--- @return node long_node The broken paragraph
--- @return table long_info An info table about the broken paragraph
local function long_paragraph(head, parfillskip)
    -- We can't modify the original paragraph
    head = copy_list(head)

    prepare_linebreak(head)

    -- TODO node.setglue is broken in LMTX, so we have to do this manually
    local n = last(head)
    n.width = parfillskip[1]
    n.stretch = parfillskip[2]
    n.shrink = parfillskip[3]
    n[stretch_order] = parfillskip[4]
    n[shrink_order] = parfillskip[5]

    -- Break the paragraph 1 line longer than natural
    local long_node, long_info =  linebreak(head, {
        looseness = 1,
        emergencystretch = tex_dimen[emergencystretch],
    })

    -- Mark the last line for the costs display
    set_attribute(
        last(long_node),
        paragraph_attribute,
        -1 * (#paragraphs + 1 + (PAGE_MULTIPLE * pagenum))
    )

    return long_node, long_info
end


--- Breaks a paragraph at its natural length
---
--- @param head node The unbroken paragraph
--- @return table natural_info An info table about the broken paragraph
local function natural_paragraph(head)
    -- We can't modify the original paragraph
    head = copy_list(head)

    prepare_linebreak(head)

    -- Break the paragraph naturally to get \\prevgraf
    local natural_node, natural_info = linebreak(head)
    free_list(natural_node)

    return natural_info
end


local show_colours = false
--- Changes the text colour in a node list if draft mode is active
---
--- @param head node The first node to colour
--- @param colour string The name of a colour in `lwc.colours`
--- @return node head The coloured node
local function colour_list(head, colour)
    if not show_colours then
        return head
    end

    local pdf_colour = str_format(
        "%.2f %.2f %.2f rg",
        table.unpack(lwc.colours[colour])
    )

    if optex and optex.set_node_color then
        for n in node.traverse(head) do
            optex.set_node_color(n, pdf_colour)
        end

        return head
    end

    if context then
        nodes.tracers.colors.setlist(head, "lwc_" .. colour)
        return head
    end

    -- Adapted from https://tex.stackexchange.com/a/372437 and
    -- https://github.com/zauguin/luametalatex/issues/8.
    local start_colour = new_node("whatsit", subtype("pdf_colorstack"))
    set_whatsit_field(start_colour, "stack", 0)
    set_whatsit_field(start_colour, "command", 1)
    set_whatsit_field(start_colour, "data", pdf_colour)

    local end_colour = new_node("whatsit", subtype("pdf_colorstack"))
    set_whatsit_field(end_colour, "stack", 0)
    set_whatsit_field(end_colour, "command", 2)

    start_colour.next = head
    last(head).next = end_colour

    return start_colour
end


--- Saves each paragraph, but lengthened by 1 line
---
--- Called by the `pre_linebreak_filter` callback
---
--- @param head node The pre-broken paragraph
--- @return node head The unmodified `head` argument
function lwc.save_paragraphs(head)
    if (head.id ~= par_id and context) or -- Make sure that `head` is a paragraph
        status.output_active or -- Don't run during the output routine
        tex.nest.ptr > 1 -- Don't run inside boxes
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

    natural_info = natural_paragraph(head)

    -- Prevent ultra-short last lines (\TeX{}book p. 104). Equivalent to
    -- \\parfillskip=0.75\\hsize plus 0.05\\hsize minus 0.75\\hsize.
    -- From http://petr.olsak.net/ftp/olsak/tbn/tbn.pdf p. 234 (via Jan Sustek)
    long_node, long_info = long_paragraph(
        head,
        {0.75 * tex.hsize, 0.05 * tex.hsize, 0.75 * tex.hsize, 0, 0}
    )

    if long_info.prevgraf ~= natural_info.prevgraf + 1 then
        -- The \\parfillskip settings with \\looseness=1 can sometimes
        -- lengthen paragraphs by two lines instead of one. If this happens,
        -- we fall back to a slightly-worse \\parfillskip setting.
        free_list(long_node)
        long_node, long_info = long_paragraph(
            head,
            {0, 0.8 * tex.hsize, false, 0, false}
        )
    end

    if renable_box_warnings then
        lwc.callbacks.disable_box_warnings.disable()
    end

    if not grid_mode_enabled() then
        -- Offset the \\prevdepth differences between natural and long
        local prevdepth = new_node("glue")
        prevdepth.width = natural_info.prevdepth - long_info.prevdepth
        last(long_node).next = prevdepth
    end

    local long_cost = lwc.paragraph_cost(
        long_info.demerits,
        long_info.prevgraf,
        natural_info.demerits,
        natural_info.prevgraf,
        long_node
    )

    if long_info.prevgraf ~= natural_info.prevgraf + 1 or
       long_cost < 10 -- Any paragraph that is "free" to expand is suspicious
    then
        -- This paragraph is infinitely bad
        long_cost = math.maxinteger
    end

    -- The initial glue can disappear in ConTeXt's grid mode, so we
    -- save starting at the first hlsit
    local saved_node = next_of_type(long_node, hlist_id, { subtype = line_subid })

    for n in traverse_id(hlist_id, saved_node) do
        n.list = colour_list(n.list, "expanded")
    end

    table.insert(paragraphs, {
        cost = long_cost,
        node = copy_list(saved_node)
    })

    free_list(long_node)

    costs[#paragraphs + (PAGE_MULTIPLE * pagenum)] = long_cost

    -- Print some debugging information
    if lwc.debug then
        get_chars(head)
        debug(get_location(), "nat  lines    " .. natural_info.prevgraf)
        debug(
            get_location(),
            "nat  cost " ..
            lwc.paragraph_cost(natural_info.demerits, natural_info.prevgraf)
        )
        debug(get_location(), "long lines    " .. long_info.prevgraf)
        debug(
            get_location(),
            "long cost " ..
            lwc.paragraph_cost(long_info.demerits, long_info.prevgraf)
        )
    end

    -- \ConTeXt{} crashes if we return `true`
    return head
end


--- Tags the beginning and the end of each paragraph as it is added to the page.
---
--- We add an attribute to the first and last node of each paragraph. The ID is
--- some arbitrary number for \lwc/, and the value corresponds to the
--- paragraphs index, which is negated for the end of the paragraph.
---
--- @param head node
--- @return nil
local function mark_paragraphs(head)
    -- Tag the paragraphs
    if status.output_active then
        -- Don't run during the output routine
        return
    end

    -- Get the start and end of the paragraph
    local top = next_of_type(head, hlist_id, { subtype = line_subid })
    local bottom = last(head)

    -- The inserts disappear before `pre_output_routine`, so we shouldn't
    -- mark them.
    while bottom.id == insert_id do
        bottom = bottom.prev
    end

    if top ~= bottom then
        set_attribute(
            top,
            paragraph_attribute,
            #paragraphs + (PAGE_MULTIPLE * pagenum)
        )
        set_attribute(
            bottom,
            paragraph_attribute,
            -1 * (#paragraphs + (PAGE_MULTIPLE * pagenum))
        )
    else
        -- We need a special tag for a 1-line paragraph since the node can only
        -- have a single attribute value
        set_attribute(
            top,
            paragraph_attribute,
            #paragraphs + (PAGE_MULTIPLE * pagenum) + SINGLE_LINE
        )
    end
end


--- Tags the each line with the indices of any corresponding inserts.
---
--- We need to tag the first element of the hlist before the any insert nodes
--- since the insert nodes are removed before `pre_output_filter` gets called.
---
--- @param head node
--- @return nil
local function mark_inserts(head)
    local insert_indices = {}
    for insert in traverse_id(insert_id, head) do
        -- Save the found insert nodes for later
        inserts[#inserts+1] = copy(insert)

        -- Tag the insert's content so that we can find it later
        set_attribute(insert.list, insert_attribute, #inserts)

        -- We need to tag all lines---not just the start and the end---since
        -- \TeX{} can split the insert between pages at any point.
        for n in traverse(insert.list.next) do
            set_attribute(n, insert_attribute, -1 * #inserts)
        end

        -- Each hlist/line can have multiple inserts, but so we can't just tag
        -- the hlist as we go. Instead, we need save up all of their indices,
        -- then tag the hlist with the first and last indices.
        insert_indices[#insert_indices+1] = #inserts

        if not insert.next or
           insert.next.id ~= insert_id
        then
            local hlist_before = next_of_type(insert, hlist_id, { reverse = true} )

            local insert_class
            if lmtx then
                insert_class = insert.index
            else
                insert_class = insert.subtype
            end

            -- We tag the first element of the hlist/line with an integer
            -- that holds the insert class and the first and last indices
            -- of the inserts contained in the line. This won't work if
            -- the line has multiple classes of inserts, but I don't think
            -- that happens in real-world documents. If this does turn out
            -- to be an issue, we can get the insert's class from it's copy
            -- at `pre_output_filter` instead of saving it now.
            set_attribute(
                hlist_before.list,
                insert_attribute,
                insert_class      * INSERT_CLASS_MULTIPLE +
                insert_indices[1] * INSERT_FIRST_MULTIPLE +
                insert_indices[#insert_indices]
            )

            -- Clear the indices to prepare for the next line
            insert_indices = {}
        end
    end
end


--- Saves the inserts and tags a typeset paragraph. Called by the
--- `post_linebreak_filter` callback.
---
--- @param head node The head of the broken paragraph
--- @return node head The unmodified `head` parameter
function lwc.mark_paragraphs(head)
    mark_paragraphs(head)
    mark_inserts(head)

    return head
end


--- Checks to see if a penalty matches the widow/orphan/broken penalties
---
--- @param penalty number
--- @return boolean
local function is_matching_penalty(penalty)
    local widowpenalty = tex.widowpenalty
    local clubpenalty = tex.clubpenalty
    local displaywidowpenalty = tex.displaywidowpenalty
    local brokenpenalty = tex.brokenpenalty

    penalty = penalty - tex.interlinepenalty

    -- Adapted from https://tug.org/TUGboat/tb39-3/tb123mitt-widows-code.pdf.
    -- This only takes into account the original \TeX{} penalties, not the
    -- "new" \eTeX{} \\(club/widow/broken)penalties commands.
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


--- Determines if we should "activate" \lwc/ for the current page/column.
---
--- Users can redefine this if they wish.
---
--- @param penalty number The \\outputpenalty for the current page/column
--- @param paragraphs table<table<string, node|number>> The `paragraphs` table
--- @param head node The head of the current page/column
--- @return boolean activate True if \lwc/ should move the last line on this page
function lwc.should_remove_widows(penalty, paragraphs, head)
    return is_matching_penalty(penalty)
end

--- Reset any state saved between pages
---
--- This function is *vital* to ensure that we don't leak any nodes.
--- If we do leak nodes, then very large documents will slow down and
--- eventually fail to compile.
---
--- @return nil
local function reset_state()
    for _, paragraph in ipairs(paragraphs) do
        free_list(paragraph.node)
    end
    paragraphs = {}

    for _, insert in ipairs(inserts) do
        free(insert)
    end
    inserts = {}

    pagenum = pagenum + 1
end


--- When we are unable to remove a widow/orphan, print a warning
---
--- @return nil
local function remove_widows_fail()
    warning("Widow/Orphan/Broken Hyphen NOT removed on page " .. pagenum)

    local last_line = next_of_type(
        last(tex_lists[page_head]),
        hlist_id,
        { subtype = line_subid, reverse = true }
    )
    if last_line then
        last_line.list = colour_list(last_line.list, "failure")
    end

    local next_first_line = next_of_type(
        tex_lists[contrib_head],
        hlist_id,
        { subtype = line_subid }
    )
    if next_first_line then
        next_first_line.list = colour_list(next_first_line.list, "failure")
    end

    reset_state()
end


--- Finds the first and last paragraphs present on a page
---
--- @param head node The node representing the start of the page
--- @return number first_index The index of the first paragraph on the page in
---                            the `paragraphs` table
--- @return number last_index The index of the last paragraph on the page in the
---                           `paragraphs` table
local function first_last_paragraphs(head)
    local first_index, last_index

    -- Find the last paragraph on the page, starting at the end, heading in reverse
    local n = last(head)
    while n do
        local value = get_attribute(n, paragraph_attribute)
        if value then
            last_index = value % PAGE_MULTIPLE
            break
        end

        n = n.prev
    end

    -- Find the first paragraph on the page, from the top
    local first_val, first_head = find_attribute(head, paragraph_attribute)
    while abs(first_val) // PAGE_MULTIPLE == pagenum - 1 do
        -- If the first complete paragraph on the page was initially broken on the
        -- previous page, then we can't expand it here. Why can't we expand it?
        -- Well, expanding it will nearly always change how the first few lines
        -- are printed, but we can't modify those since they've already been
        -- shipped out. So, we need to skip these paragraphs.
        first_val, first_head = find_attribute(
            first_head.next,
            paragraph_attribute
        )
    end

    first_index = first_val % PAGE_MULTIPLE

    if first_index >= SINGLE_LINE then
        first_index = first_index - SINGLE_LINE
    end

    debug("first/last", first_index .. "/" .. last_index)

    return first_index, last_index
end


--- Selects the "best" paragraph on the page to expand
---
--- @param head node The node representing the start of the page
--- @return number? best_index The index of the paragraph to expand in the
---                           `paragraphs` table
local function best_paragraph(head)
    local first_paragraph_index, last_paragraph_index = first_last_paragraphs(head)

    -- Find the paragraph on the page with the least cost.
    local best_index = 1
    local best_cost = paragraphs[best_index].cost

    -- We find the current "best" replacement
    for index, paragraph in pairs(paragraphs) do
        if paragraph.cost < best_cost and
           index <  last_paragraph_index and
           index >= first_paragraph_index
        then
            best_index, best_cost = index, paragraph.cost
        end
    end

    debug(
        "selected para",
        pagenum .. "/" .. best_index .. " (" .. best_cost .. ")"
    )

    if best_cost  >  tex_count[max_cost] or
       best_index == last_paragraph_index or -- Shouldn't happen
       best_cost  == math.maxinteger
    then
        return nil
    else
        return best_index
    end
end


--- Gets any inserts present in the moved line
---
--- @param last_line node The moved last line
--- @return table<node> inserts A list of the present inserts
local function get_inserts(last_line)
    local selected_inserts = {}

    local n = last_line.list
    while n do -- Iterate through the last line
        local line_value
        line_value, n = find_attribute(n, insert_attribute)

        if not n then
            break
        end

        -- Demux the insert values
        local class = line_value // INSERT_CLASS_MULTIPLE
        local first_index = (line_value % INSERT_CLASS_MULTIPLE)
                            // INSERT_FIRST_MULTIPLE
        local last_index = line_value % INSERT_FIRST_MULTIPLE

        -- Get the output box containing the insert boxes
        local insert_box

        if lmtx then
            insert_box = tex.getinsertcontent(class)
            -- `getinsertcontent` resets the insert box, so we need to
            -- re-set it.
            tex.setinsertcontent(class, insert_box)
        else
            insert_box = tex_box[class]
        end

        -- Get any portions of the insert "held over" until the next page
        local split_insert
        if lmtx then
            split_insert = next_of_type(
                tex_lists[hold_head],
                insert_id,
                { index = class }
            )
        else
            split_insert = next_of_type(
                tex_lists[hold_head],
                insert_id,
                { subtype = class }
            )
        end

        -- We use the same procedure for this page and the next page
        for i, insert in ipairs { insert_box, split_insert } do
            local m = insert and insert.list

            while m do -- Iterate through the insert box
                local box_value
                box_value, m = find_attribute(m, insert_attribute)
                local next = m.next

                if not m then
                    break
                end

                if abs(box_value) >= first_index and
                   abs(box_value) <= last_index
                then
                    -- Remove the respective contents from the insert box
                    insert.list = remove(insert.list, m)

                    if box_value > 0 and i == 1 then
                        table.insert(selected_inserts, copy(inserts[box_value]))
                    end

                    free(m)
                end

                m = next
            end
        end

        -- If the box has no contents, then void it so that any \\ifvoid
        -- tests work correctly in the output routine.
        if not insert_box.list then
            tex_box[class] = nil
        end

        if split_insert and not split_insert.list then
            remove(tex_lists[hold_head], split_insert)
        end

        n = n.next
    end

    if #selected_inserts ~= 0 then
        -- This is a somewhat-risky process, so we print an info
        -- message just in case something goes wrong. We can probably
        -- remove this in the future if we're sure that everything
        -- is working correctly.
        info("Moving footnotes on page " .. pagenum)
    end

    return selected_inserts
end


lwc.nobreak_behaviour = "keep"
--- Moves the last line of the page onto the following page.
---
--- This is the most complicated function of the module since it needs to
--- look back to see if there is a heading preceding the last line, then it does
--- some low-level node shuffling.
---
--- @param head node The node representing the start of the page
--- @return boolean success Set to false if something went wrong
local function move_last_line(head)
    -- Start of final paragraph
    debug("remove_widows", "moving last line")

    -- Here we check to see if the widow/orphan was preceded by a large penalty
    local big_penalty_found, last_line, hlist_head
    local n = last(head).prev
    while n do
        if n.id == glue_id then
            -- Ignore any glue nodes
        elseif n.id == penalty_id and n.penalty >= INFINITY then
            -- Infinite break penalty
            big_penalty_found = true
        elseif big_penalty_found and n.id == hlist_id then
            -- Line before the penalty
            if lwc.nobreak_behaviour == "keep" then
                hlist_head = n
                big_penalty_found = false
            elseif lwc.nobreak_behaviour == "split" then
                n = last(head)
                break
            elseif lwc.nobreak_behaviour == "warn" then
                debug("last line", "heading found")
                return false
            end
        else
            -- Not found
            if hlist_head then
                n = hlist_head
            else
                n = last(head)
            end
            break
        end
        n = n.prev
    end

    local potential_penalty = n.prev.prev

    if potential_penalty and
       potential_penalty.id      == penalty_id and
       potential_penalty.subtype == linebreakpenalty_subid and
       is_matching_penalty(potential_penalty.penalty)
    then
        warning("Making a new widow/orphan/broken hyphen on page " .. pagenum)

        local second_last_line = next_of_type(
            potential_penalty,
            hlist_id,
            { subtype = line_subid, reverse = true }
        )
        second_last_line.list = colour_list(second_last_line.list, "failure")
    end

    last_line = copy_list(n)

    last_line.list = colour_list(last_line.list, "moved")

    -- Reinsert any inserts originally present in this moved line
    local selected_inserts = get_inserts(last_line)
    for _, insert in ipairs(selected_inserts) do
        last(last_line).next = insert
    end

    -- Add back in the content from the next page
    last(last_line).next = copy_list(tex_lists[contrib_head])

    free_list(n.prev.prev.next)
    n.prev.prev.next = nil

    -- Set the content of the next page
    free_list(tex_lists[contrib_head])
    tex_lists[contrib_head] = last_line

    return true
end


--- Replace the chosen paragraph with its expanded version.
---
--- This is the "core function" of the module since it is what ultimately causes
--- the expansion to occur.
---
--- @param head node
--- @param paragraph_index number
local function replace_paragraph(head, paragraph_index)
    -- Remove any inserts. They are completely ignored after
    -- the page has been broken, but they can upset LuaMetaLaTeX if
    -- they're found somewhere unexpected.
    local target_node, last_target_node
    for n in traverse(paragraphs[paragraph_index].node) do
        -- Just removing the inserts from the list doesn't work properly,
        -- so we instead copy over everything that isn't an insert.
        if n.id ~= insert_id then
            if not target_node then
                target_node = copy(n)
                last_target_node = target_node
            else
                last_target_node.next = copy(n)
                last_target_node = last_target_node.next
            end
        end
    end

    local start_found = false
    local end_found = false
    local free_nodes_begin

    -- Loop through all of the nodes on the page with the \lwc/ attribute
    local n = head
    while n do
        local value
        value, n = find_attribute(n, paragraph_attribute)

        if not n then
            break
        end

        debug("remove_widows", "found " .. value)

        -- Insert the start of the replacement paragraph
        if value == paragraph_index + (PAGE_MULTIPLE * pagenum) or
           value == paragraph_index + (PAGE_MULTIPLE * pagenum) + SINGLE_LINE
        then
            debug("remove_widows", "replacement start")
            start_found = true

            -- Fix the `\\baselineskip` glue between paragraphs
            height_difference = (
                next_of_type(n, hlist_id, { subtype = line_subid }).height -
                next_of_type(
                    target_node, hlist_id, { subtype = line_subid }
                ).height
            )

            local prev_bls = next_of_type(
                n,
                glue_id,
                { subtype = baselineskip_subid, reverse = true }
            )

            if prev_bls then
                prev_bls.width = prev_bls.width + height_difference
            end

            n.prev.next = target_node
            free_nodes_begin = n
        end

        -- Insert the end of the replacement paragraph
        if value == -(paragraph_index + (PAGE_MULTIPLE * pagenum)) or
           value ==   paragraph_index + (PAGE_MULTIPLE * pagenum) + SINGLE_LINE
        then
            debug("remove_widows", "replacement end")
            end_found = true

            local target_node_last = last(target_node)

            if grid_mode_enabled() then
                -- Account for the difference in depth
                local after_glue = new_node("glue")
                after_glue.width = n.depth - target_node_last.depth
                target_node_last.next = after_glue

                after_glue.next = n.next
            else
                target_node_last.next = n.next
            end

            n.next = nil

            break
        end

        n = n.next
    end

    if start_found and end_found then
        free_list(free_nodes_begin)
    else
        warning("Paragraph NOT expanded on page " .. pagenum)
    end
end


--- Remove the widows and orphans from the page, just after the output routine.
---
--- This is called just after the end of the output routine, before the page is
--- shipped out. If the output penalty indicates that the page was broken at a
--- widow or an orphan, we replace one paragraph with the same paragraph, but
--- lengthened by one line. Then, we can push the bottom line of the page to the
--- next page.
---
--- @param head node
--- @return node
function lwc.remove_widows(head)
    debug("outputpenalty", tex.outputpenalty .. " " .. #paragraphs)

    -- See if there is a widow/orphan for us to remove
    if not lwc.should_remove_widows(tex.outputpenalty, paragraphs, head) then
        reset_state()
        return head
    end

    info("Widow/orphan/broken hyphen detected. Attempting to remove")

    -- Nothing that we can do if there aren't any paragraphs available to expand
    if #paragraphs == 0 then
        debug("failure", "no paragraphs to expand")
        remove_widows_fail()
        return head
    end

    -- Check the original height of \\box255
    local vsize = tex_dimen.vsize
    local orig_vpack = vpack(head)
    local orig_height_diff = orig_vpack.height - vsize
    orig_vpack.list = nil
    free(orig_vpack)

    -- Find the paragraph to expand
    local paragraph_index = best_paragraph(head)

    if not paragraph_index then
        debug("failure", "no good paragraph")
        remove_widows_fail()
        return head
    end

    -- Move the last line of the page to the next page
    if not move_last_line(head) then
        debug("failure", "can't move last line")
        remove_widows_fail()
        return head
    end

    -- Replace the chosen paragraph with its expanded version
    replace_paragraph(head, paragraph_index)

    -- The final \\box255 needs to be exactly \\vsize tall to avoid
    -- over/underfull box warnings, so we correct any discrepancies
    -- here.
    local new_vpack = vpack(head)
    local new_height_diff = new_vpack.height - vsize
    new_vpack.list = nil
    free(new_vpack)
    -- We need the original height discrepancy in case there are \\vfill's
    local net_height_diff = orig_height_diff - new_height_diff
    local bls = tex.skip.baselineskip
    local bls_width = bls.width
    free(bls)

    if abs(net_height_diff) > 0 and
       -- A difference larger than 0.25\\baselineskip is probably not from
       -- \lwc/, so we let those warnings surface
       abs(net_height_diff) < bls_width / 4
    then
        local bottom_glue = new_node("glue")
        bottom_glue.width = net_height_diff
        last(head).next = bottom_glue
    end

    info(
        "Widow/orphan/broken hyphen successfully removed at paragraph "
        .. paragraph_index
        .. " on page "
        .. pagenum
    )

    reset_state()

    return head
end


local show_costs = false
--- Add the paragraph to the list of paragraphs on the page.
---
--- Called immediately before the page is shipped out so that we can get
--- the costs on the correct side in multi-column layouts.
---
--- To evenly align all of the costs in the margins, we need to know the
--- the exact position of the start and end of the paragraph on the page.
--- This is surprisingly complicated.
---
--- @param head node The box to be shipped out
--- @return true
function lwc.show_costs (head)
    if not show_costs then
        return true
    end

    local pagewidth = tex.pagewidth or layouts.getpagedimensions()

    --- Loop over each sublist, add up the total width, and show the costs.
    ---
    --- @param n node The node to loop over
    --- @param width number The accumulated width so far
    --- @param parent node The parent node of the current list
    --- @return nil
    local function recurse(n, width, parent)
        for m in traverse(n) do
            -- Anything with an \\hbox parent and a width is actual width.
            -- (If it had a \\vbox parent, then n.width would actually be height.)
            local self_width = 0
            if m.id == glue_id and parent.id == hlist_id then
                self_width = effective_glue(m, parent)
            elseif m.width and parent.id == hlist_id then
                self_width = m.width
            end

            -- A node's "shift" attribute is horizontal only if the parent is
            -- a \\vbox. This corresponds to the primatives \\moveleft and
            -- \\moveright. (If the parent is a \\hbox, then n.shift is
            -- vertical and corresponds to \\raise.)
            local shift = 0
            if m.shift and
               (parent.id == vlist_id or
                not is_node(parent))
            then
                shift = m.shift
            end

            width = width + self_width

            local attr = get_attribute(m, paragraph_attribute)
            if attr and abs(attr) % PAGE_MULTIPLE >= SINGLE_LINE then
                attr = -1 * (abs(attr) - SINGLE_LINE)
            end

            local cost = costs[abs(attr or 0)]

            if attr and attr < 0 and cost and m.list then
                -- We've found the end of a marked paragraph!

                -- Generate the \\hbox containing the formatted cost
                local cost_str
                if not cost then
                    return
                elseif cost < math.maxinteger then
                    cost_str = str_format("%.0f", cost)
                else
                    cost_str = "infinite"
                end

                local prev, first
                for letter in cost_str:gmatch(".")  do
                    local curr = new_node("glyph")
                    curr.font = SMALL_FONT
                    curr.char = str_byte(letter)

                    if not first then
                        first = curr
                    else
                        prev.next = curr
                    end
                    prev = curr
                end

                local text = hpack(colour_list(first, "cost"))

                -- Make an \\hss to make sure that our `\\hbox`es aren't overfull
                local hss = new_node("glue")
                hss.stretch = 1
                hss[stretch_order] = 1
                hss.shrink = 1
                hss[shrink_order] = 1

                local hbox
                local offset = new_node("glue")

                if (width >= pagewidth / 2) or
                   (m.width >= 0.4 * pagewidth)
                then -- Right column or single-column
                    -- Costs in the right margin
                    offset.width = (
                        pagewidth -
                        width -
                        m.width -
                        shift -
                        tex_dimen[draft_offset]
                    )
                    text.next = hss
                    hbox = hpack(text, 0, "exactly")
                else -- Left column
                    -- Costs in the left margin
                    offset.width = (
                        tex_dimen[draft_offset] -
                        m.width -
                        width -
                        shift
                    )
                    hss.next = text
                    hbox = hpack(hss, 0, "exactly")
                end

                last(m.list).next = offset
                offset.next = hbox
            elseif m.list then
                recurse(m.list, width - self_width + shift, m)
            end
        end
    end

    -- Start at the root of the page
    recurse(head.list, (tex.hoffset or 0) + horigin, {})

    -- LaTeX requires us to always return true here
    return true
end


--- Create a table of functions to enable or disable a given callback
---
--- @param t table Parameters of the callback to create
---     callback: string = The \LuaTeX{} callback name
---     func: function = The function to call
---     name: string = The name/ID of the callback
---     category: string = The category for a \ConTeXt{} "Action"
---     position: string = The "position" for a \ConTeXt{} "Action"
---     lowlevel: boolean = If we should use a lowlevel \LuaTeX{} callback
---                         instead of a \ConTeXt{} "Action"
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
        -- Some of the callbacks in \ConTeXt{} have no associated "actions".
        -- Unlike with \LuaTeX{}base, \ConTeXt{} leaves some \LuaTeX{} callbacks
        -- unregistered and unfrozen. Because of this, we need to register some
        -- callbacks at the engine level. This is fragile though, because a
        -- future \ConTeXt{} update may decide to register one of these
        -- functions, in which case \lwc/ will crash with a cryptic error
        -- message.
        return {
            enable = function() callback.register(t.callback, t.func) end,
            disable = function() callback.register(t.callback, nil) end,
        }
    elseif optex then -- Op\TeX{} is luckily very similar to luatexbase
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
    show_costs = register_callback({
        callback = "pre_shipout_filter",
        func     = lwc.show_costs,
        name     = "show_costs",
        category = "shipouts",
        position = "finishers",
    }),
}


local lwc_enabled = false
--- Enables the paragraph callbacks
function lwc.enable_callbacks()
    debug("callbacks", "enabling")
    if not lwc_enabled then
        lwc.callbacks.save_paragraphs.enable()
        lwc.callbacks.mark_paragraphs.enable()

        lwc_enabled = true
    else
        info("Already enabled")
    end
end


--- Disables the paragraph callbacks
function lwc.disable_callbacks()
    debug("callbacks", "disabling")
    if lwc_enabled then
        lwc.callbacks.save_paragraphs.disable()
        lwc.callbacks.mark_paragraphs.disable()

        -- We do *not* disable `remove_widows` callback, since we still want
        -- to expand any of the previously-saved paragraphs if we hit an orphan
        -- or a widow.
        lwc_enabled = false
    else
        info("Already disabled")
    end
end

function lwc.if_lwc_enabled()
    debug("iflwc")
    if lwc_enabled then
        insert_token(iftrue)
    else
        insert_token(iffalse)
    end
end


--- Mangles a macro name so that it's suitable for a specific format
---
--- @param name string The plain name
--- @param args table<string> The TeX types of the function arguments
--- @return string name The mangled name
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
---
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

        -- An intermediate function that properly "scans" for its arguments
        -- in the \TeX{} side.
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

--[[ Make all of the \lwc/ Lua commands available from \TeX{}
  ]]
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
register_tex_cmd(
    "show_costs",
    function(str)
        show_costs = str ~= "0" and str ~= "false" and str ~= "stop"
    end,
    { "string" }
)
register_tex_cmd(
    "show_colours",
    function(str)
        show_colours = str ~= "0" and str ~= "false" and str ~= "stop"
    end,
    { "string" }
)
register_tex_cmd(
    "pre_shipout",
    function(box)
        luatexbase.call_callback('pre_shipout_filter', tex_box[box])
    end,
    { "int" }
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
--- luatexbase puts an info message in the log. This completely fills the log
--- file with useless error messages, so we disable it here.
---
--- This uses the Lua `debug` library to internally modify the log upvalue in
--- the `add_to_callback` function. This is almost certainly a terrible idea,
--- but I don't know of a better way to do it.
---
--- @return nil
local function silence_luatexbase()
    local debug_lib = require("debug")

    -- On TL24, the `debug` library no longer exists, so there's nothing that
    -- we can do here.
    if not debug_lib or
       not debug_lib.getinfo or
       not debug_lib.getupvalue or
       not debug_lib.setupvalue then
        return
    end

    local nups = debug_lib.getinfo(luatexbase.add_to_callback).nups

    for i = 1, nups do
        local name, func = debug_lib.getupvalue(luatexbase.add_to_callback, i)
        if name == "luatexbase_log" then
            debug_lib.setupvalue(
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


-- Call `silence_luatexbase` in Plain and LaTeX, unless the undocmented global
-- `LWC_NO_DEBUG` is set. We provide this opt-out in case something goes awry
-- with the `debug` library calls.
if (plain or latex) and
   not LWC_NO_DEBUG --- @diagnostic disable-line
then
    silence_luatexbase()
end

-- Register colours for ConTeXt
if context then
    for colour, values in pairs(lwc.colours) do
        attributes.colors.defineprocesscolor(
            "lwc_" .. colour,
            str_format("r=%.2f, g=%.2f, b=%.2f", table.unpack(values))
        )
    end
end

-- Activate \lwc/
lwc.callbacks.remove_widows.enable()
lwc.callbacks.show_costs.enable()

return lwc


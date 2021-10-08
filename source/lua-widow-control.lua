--[[
    lua-widow-control
    https://github.com/gucci-on-fleek/lua-widow-control
    SPDX-License-Identifier: MPL-2.0+
    SPDX-FileCopyrightText: 2021 gucci-on-fleek
  ]]

lwc = {}
lwc.name = "lua-widow-control"

--[[
    \lwc/ is intended to be format-agonistic. It only runs on Lua\TeX{},
    but there are still some slight differences between formats. Here, we
    detect the format name then set some flags for later processing.
  ]]
local format = tex.formatname

-- Save some local copies of the node library to reduce table lookups
local last = node.slide
local copy = node.copy_list
local par_id = node.id("par")
local glue_id = node.id("glue")
local set_attribute = node.set_attribute
local has_attribute = node.has_attribute

if format:find('cont') then -- cont-en, cont-fr, cont-nl, ...
    lwc.context = true
elseif format:find('latex') then -- lualatex, lualatex-dev, ...
    lwc.latex = true
elseif format == 'luatex' then -- Plain
    lwc.plain = true
end

--[[
    This warning is raised in the following circumstances:
      - When the user manually loads the Lua module without loading Lua\TeX{}Base
      - When the package is used with an unsupported format
    Both of these are pretty unlikely.
  ]]

assert(lwc.context or luatexbase, [[
    
    This module requires a supported callback library. Please
    follow the following format-dependant instructions:
      - LaTeX: Use a version built after 2015-01-01, or include
              `\usepackage{luatexbase}' before loading this module.
      - Plain: Include `\input ltluatex' before loading this module.
      - ConTeXt: Use the LMTX version.
]])

if lwc.context then
    lwc.warning = logs.reporter("module", lwc.name)
    lwc.attribute = attributes.public(lwc.name)
    lwc.contrib_head = 'contribute_head' -- For \LuaMetaTeX{}
    node.flush_list = node.flushlist
elseif lwc.plain or lwc.latex then
    luatexbase.provides_module {
        name = lwc.name,
        date = "2021/06/24",
        version = "v0.00",
        description = [[

    This module provides a LuaTeX-based solution to prevent
    widows and orphans from appearing in a document. It does
    so by increasing or decreasing the lengths of previous
    paragraphs.
        ]],
    }
    lwc.warning = function(str) luatexbase.module_warning(lwc.name, str) end
    lwc.attribute = luatexbase.new_attribute(lwc.name)
    lwc.contrib_head = 'contrib_head' -- For \LuaTeX{}
end

--[[
    Here we initialize a bunch of module-level variables and constants.
  ]]

lwc.paragraphs = {} -- List to hold the alternate paragraph versions

if tex.interlinepenalty ~= 0 then
    lwc.warning [[
\interlinepenalty is set to a non-zero value.
This may prevent lua-widow-control from 
properly functioning.
]]
end

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
function lwc.register_callback(t)
    if lwc.plain or lwc.latex then
        return {
            enable = function()
                luatexbase.add_to_callback(t.callback, t.func, t.name)
            end,
            disable = function()
                luatexbase.remove_from_callback(t.callback, t.name)
            end,
        }
    elseif lwc.context and not t.lowlevel then
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
    elseif lwc.context and t.lowlevel then
        --[[
            Some of the callbacks in \ConTeXt{} have no associated "actions". Unlike
            with \LuaTeX{}base, \ConTeXt{} leaves some \LuaTeX{} callbacks unregistered
            and unfrozen. Because of this, we need to register some callbacks at the
            engine level.
          ]]
        return {
            enable = function() callback.register(t.callback, t.func) end,
            disable = function() callback.register(t.callback, nil) end,
        }
    end
end

-- Saves each paragraph, but lengthened by 1 line
function lwc.save_paragraphs(head)
    -- Prevent the "underfull hbox" warnings when we store a potential paragraph
    lwc.callbacks.disable_box_warnings.enable()

    if head.id ~= par_id and lwc.context then
        -- Not too sure why this is necessary, but \ConTeXt{} crashes without it
        return head
    end

    local new_head = copy(head)

    -- Prevent ultra-short last lines (TeXBook p. 104), except with narrow columns
    local parfillskip = last(new_head)
    if parfillskip.id == glue_id and tex.hsize > tex.sp("25em") then
            parfillskip.stretch_order = 0
            parfillskip.stretch = 0.9 * tex.hsize
    end

    local long_node, long_info = tex.linebreak(new_head, {
        looseness = 1,
        emergencystretch = tex.dimen.lwcemergencystretch,
    })

    local natural_node, natural_info = tex.linebreak(copy(head))
    node.flush_list(natural_node)

    lwc.callbacks.disable_box_warnings.disable()

    -- If we can't change the length of a paragraph, assign a very large demerit value
    local long_demerits
    if long_info.prevgraf == natural_info.prevgraf then
        long_demerits = 1073741823 -- \\maxdimen
    else
        long_demerits = long_info.demerits
    end

    tex.prevdepth = long_info.prevdepth

    table.insert(lwc.paragraphs, {demerits = long_demerits, node = long_node})

    --[[
        \LuaMetaTeX{} crashes if we return `true`. However, page 175 of the \LuaMetaTeX{}
        manual says:

        "As for all the callbacks that deal with nodes, the return value can be one
        of three things:
          - boolean true signals successful processing
          - <node> signals that the ‘head’ node should be replaced by the returned node
          - boolean false signals that the ‘head’ node list should be ignored and
            flushed from memory"
      ]]
    return head
end

-- Tags the beginning and the end of each paragraph as it is added to the page
function lwc.mark_paragraphs(head)
    set_attribute(head, lwc.attribute, #lwc.paragraphs)
    set_attribute(last(head), lwc.attribute, -1 * #lwc.paragraphs)

    return head
end

--[[
    This function holds the majority of the module's functionality. It is called
    just after the end of the output routine, before the page is shipped out. If
    the output penalty indicates that the page was broken at a widow or an orphan,
    we replace one paragraph with the same paragraph, but lengthened by one line.
    Then, we can push the bottom line of the page to the next page.
  ]]
function lwc.remove_widows(head)
    local penalty = tex.outputpenalty
    local paragraphs = lwc.paragraphs

    --[[
        We only need to process pages that have orphans or widows.

        If the paragraphs array is empty, then there is nothing that we can do.
      ]]
    if  penalty >=  10000 or
        penalty <= -10000 or
        penalty ==      0 or
        #paragraphs == 0 then
            return head
    end

    local head_save = head -- Save the head to return at the end

    --[[
        Find the paragraph on the page with the minimum penalty.

        This would be a 1-liner in Python or JavaScript, but Lua is pretty low-level,
        so there's quite a bit of code here.
      ]]
    local paragraph_index = 1
    local minimum_demerits = paragraphs[paragraph_index].demerits

    for i, paragraph in pairs(paragraphs) do
        if paragraph.demerits < minimum_demerits and i <= #paragraphs - 1 then
            node.flush_list(paragraphs[paragraph_index].node)
            paragraphs[paragraph_index].node = nil
            paragraph_index, minimum_demerits = i, paragraph.demerits
        elseif i > 1 then
            -- Not sure why `i > 1` is required?
            node.flush_list(paragraph.node)
            paragraph.node = nil
        end
    end

    local target_node = paragraphs[paragraph_index].node
    local clear_flag = false

    while head do
        -- Insert the start of the replacement paragraph
        if has_attribute(head, lwc.attribute, paragraph_index) then
            head.prev.next = target_node
            clear_flag = true
        end

        -- Insert the end of the replacement paragraph
        if has_attribute(head, lwc.attribute, -1 * paragraph_index) then
            last(target_node).next = head.next
            clear_flag = false
        end

        -- Start of final paragraph
        if has_attribute(head, lwc.attribute, #paragraphs) then
            local last_line = copy(last(head))

            last(last_line).next = copy(tex.lists[lwc.contrib_head])

            last(head).prev.prev.next = nil
            tex.lists[lwc.contrib_head] = last_line
        end

        if clear_flag then
            head = node.free(head)
        else
            head = head.next
        end
    end

    lwc.paragraphs = {} -- Clear paragraphs array at the end of the page

    return head_save
end


lwc.callbacks = {
    disable_box_warnings = lwc.register_callback({
        callback = "hpack_quality",
        func     = function() end,
        name     = "disable_box_warnings",
        lowlevel = true,
    }),
    remove_widows = lwc.register_callback({
        callback = "pre_output_filter",
        func     = lwc.remove_widows,
        name     = "remove_widows",
        lowlevel = true,
    }),
    save_paragraphs = lwc.register_callback({
        callback = "pre_linebreak_filter",
        func     = lwc.save_paragraphs,
        name     = "save_paragraphs",
        category = "processors",
        position = "after",
    }),
    mark_paragraphs = lwc.register_callback({
        callback = "post_linebreak_filter",
        func     = lwc.mark_paragraphs,
        name     = "mark_paragraphs",
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
        lwc.warning("Already enabled")
    end
end


function lwc.disable_callbacks()
    if enabled then
        lwc.callbacks.save_paragraphs.disable()
        lwc.callbacks.mark_paragraphs.disable()

        enabled = false
    else
        lwc.warning("Already disabled")
    end
end


return lwc

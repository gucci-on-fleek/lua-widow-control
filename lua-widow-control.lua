lwc = {}
lwc.name = "lua-widow-control"

local format = tex.formatname

if format:find('cont') then
    lwc.context = true
elseif format:find('latex') then
    lwc.latex = true
elseif format == 'luatex' then
    lwc.plain = true
end

assert(lwc.context or luatexbase, [[
    This module requires a supported callback library. Please
    follow the following format-dependant instructions:
      - LaTeX: Use a version built after 2015-01-01, or include
              `\usepackage{luatexbase}' before loading this module.
      - Plain: Include `\input ltluatex' before loading this module.
      - ConTeXt: Use the LMTX or MKIV versions.
]])

if lwc.context then
    lwc.warning = logs.reporter("module", lwc.name)
    lwc.attribute = attributes.public(lwc.name)
elseif lwc.plain or lwc.latex then
    luatexbase.provides_module{
        name = lwc.name,
        date = "2021/06/24",
        version = "v0.00",
        description = [[
            This module provides a LuaTeX-based solution to prevent
            widows and orphans from appearing in a document. It does
            so by increasing or decreasing the lengths of previous
            paragraphs.
        ]]
    }
    lwc.warning = function(str)
        luatexbase.module_warning(lwc.name, str)
    end
    lwc.attribute = luatexbase.new_attribute(lwc.name)
end

lwc.paragraphs = {} -- List to hold the alternate paragraph versions
lwc.emergency_stretch = tex.sp("3em") -- \emergencystretch value for adjusted paragraphs
lwc.max_demerits = 1000000 -- Demerits assigned when a paragraph can't adjusted
lwc.club_penalty = tex.clubpenalty
lwc.widow_penalty = tex.widowpenalty
lwc.broken_club_penalty = tex.clubpenalty + tex.brokenpenalty
lwc.broken_widow_penalty = tex.widowpenalty + tex.brokenpenalty

if lwc.club_penalty == lwc.widow_penalty then
    lwc.warning [[
        \clubpenalty and \widowpenalty both have the same value.
        This will prevent the package from distinguishing between
        orphans and widows and will almost certainly lead to
        undesirable behavior.
        ]]
end

function lwc.register_callback(t)
    if lwc.plain or lwc.latex then
        return {
            enable = function () luatexbase.add_to_callback(t.callback, t.func, t.name) end,
            disable = function () luatexbase.remove_from_callback(t.callback, t.name) end,
        }
    elseif lwc.context and not t.lowlevel then
       return {
            enable = nodes.tasks.appendaction(t.category, t.position, "lwc." .. t.name) or function () nodes.tasks.enableaction(t.category, "lwc." .. t.name) end,
            disable = function () nodes.tasks.disableaction(t.category, "lwc." .. t.name) end,
        }
    elseif lwc.context and t.lowlevel then
        return {
            enable = function () callback.register(t.callback, t.func) end,
            disable = function () callback.register(t.callback, nil) end,
        }
    end
end


function lwc.save_paragraphs(head, groupcode)
    -- Prevent the "underfull hbox" warnings when we store a potential paragraph
    lwc.callbacks.disable_box_warnings.enable()

    if head.id ~= node.id("par") then
        return head
    end

    local new_head = node.copy_list(head)

    -- Prevent ultra-short last lines (TeXBook p. 104)
    local parfillskip = node.slide(new_head)
    parfillskip.stretch_order = 0
    parfillskip.stretch = 0.9 * tex.hsize

    local long_node, long_info = tex.linebreak(new_head, {
        looseness = 1,
        emergencystretch = lwc.emergency_stretch
    })

    lwc.callbacks.disable_box_warnings.disable()

    -- If we can't change the length of a paragraph, assign a very large demerit value
    local long_demerits
    if long_info.looseness == 0 then
        long_demerits = lwc.max_demerits
    else
        long_demerits = long_info.demerits
    end

    table.insert(lwc.paragraphs, {
        demerits = long_demerits,
        node = long_node
    })

    return head
end

function lwc.mark_paragraphs(head)
    node.set_attribute(head, lwc.attribute, #lwc.paragraphs)
    node.set_attribute(node.slide(head), lwc.attribute, -1 * #lwc.paragraphs)

    return head
end


function lwc.remove_widows(head)
    local head_save = head -- Save the head to return at the end
    local penalty = tex.outputpenalty
    local paragraphs = lwc.paragraphs

    if penalty ~= lwc.club_penalty and penalty ~= lwc.widow_penalty and penalty ~= lwc.broken_club_penalty and penalty ~= lwc.broken_widow_penalty then
        -- We only need to process paragraphs with orphans or widows
        return head_save
    end

    if #paragraphs == 0 then
        -- Callbacks were enabled at a page break
        return head_save
    end

    local paragraph_index = 1
    local minimum_demerits = paragraphs[paragraph_index].demerits

    for i, x in pairs({table.unpack(paragraphs, 1, #paragraphs - 1)}) do
        if paragraphs[i].demerits < minimum_demerits then
            paragraph_index, minimum_demerits = i, x.demerits
        end
    end

    local target_node = paragraphs[paragraph_index].node

    while head do
        if node.has_attribute(head, lwc.attribute, paragraph_index) then
            -- Insert the start of the replacement paragraph
            head.prev.next = target_node
        end

        if node.has_attribute(head, lwc.attribute, -1 * paragraph_index) then
            -- Insert the end of the replacement paragraph
            node.slide(target_node).next = head.next
        end

        -- Start of final paragraph
        if node.has_attribute(head, lwc.attribute, #paragraphs) then
            if penalty == lwc.club_penalty or penalty == lwc.broken_club_penalty then
                -- Move last line to next page
                tex.lists.contrib_head = paragraphs[#paragraphs].node
                head.prev.next = nil

            elseif penalty == lwc.widow_penalty or penalty == lwc.broken_widow_penalty then
                -- Insert last line on top of next page
                local last_line = node.copy_list(node.slide(head))

                node.slide(last_line).next = node.copy_list(tex.lists.contrib_head)

                node.slide(head).prev.prev.next = nil
                tex.lists.contrib_head = nil
                tex.lists.contrib_head = last_line
            end
        end
        head = head.next
    end

    lwc.paragraphs = {} -- Clear paragraphs array at the end of the page

    return head_save
end


lwc.callbacks = {
    disable_box_warnings = lwc.register_callback({
        callback = "hpack_quality",
        func     = function() end,
        name     = "disable_box_warnings",
        lowlevel = true
    }),
    remove_widows = lwc.register_callback({
        callback = "pre_output_filter",
        func     = lwc.remove_widows,
        name     = "remove_widows",
        lowlevel = true
    }),
    save_paragraphs = lwc.register_callback({
        callback = "pre_linebreak_filter",
        func     = lwc.save_paragraphs,
        name     = "save_paragraphs",
        category = "processors",
        position = "after"
    }),
    mark_paragraphs = lwc.register_callback({
        callback = "post_linebreak_filter",
        func     = lwc.mark_paragraphs,
        name     = "mark_paragraphs",
        category = "finalizers",
        position = "after"
    }),
}


function lwc.enable_callbacks()
    lwc.callbacks.remove_widows.enable()
    lwc.callbacks.save_paragraphs.enable()
    lwc.callbacks.mark_paragraphs.enable()
end


function lwc.disable_callbacks()
    lwc.callbacks.remove_widows.disable()
    lwc.callbacks.save_paragraphs.disable()
    lwc.callbacks.mark_paragraphs.disable()
end


return lwc

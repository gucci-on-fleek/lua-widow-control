lwc = {}
lwc.name = "lua-widow-control"

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

lwc.paragraphs = {} -- List to hold the alternate paragraph versions
lwc.emergency_stretch = tex.sp("10em") -- \emergencystretch value for adjusted paragraphs
lwc.max_demerits = 10000 -- Demerits assigned when a paragraph can't adjusted
lwc.club_penalty = tex.clubpenalty
lwc.widow_penalty = tex.widowpenalty
lwc.broken_club_penalty = tex.clubpenalty + tex.brokenpenalty
lwc.broken_widow_penalty = tex.widowpenalty + tex.brokenpenalty
lwc.attribute = luatexbase.new_attribute("lua-widow-control")

if lwc.club_penalty == lwc.widow_penalty then
    luatexbase.module_warning(lwc.name, [[
        \clubpenalty and \widowpenalty both have the same value.
        This will prevent the package from distinguishing between
        orphans and widows and will almost certainly lead to
        undesirable behavior.
        ]])
end


function lwc.linebreak(head, params)
    local new_head = node.copy_list(head)

    -- Prevent ultra-short last lines (TeXBook p. 104)
    local parfillskip = node.slide(new_head)
    parfillskip.stretch_order = 0
    parfillskip.stretch = 0.9 * tex.hsize

    return tex.linebreak(new_head, params)
end


function lwc.save_paragraphs(head)
    -- Produce the regular paragraph
    local natural_node, natural_info = tex.linebreak(node.copy_list(head))

    -- Prevent the "underfull hbox" warnings when we store a potential paragraph
    luatexbase.add_to_callback("hpack_quality", function() end, "disable-box-warnings")
    local long_node, long_info = lwc.linebreak(head, {
        looseness = 1,
        emergencystretch = lwc.emergency_stretch
    })
    luatexbase.remove_from_callback("hpack_quality", "disable-box-warnings")

    -- If we can't change the length of a paragraph, assign a very large demerit value
    local long_demerits
    if long_info.looseness == 0 then
        long_demerits = lwc.max_demerits
    else
        long_demerits = long_info.demerits
    end

    table.insert(lwc.paragraphs, {
        demerits = long_demerits,
        node = long_node,
        lines = natural_info.prevgraf
    })

    -- Set attributes on the first and last node of the original paragraph so that
    -- we can find and remove it later.
    node.set_attribute(natural_node, lwc.attribute, #lwc.paragraphs)
    node.set_attribute(node.slide(natural_node), lwc.attribute, -1 * #lwc.paragraphs)

    tex.prevdepth = natural_info.prevdepth -- https://tex.stackexchange.com/a/403813

    return natural_node
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

    for i, x in pairs(paragraphs) do
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
                node.write(paragraphs[#paragraphs].node)
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


function lwc.enable_callbacks()
    luatexbase.add_to_callback("pre_output_filter", lwc.remove_widows, "remove-widows")
    luatexbase.add_to_callback("linebreak_filter", lwc.save_paragraphs, "save-paragraphs")
end


function lwc.disable_callbacks()
    luatexbase.remove_from_callback("pre_output_filter", "remove-widows")
    luatexbase.remove_from_callback("linebreak_filter", "save-paragraphs")
end


return lwc

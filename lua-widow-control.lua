lwc = {} -- Lua Widow Control

lwc.paragraphs = {}
lwc.emergency_stretch = tex.sp("10em")
lwc.max_demerits = 10000
lwc.club_penalty = tex.clubpenalty
lwc.widow_penalty = tex.widowpenalty
lwc.attribute = luatexbase.new_attribute("lua-widow-control")

function lwc.linebreaker(head)
    local natural_node, natural_info = tex.linebreak(node.copy_list(head))
    local tight_node, tight_info = tex.linebreak(node.copy_list(head), {looseness = -1, emergencystretch = lwc.emergency_stretch})
    local loose_node, loose_info = tex.linebreak(node.copy_list(head), {looseness = 1, emergencystretch = lwc.emergency_stretch})

    local loose_demerits, tight_demerits, demerits, best_node

    if tight_info.looseness == 0 then
        tight_demerits = lwc.max_demerits
    else
        tight_demerits = tight_info.demerits
    end

    if loose_info.looseness == 0 then
        loose_demerits = lwc.max_demerits
    else
        loose_demerits = loose_info.demerits
    end

    if loose_demerits < tight_demerits then
        demerits = loose_demerits
        best_node = loose_node
    else
        demerits = tight_demerits
        best_node = tight_node 
    end

    table.insert(lwc.paragraphs, {demerits = demerits, node = best_node, lines = natural_info.prevgraf})

    node.set_attribute(natural_node, lwc.attribute, #lwc.paragraphs)
    node.set_attribute(node.slide(natural_node), lwc.attribute, -1 * #lwc.paragraphs)

    tex.prevdepth = natural_info.prevdepth
    return natural_node
end

function lwc.fix_orphans_widows(head)
    local head_save = head
    local penalty = tex.outputpenalty
    local paragraphs = lwc.paragraphs

    if penalty ~= lwc.club_penalty and penalty ~= lwc.widow_penalty then
        return head_save
    end

    local key = 1
    local min = paragraphs[key].demerits

    for k, v in pairs(paragraphs) do
        if paragraphs[k].demerits < min then
            key, min = k, v.demerits
        end
    end

    local target_node = paragraphs[key].node

    while head do
        if node.has_attribute(head, lwc.attribute, key) then
            head.prev.next = target_node
        end
        if node.has_attribute(head, lwc.attribute, -1 * key) then
            node.slide(target_node).next = head.next
        end
        if node.has_attribute(head, lwc.attribute, #paragraphs) then
            if penalty == lwc.club_penalty then
                node.write(paragraphs[#paragraphs].node)
                head.prev.next = nil
            elseif penalty == lwc.widow_penalty then
                local last_line = node.copy_list(head.next.next)
                node.slide(last_line).next = node.copy_list(tex.lists.contrib_head)
                head.next.next = nil
                tex.lists.contrib_head = nil
                tex.lists.contrib_head = last_line
            end
        end
        head = head.next
    end

    return head_save
end


luatexbase.add_to_callback("pre_output_filter", lwc.fix_orphans_widows, "Expands or shrinks a paragraph on the page to remove orphans and widows.")
luatexbase.add_to_callback("linebreak_filter", lwc.linebreaker, "Takes over paragraph formation to save paragraphs with different lengths.")
luatexbase.add_to_callback("hpack_quality", function() end, "hpack_quality")

return lwc

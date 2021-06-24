lua_widow_control = lua_widow_control or {}
lua_widow_control.paragraphs = {}
lua_widow_control.emergencystretch = tex.sp("10em")

function lua_widow_control.linebreaker(head)
    local natural_node, natural_info = tex.linebreak(node.copy_list(head))
    local tight_node, tight_info = tex.linebreak(node.copy_list(head), {looseness = -1, emergencystretch = lua_widow_control.emergencystretch})
    local loose_node, loose_info = tex.linebreak(node.copy_list(head), {looseness = 1, emergencystretch = lua_widow_control.emergencystretch})

    local loose_demerits, tight_demerits, demerits, best_node

    if tight_info.looseness == 0 then
        tight_demerits = 10000
    else
        tight_demerits = tight_info.demerits
    end

    if loose_info.looseness == 0 then
        loose_demerits = 10000
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

    table.insert(lua_widow_control.paragraphs, {demerits = demerits, node = best_node, lines = natural_info.prevgraf})

    node.set_attribute(natural_node, 999, #lua_widow_control.paragraphs)
    node.set_attribute(node.slide(natural_node), 999, -1 * #lua_widow_control.paragraphs)

    tex.prevdepth = natural_info.prevdepth
    return natural_node
end

function lua_widow_control.fix_orphans_widows(head)
    local head_save = head
    local penalty = tex.outputpenalty
    local paragraphs = lua_widow_control.paragraphs
    
    if penalty ~= 3 and penalty ~= 5 then
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
        if node.has_attribute(head, 999, key) then
            head.prev.next = target_node
        end
        if node.has_attribute(head, 999, -1 * key) then
            node.slide(target_node).next = head.next
        end
        if node.has_attribute(head, 999, #paragraphs) then
            if penalty==3 then
                node.write(paragraphs[#paragraphs].node)
                head.prev.next = nil
            elseif penalty==5 then
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


luatexbase.add_to_callback("pre_output_filter", lua_widow_control.fix_orphans_widows, "Expands or shrinks a paragraph on the page to remove orphans and widows.")
luatexbase.add_to_callback("linebreak_filter", lua_widow_control.linebreaker, "Takes over paragraph formation to save paragraphs with different lengths.")
luatexbase.add_to_callback("hpack_quality", function() end, "hpack_quality")

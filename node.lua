local json = require "json"

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

local font = resource.load_font("font.ttf")
local offline_logo = resource.load_image("offline-logo.png")
local white = resource.create_colored_texture(1, 1, 1, 1)
local black = resource.create_colored_texture(0, 0, 0, 1)
local surface = resource.create_colored_texture(1, 1, 1, 1)
local divider = resource.create_colored_texture(0.90, 0.91, 0.93, 1)
local placeholder = resource.create_colored_texture(1, 1, 1, 1)
local saber_bands = {}
for index = 1, 12 do
    local width = 46 - (index - 1) * 3.5
    local alpha = 0.014 + index * 0.006
    saber_bands[#saber_bands + 1] = {
        width = width,
        texture = resource.create_colored_texture(0.05, 0.64, 0.94, alpha),
    }
end
local saber_core = resource.create_colored_texture(0.78, 0.96, 1, 0.72)
local config = { display_profile = "3840x1080", output_rotation = "0", playback_mode = "static", hide_hotfoods_always = false, page_duration_seconds = 25, combo_upgrades_placement = "popcorn", combo_font_scale_percent = 100, alacarte_font_scale_percent = 100, refreshing_drinks_title_font_scale_percent = 100, refreshing_drinks_font_scale_percent = 100, hotfoods_font_scale_percent = 100, tax_font_scale_percent = 100, theme_overlay_fit = "stretch", theme_overlay_opacity_percent = 100, debug = false }
local state = nil
local font_region = nil
local theme_overlay = nil
local theme_overlay_asset = nil
local images = {}
local ad_media = {}
local ad_media_errors = {}
local last_ad_error = nil
local last_manifest_version = nil

local profiles = {
    ["3840x1080"] = {3840, 1080},
    ["2160x3840"] = {2160, 3840},
    ["1920x1080"] = {1920, 1080},
    ["3840x2160"] = {3840, 2160},
}

local function sorted_available(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        if value.available ~= false and value.schedule_visible ~= false then out[#out + 1] = value end
    end
    table.sort(out, function(a, b)
        if (a.display_order or 0) == (b.display_order or 0) then return (a.name or "") < (b.name or "") end
        return (a.display_order or 0) < (b.display_order or 0)
    end)
    return out
end

local function money(value)
    if value.effective_display_price and value.effective_display_price ~= "" then return value.effective_display_price end
    if value.display_price and value.display_price ~= "" then return value.display_price end
    return string.format("$%.2f", tonumber(value.price) or 0)
end

local function load_media(manifest)
    images = {}
    ad_media = {}
    ad_media_errors = {}
    last_ad_error = nil
    local function load(path)
        if path and path ~= "" and not images[path] then
            local ok, result = pcall(resource.load_image, path)
            if ok then images[path] = result end
        end
    end
    for _, combo in ipairs(manifest.combos or {}) do load(combo.local_image) end
    for _, category in ipairs(manifest.categories or {}) do
        load(category.local_image)
        for _, item in ipairs(category.items or {}) do load(item.local_image) end
    end
    for _, category in ipairs(manifest.hotfoods_categories or {}) do
        load(category.local_image)
        for _, item in ipairs(category.items or {}) do load(item.local_image) end
    end
    for _, ad in ipairs(manifest.advertisements or {}) do
        local path = ad.local_media
        if path and path ~= "" then
            if ad.media_type == "video" then
                local ok, result = pcall(resource.load_video, {file=path, audio=false, looped=true, paused=false})
                if ok then ad_media[path] = {resource=result, media_type="video"} end
            else
                local ok, result = pcall(resource.load_image, path)
                if ok then ad_media[path] = {resource=result, media_type="image"} end
            end
        end
    end
    for _, media in ipairs(manifest.hotfoods_media or {}) do
        local path = media.local_media
        if path and path ~= "" and not ad_media[path] then
            if media.media_type == "video" then
                local ok, result = pcall(resource.load_video, {file=path, audio=false, looped=true, paused=false})
                if ok then ad_media[path] = {resource=result, media_type="video"} end
            else
                local ok, result = pcall(resource.load_image, path)
                if ok then ad_media[path] = {resource=result, media_type="image"} end
            end
        end
    end
end

local function load_theme_overlay(value)
    local selected = value and value.theme_overlay
    local asset = type(selected) == "table" and selected.asset_name or nil
    if not asset or asset == "" then asset = "transparent-overlay.png" end
    if asset == theme_overlay_asset then return end
    theme_overlay_asset = asset
    local ok, result = pcall(resource.load_image, asset)
    theme_overlay = ok and result or nil
    if not ok then print("theme overlay load failed: " .. tostring(asset)) end
end

util.json_watch("config.json", function(value)
    config = value or config
    load_theme_overlay(config)
end)

load_theme_overlay(config)

util.json_watch("state.json", function(value)
    state = value
    if state and state.manifest and state.manifest.manifest_version ~= last_manifest_version then
        last_manifest_version = state.manifest.manifest_version
        load_media(state.manifest)
    end
end)

local function scaled_font_size(size)
    local legacy = tonumber(config.font_scale_percent) or 100
    local configured = legacy
    if font_region == "combo" then
        configured = tonumber(config.combo_font_scale_percent) or legacy
    elseif font_region == "alacarte" then
        configured = tonumber(config.alacarte_font_scale_percent) or legacy
    elseif font_region == "refreshing_drinks" then
        configured = tonumber(config.refreshing_drinks_font_scale_percent) or tonumber(config.alacarte_font_scale_percent) or legacy
    elseif font_region == "refreshing_drinks_title" then
        configured = tonumber(config.refreshing_drinks_title_font_scale_percent) or tonumber(config.alacarte_font_scale_percent) or legacy
    elseif font_region == "hotfoods" then
        configured = tonumber(config.hotfoods_font_scale_percent) or legacy
    elseif font_region == "tax" then
        configured = tonumber(config.tax_font_scale_percent) or legacy
    end
    local minimum = font_region == "tax" and 50 or 75
    local percent = math.max(minimum, math.min(250, configured))
    return size * percent / 100
end

local function display_string(value)
    local value_type = type(value)
    if value_type == "string" or value_type == "number" then return tostring(value) end
    return ""
end

local function text(x, y, value, size, r, g, b, a)
    font:write(x, y, display_string(value), scaled_font_size(size), r or 0.05, g or 0.08, b or 0.13, a or 1)
end

local function centered(x1, x2, y, value, size, color)
    local width = font:width(display_string(value), scaled_font_size(size))
    text(x1 + math.max(0, (x2 - x1 - width) / 2), y, value, size, unpack(color or {0.05, 0.08, 0.13, 1}))
end

local function wrapped_centered(x1, x2, y, value, size, line_height, max_lines, color)
    local words, lines, current = {}, {}, ""
    for word in display_string(value):gmatch("%S+") do words[#words + 1] = word end
    local max_width = x2 - x1
    for _, word in ipairs(words) do
        local candidate = current == "" and word or current .. " " .. word
        if current ~= "" and font:width(candidate, scaled_font_size(size)) > max_width then
            lines[#lines + 1] = current
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = "" end
    while #lines > max_lines do
        lines[max_lines] = lines[max_lines] .. " " .. lines[max_lines + 1]
        table.remove(lines, max_lines + 1)
    end
    for index, line in ipairs(lines) do
        centered(x1, x2, y + (index - 1) * line_height, line, size, color)
    end
end

local function split_two_lines(value, size, max_width)
    local text_value = display_string(value)
    if font:width(text_value, scaled_font_size(size)) <= max_width then return {text_value} end
    local words = {}
    for word in text_value:gmatch("%S+") do words[#words + 1] = word end
    if #words < 2 then return {text_value} end
    local best, best_width = nil, nil
    for split = 1, #words - 1 do
        local first, second = {}, {}
        for index = 1, split do first[#first + 1] = words[index] end
        for index = split + 1, #words do second[#second + 1] = words[index] end
        local lines = {table.concat(first, " "), table.concat(second, " ")}
        local widest = math.max(font:width(lines[1], scaled_font_size(size)), font:width(lines[2], scaled_font_size(size)))
        if not best_width or widest < best_width then best, best_width = lines, widest end
    end
    return best or {text_value}
end

local function fit_image(path, x1, y1, x2, y2)
    local image = images[path]
    if not image then
        placeholder:draw(x1 + 8, y1 + 8, x2 - 8, y2 - 8)
        return
    end
    local status, iw, ih = image:state()
    if status ~= "loaded" or not iw or iw == 0 or not ih or ih == 0 then
        placeholder:draw(x1 + 8, y1 + 8, x2 - 8, y2 - 8)
        return
    end
    local scale = math.min((x2-x1)/iw, (y2-y1)/ih)
    local w, h = iw*scale, ih*scale
    image:draw(x1+(x2-x1-w)/2, y1+(y2-y1-h)/2, x1+(x2-x1+w)/2, y1+(y2-y1+h)/2)
end

local function render_offline_indicator(w, h)
    local status, iw, ih = offline_logo:state()
    if status ~= "loaded" or not iw or not ih or iw == 0 or ih == 0 then return end
    local indicator_h = math.min(w, h) * .055
    local indicator_w = indicator_h * iw / ih
    local margin = math.min(w, h) * .012
    offline_logo:draw(w-margin-indicator_w, h-margin-indicator_h, w-margin, h-margin, .88)
end

local function render_media(values, x1, y1, x2, y2, preserve_aspect, vertical_align)
    local ads = {}
    for _, ad in ipairs(values or {}) do
        local holder = ad_media[ad.local_media]
        if holder then
            local ok, status, detail = pcall(function() return holder.resource:state() end)
            if ok and (status == "loaded" or status == "paused" or status == "finished") then
                ads[#ads + 1] = ad
            elseif ok and status == "error" then
                last_ad_error = tostring(detail or "unknown decoder error")
                if not ad_media_errors[ad.local_media] then
                    ad_media_errors[ad.local_media] = true
                    print("advertisement media error " .. tostring(ad.local_media) .. ": " .. last_ad_error)
                end
            end
        end
    end
    if #ads == 0 then return false end
    local total = 0
    for _, ad in ipairs(ads) do total = total + math.max(1, tonumber(ad.duration_seconds) or 10) end
    local cursor = sys.now() % total
    local selected = ads[1]
    for _, ad in ipairs(ads) do
        cursor = cursor - math.max(1, tonumber(ad.duration_seconds) or 10)
        if cursor < 0 then selected = ad; break end
    end
    local holder = selected and ad_media[selected.local_media]
    if not holder then return false end
    local rendered_height = y2 - y1
    if preserve_aspect and vertical_align == "top" then
        local ok, status, iw, ih = pcall(function() return holder.resource:state() end)
        if ok and iw and ih and iw > 0 and ih > 0 then
            local scale = math.min((x2-x1)/iw, (y2-y1)/ih)
            local draw_w, draw_h = iw*scale, ih*scale
            local draw_x = x1 + ((x2-x1)-draw_w)/2
            holder.resource:draw(draw_x, y1, draw_x+draw_w, y1+draw_h)
            rendered_height = draw_h
        else
            util.draw_correct(holder.resource, x1, y1, x2, y2)
        end
    elseif preserve_aspect then
        util.draw_correct(holder.resource, x1, y1, x2, y2)
    else
        holder.resource:draw(x1, y1, x2, y2)
    end
    return true, rendered_height
end

local function render_advertisement(manifest, x1, y1, x2, y2, preserve_aspect, vertical_align)
    return render_media(manifest.advertisements, x1, y1, x2, y2, preserve_aspect, vertical_align)
end

local function render_combo(manifest, w, h, with_ads)
    font_region = "combo"
    local combos = sorted_available(manifest.combos)
    local margin, gap = w * 0.018, w * 0.008
    local grid_top
    local has_ad, ad_height
    if with_ads and h > w then
        -- Portrait layouts top-align the original artwork and reclaim unused
        -- letterbox space for the combo grid below it.
        has_ad, ad_height = render_advertisement(manifest, 0, 0, w, h * 0.5, true, "top")
    elseif with_ads then
        -- Preserve the established horizontal rendering behavior.
        has_ad, ad_height = render_advertisement(manifest, 0, 0, w, h * 0.5, false)
    end
    if has_ad then
        grid_top = (ad_height or h * 0.5) + margin
    else
        local top = h * 0.035
        centered(0, w, top, "COMBOS", math.min(w, h) * 0.052, {0.03, 0.16, 0.34, 1})
        grid_top = top + math.min(w,h)*0.08
    end
    local columns = (#combos <= 5 and w > h * 0.8) and #combos or math.min(2, #combos)
    columns = math.max(1, columns)
    local rows = math.ceil(#combos / columns)
    local card_w = (w - margin*2 - gap*(columns-1))/columns
    local footer = math.min(w,h) * .025
    local card_h = (h - grid_top - margin - footer - gap*(rows-1))/rows
    for i, combo in ipairs(combos) do
        local col, row = (i-1)%columns, math.floor((i-1)/columns)
        local x1, y1 = margin+col*(card_w+gap), grid_top+row*(card_h+gap)
        local x2, y2 = x1+card_w, y1+card_h
        white:draw(x1, y1, x2, y2)
        local info_h = math.max(card_h*0.34, math.min(w,h)*0.17)
        fit_image(combo.local_image, x1, y1, x2, y2-info_h)
        local title_size = math.min(card_w*0.065, info_h*0.18)
        centered(x1, x2, y2-info_h+info_h*0.08, combo.name, title_size)
        wrapped_centered(x1+card_w*.04, x2-card_w*.04, y2-info_h+info_h*.34, combo.description or "", title_size*.55, title_size*.72, 2)
        centered(x1, x2, y2-info_h+info_h*.70, money(combo), title_size*.92, {0.03, 0.22, 0.52, 1})
    end
    font_region = "tax"
    centered(0, w, h-footer*.85, manifest.screen.tax_disclaimer or "", math.min(w,h)*.014, {0.2,0.25,0.3,1})
    font_region = "combo"
    return has_ad
end

local function render_categories(manifest, w, h)
    font_region = "alacarte"
    local source = sorted_available(manifest.categories)
    local categories, drinks, upgrades = {}, {}, {}
    for _, category in ipairs(source) do
        local name = string.lower(category.name or "")
        if config.hide_hotfoods_always and (name == "hot food" or name == "hot foods") then
            -- Explicit device override: never show Hot Foods on this menu.
        elseif name == "bottled water" or name == "fountain drinks" or name == "icee" or
           name == "drinks" or name == "other drinks" or name == "beverages" or
           name == "refreshing drinks" then
            drinks[#drinks + 1] = category
        elseif name == "combo upgrades" or name == "combo upgrade" then
            upgrades[#upgrades + 1] = category
        else
            categories[#categories + 1] = category
        end
    end
    if #drinks > 0 then categories[#categories + 1] = {name="Refreshing Drinks", groups=drinks} end
    if #upgrades > 0 then
        local placement = config.combo_upgrades_placement or "popcorn"
        local target_name = ({popcorn="popcorn", snacks="snacks", drinks="refreshing drinks"})[placement]
        local attached = false
        for index, category in ipairs(categories) do
            if target_name and string.lower(category.name or "") == target_name then
                local combined = {}
                for key, value in pairs(category) do combined[key] = value end
                combined.groups = {}
                if category.groups then
                    for _, group in ipairs(category.groups) do combined.groups[#combined.groups + 1] = group end
                else
                    combined.groups[1] = category
                end
                for _, upgrade in ipairs(upgrades) do combined.groups[#combined.groups + 1] = upgrade end
                categories[index] = combined
                attached = true
                break
            end
        end
        if not attached then
            for _, upgrade in ipairs(upgrades) do categories[#categories + 1] = upgrade end
        end
    end
    -- Keep the horizontal breathing room, but use a much smaller vertical
    -- margin so scaled menu text has more usable card height.
    local margin_x, margin_y, gap = w*.025, h*.012, w*.012
    local columns = (w/h > 1.25) and math.min(3, #categories) or math.min(2, #categories)
    columns = math.max(1, columns)
    local rows = math.ceil(#categories/columns)
    local cw = (w-margin_x*2-gap*(columns-1))/columns
    local ch = (h-margin_y*2-gap*(rows-1))/rows
    for i, category in ipairs(categories) do
        local category_name = string.lower(category.name or "")
        local is_refreshing_drinks = category_name == "refreshing drinks"
        font_region = is_refreshing_drinks and "refreshing_drinks_title" or "alacarte"
        local col, row = (i-1)%columns, math.floor((i-1)/columns)
        local x, y = margin_x+col*(cw+gap), margin_y+row*(ch+gap)
        white:draw(x, y, x+cw, y+ch)
        local heading = math.min(cw*.085, ch*.10)
        text(x+cw*.05, y+ch*.05, category.name, heading, 0.02, 0.16, 0.34, 1)
        font_region = is_refreshing_drinks and "refreshing_drinks" or "alacarte"
        local hero_path = category.local_image
        if not hero_path then
            for _, item in ipairs(category.items or {}) do
                if item.local_image then hero_path = item.local_image; break end
            end
        end
        local has_hero = hero_path and (category_name == "popcorn" or category_name == "snacks")
        if has_hero then fit_image(hero_path, x+cw*.06, y+ch*.14, x+cw*.94, y+ch*.50) end
        local groups = category.groups or {category}
        local entries = 0
        for group_index, group in ipairs(groups) do
            local same_as_card = group_index == 1 and string.lower(group.name or "") == string.lower(category.name or "")
            local is_upgrade = string.lower(group.name or "") == "combo upgrades" or string.lower(group.name or "") == "combo upgrade"
            local item_rows = #(sorted_available(group.items)) * (is_upgrade and 2 or 1)
            entries = entries + item_rows + (category.groups and not same_as_card and 1 or 0)
        end
        local available_fraction = has_hero and .40 or .76
        local line = math.min(ch*.095, (ch*available_fraction)/math.max(1,entries))
        local cursor = 0
        for group_index, group in ipairs(groups) do
            local same_as_card = group_index == 1 and string.lower(group.name or "") == string.lower(category.name or "")
            local is_upgrade = string.lower(group.name or "") == "combo upgrades" or string.lower(group.name or "") == "combo upgrade"
            if category.groups and not same_as_card then
                local gy = y+(has_hero and ch*.53 or ch*.20)+cursor*line
                text(x+cw*.06, gy, string.upper(group.name or ""), line*.40, 0.07, 0.39, 0.54, 1)
                cursor = cursor + 1
            end
            for _, item in ipairs(sorted_available(group.items)) do
                local iy = y+(has_hero and ch*.53 or ch*.20)+cursor*line
                local price = money(item)
                local item_size = line*.43
                local measured_size = scaled_font_size(item_size)
                local price_width = font:width(price, measured_size)
                local name_width = cw*.82-price_width
                local item_lines = is_upgrade and split_two_lines(item.name, item_size, name_width) or {item.name or ""}
                local widest = 0
                for _, item_line in ipairs(item_lines) do widest = math.max(widest, font:width(item_line, measured_size)) end
                if widest > name_width then item_size = item_size * (name_width/widest) end
                for line_index, item_line in ipairs(item_lines) do
                    text(x+cw*.06, iy+(line_index-1)*line, item_line, item_size)
                end
                local price_y = iy + (#item_lines-1)*line*.5
                text(x+cw*.94-font:width(price,scaled_font_size(item_size)), price_y, price, item_size)
                cursor = cursor + (is_upgrade and 2 or 1)
            end
        end
    end
end

local function render_hotfoods(manifest, w, h)
    font_region = "hotfoods"
    if config.hide_hotfoods_always then
        white:draw(0, 0, w, h)
        centered(0, w, h*.47, "HOT FOODS CURRENTLY UNAVAILABLE", math.min(w,h)*.034, {0.38,0.40,0.44,1})
        return
    end
    local split = w * 0.5
    white:draw(0, 0, split, h)
    black:draw(split, 0, w, h)

    local category = nil
    local hotfoods_categories = manifest.hotfoods_categories or manifest.categories or {}
    for _, candidate in ipairs(hotfoods_categories) do
        local name = string.lower(candidate.name or "")
        if name == "hot food" or name == "hot foods" then
            category = candidate
            break
        end
    end

    local title = category and category.name or "Hot Food"
    centered(0, split, h*.045, string.upper(title), math.min(split,h)*.060, {0.76,0.17,0.11,1})
    local items = category and sorted_available(category.items) or {}
    if category and category.schedule_visible == false then
        centered(0, split, h*.47, "CURRENTLY UNAVAILABLE", math.min(split,h)*.034, {0.38,0.40,0.44,1})
    elseif #items == 0 then
        centered(0, split, h*.47, "NO HOT FOOD ITEMS AVAILABLE", math.min(split,h)*.027, {0.38,0.40,0.44,1})
    else
        local row_h = math.min(h*.075, h*.58/#items)
        local list_h = row_h * #items
        local list_top = math.max(h*.24, h*.56-list_h*.5)
        local item_size = math.min(split*.038, row_h*.43)
        for index, item in ipairs(items) do
            local y = list_top + (index-1)*row_h
            local price = money(item)
            text(split*.052, y+row_h*.20, item.name or "", item_size)
            text(split*.948-font:width(price,scaled_font_size(item_size)), y+row_h*.20, price, item_size)
            divider:draw(split*.038, y+row_h*.88, split*.962, y+row_h*.895)
        end
    end

    font_region = "tax"
    local hotfoods_screen = manifest.hotfoods_screen or manifest.screen or {}
    centered(0, split, h*.955, hotfoods_screen.tax_disclaimer or "", math.min(split,h)*.014, {0.2,0.25,0.3,1})
    font_region = "hotfoods"

    if not render_media(manifest.hotfoods_media, split, 0, w, h, true) then
        centered(split, w, h*.48, "NO MEDIA AVAILABLE", math.min(w-split,h)*.028, {0.42,0.45,0.52,1})
    end
end

local function render_saber_edges(w, h, center, y1)
    y1 = y1 or 0
    local points = {0, w}
    if center then points[#points + 1] = w * 0.5 end
    for _, x in ipairs(points) do
        for _, band in ipairs(saber_bands) do
            band.texture:draw(math.max(0, x-band.width), y1, math.min(w, x+band.width), h)
        end
        saber_core:draw(math.max(0, x-1), y1, math.min(w, x+1), h)
    end
end

local function render_full(manifest, w, h)
    local left = w*.50
    -- Paint the saber first so advertisements and menu cards always cover it.
    render_saber_edges(w, h, true)
    gl.pushMatrix()
    gl.translate(0, 0)
    render_combo(manifest, left, h, true)
    gl.popMatrix()
    gl.pushMatrix()
    gl.translate(left, 0)
    render_categories(manifest, w-left, h)
    gl.popMatrix()
end

local function render_theme_overlay(w, h)
    if not theme_overlay then return end
    local opacity = math.max(0, math.min(100, tonumber(config.theme_overlay_opacity_percent) or 100)) / 100
    if opacity <= 0 then return end
    local status, iw, ih = theme_overlay:state()
    if status ~= "loaded" or not iw or not ih or iw == 0 or ih == 0 then return end
    local fit = config.theme_overlay_fit or "stretch"
    if fit == "stretch" then
        theme_overlay:draw(0, 0, w, h, opacity)
        return
    end
    local scale
    if fit == "cover" then
        scale = math.max(w/iw, h/ih)
    else
        scale = math.min(w/iw, h/ih)
    end
    local draw_w, draw_h = iw*scale, ih*scale
    theme_overlay:draw((w-draw_w)/2, (h-draw_h)/2, (w+draw_w)/2, (h+draw_h)/2, opacity)
end

function node.render()
    gl.clear(1, 1, 1, 1)
    local profile = profiles[config.display_profile] or profiles["3840x1080"]
    local w, h = profile[1], profile[2]
    local rotation = tonumber(config.output_rotation) or 0
    if rotation ~= 90 and rotation ~= 180 and rotation ~= 270 then rotation = 0 end
    local rotated_w = (rotation == 90 or rotation == 270) and h or w
    local rotated_h = (rotation == 90 or rotation == 270) and w or h
    local scale = math.min(NATIVE_WIDTH/rotated_w, NATIVE_HEIGHT/rotated_h)
    gl.pushMatrix()
    gl.translate((NATIVE_WIDTH-rotated_w*scale)/2, (NATIVE_HEIGHT-rotated_h*scale)/2)
    gl.scale(scale, scale)
    if rotation == 90 then
        gl.translate(h, 0)
        gl.rotate(90, 0, 0, 1)
    elseif rotation == 180 then
        gl.translate(w, h)
        gl.rotate(180, 0, 0, 1)
    elseif rotation == 270 then
        gl.translate(0, w)
        gl.rotate(270, 0, 0, 1)
    end
    surface:draw(0, 0, w, h)
    if not state or not state.manifest then
        centered(0, w, h*.45, "Waiting for menu data…", math.min(w,h)*.05)
        if config.debug and state and state.error then
            centered(w*.08, w*.92, h*.54, tostring(state.error), math.min(w,h)*.018, {0.72,0.08,0.08,1})
        end
    else
        local manifest = state.manifest
        local layout = manifest.screen and manifest.screen.layout or config.screen_id
        if config.playback_mode == "alternate" then
            local duration = math.max(5, tonumber(config.page_duration_seconds) or 25)
            layout = math.floor(sys.now()/duration)%2 == 0 and "combo" or "alacarte"
        elseif config.playback_mode == "alternate_combo_hotfoods" and not config.hide_hotfoods_always then
            local duration = math.max(5, tonumber(config.page_duration_seconds) or 25)
            layout = math.floor(sys.now()/duration)%2 == 0 and "combo" or "hotfoods"
        elseif config.playback_mode == "alternate_combo_hotfoods" then
            layout = "combo"
        elseif config.playback_mode == "alternate_alacarte_hotfoods" and not config.hide_hotfoods_always then
            local duration = math.max(5, tonumber(config.page_duration_seconds) or 25)
            layout = math.floor(sys.now()/duration)%2 == 0 and "alacarte" or "hotfoods"
        elseif config.playback_mode == "alternate_alacarte_hotfoods" then
            layout = "alacarte"
        end
        if layout == "combo" then
            render_saber_edges(w,h,false)
            render_combo(manifest,w,h,true)
        elseif layout == "alacarte" then render_saber_edges(w,h,false); render_categories(manifest,w,h)
        elseif layout == "hotfoods" then render_hotfoods(manifest,w,h)
        else render_full(manifest,w,h) end
        font_region = nil
        if config.debug then
            text(w*.01,h*.01,(state.ok and "LIVE" or "STALE").."  "..tostring(manifest.manifest_version or ""),math.min(w,h)*.012,state.ok and 0 or 0.8,state.ok and 0.45 or 0.1,0.1,1)
            if last_ad_error then
                text(w*.01,h*.035,"AD VIDEO: "..last_ad_error,math.min(w,h)*.010,0.75,0.08,0.08,1)
            end
        end
        if state.ok == false then render_offline_indicator(w, h) end
    end
    render_theme_overlay(w, h)
    gl.popMatrix()
end

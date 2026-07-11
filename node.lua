-- Copyright (C) 2015, 2017 Florian Wesch <fw@dividuum.de>
-- All Rights Reserved.
--
-- Unauthorized copying of this file, via any medium is
-- strictly prohibited. Proprietary and confidential.

util.no_globals()

local json = require "json"

local scissors = sys.get_ext "scissors"

local st
local image_files = {}
local loaded_images = {}
local rotation = 0
local bload_threshold = 3600
local bload_fallback = resource.load_image "empty.png"
local screen_idx, screen_cnt
local logo

local function mipmapped_image(filename)
    return resource.load_image(filename, true)
end
util.loaders.jpg = mipmapped_image
util.loaders.png = mipmapped_image

local badge_3d = mipmapped_image("3D.png")
local badge_green = resource.create_colored_texture(0.02, 0.55, 0.18, 1)
local badge_blue = resource.create_colored_texture(2/255, 122/255, 193/255, 1)

local res = util.resource_loader({
    "font.ttf";
    "threed.png";
    "showtime.png";
}, {})

local bgfill = resource.create_colored_texture(.5,.5,.5,1)
local fgfill = resource.create_colored_texture(.1,.1,.1,1)
local infofill = resource.create_colored_texture(1,1,1,1)

local strike_through = resource.create_colored_texture(1,1,1,1)
local strike_through_color = resource.create_shader[[
    uniform sampler2D Texture;
    varying vec2 TexCoord;
    uniform vec4 color;
    void main() {
        gl_FragColor = texture2D(Texture, TexCoord) * color;
    }
]]

local base_time = N.base_time or 0

local function current_offset()
    local time = base_time + sys.now()
    local offset = (time % 86400) / 60
    return offset
end

util.data_mapper{
    ["clock/set"] = function(time)
        print("time set to", time)
        base_time = tonumber(time) - sys.now()
        N.base_time = base_time
        print("CURRENT OFFSET is now", current_offset())
    end;
}

local bload = (function()
    local display_cfg = {
        movies_per_page = 4,
        page_interval = 5,
        hide_poster = true,
        display_badges = true,
        show_logo = false,
    }
    local data_source = "bload"
    local function strip(s)
        return s:match "^%s*(.-)%s*$"
    end

    -- Sometimes the name has another numerical suffix. Throw that away.
    local function strip_name(s)
        return strip(s:sub(1, 29))
    end

    local function hhmm(s)
        local hour, minute = s:match("(..)(..)")
        local hour, minute = tonumber(hour), tonumber(minute)
        local function mil2ampm(hour, minute)
            local suffix = hour < 12 and "am" or ""
            return ("%d:%02d%s"):format((hour-1) % 12 +1, minute, suffix)
        end
        return {
            hour = hour,
            minute = minute,
            offset = hour * 60 + minute,
            string = mil2ampm(hour, minute),
        }
    end
    local function tobool(str)
        return tonumber(str) == 1
    end

    local function convert(names, fixups, ...)
        local cols = {...}
        local out = {}
        for i = 1, #fixups do
            out[names[i]] = fixups[i](cols[i])
        end
        return out
    end

    local sorted_movies = {}
    local movies_on_screen = 1
    local bload, date

    local function parse_bload()
        if not date or not bload then
            print("cannot parse yet. no bload or no date")
            return
        end

        local movies = {}
        for line in bload:gmatch("[^\r\n]+") do
            -- "123456789012345678901234567890123456789012345678901234567890123456789012345"
            -- "1111111122 33 4444 555  6666 7777 8 9999AAAAAAAAAAAAAAAAAAAAAAAAAAAAA     B"
            -- "06/25/151  1  1320 94   10   231  0     Inside Out                        0"

            local single_day = true
            local row

            if single_day then 
                row = convert(
                    {"screen", "show",   "showtime", "runtime", "sold",   "seats",  "threed", "mpaa", "name"},
                    {strip,    tonumber, hhmm,       tonumber,  tonumber, tonumber, tobool,   strip,  strip},
                    line:match("(..) (..) (....) (...)  (....) (....) (.) (....)(.*)")
                )
            else
                row = convert(
                    {"date","screen", "show",   "showtime", "runtime", "sold",   "seats",  "threed", "mpaa", "name"},
                    {strip, strip,    tonumber, hhmm,       tonumber,  tonumber, tonumber, tobool,   strip,  strip_name},
                    line:match("(........)(..) (..) (....) (...)  (....) (....) (.) (....)(.*)")
                )
            end

            if single_day or row.date == date then
                if not movies[row.name] then
                    movies[row.name] = {}
                end

                local movie = movies[row.name]
                movie[#movie+1] = {
                    mpaa = row.mpaa,
                    threed = row.threed,
                    showtime = row.showtime,
                    seats = row.seats,
                    sold = row.sold,
                }
            end
        end

        local pre_sorted_movies = {}
        for name, shows in pairs(movies) do
            table.sort(shows, function(a, b)
                return a.showtime.offset < b.showtime.offset
            end)
            local mpaa = shows[1].mpaa
            local threed = shows[1].threed
            pre_sorted_movies[#pre_sorted_movies+1] = {
                name = name,
                image = name:gsub('[^%w]', ''):lower(),     
                mpaa = mpaa,
                threed = threed,
                shows = shows,
            }
        end
        table.sort(pre_sorted_movies, function(a, b)
            return a.name < b.name
        end)

        movies_on_screen = math.ceil(
            #pre_sorted_movies / screen_cnt
        )
        local split_start = movies_on_screen * (screen_idx - 1) + 1
        local split_end = split_start + movies_on_screen - 1
        print(#pre_sorted_movies, split_start, split_end)

        sorted_movies = {}
        for idx, movie in ipairs(pre_sorted_movies) do
            if idx >= split_start and idx <= split_end then
                sorted_movies[#sorted_movies+1] = movie
            end
        end

        -- pp(sorted_movies)
    end

    local function normalize_show(show)
        local normalized
        if show.showtime then
            normalized = show
        else
            normalized = {
                showtime = {
                    hour = show.hour,
                    minute = show.minute,
                    offset = show.offset,
                    string = show.string,
                },
                seats = show.seats or 100,
                sold = show.sold or 0,
                past = show.past,
            }
        end
        if show.threed ~= nil then normalized.threed = show.threed end
        if show.sensory ~= nil then normalized.sensory = show.sensory end
        if show.open_caption ~= nil then normalized.open_caption = show.open_caption end
        return normalized
    end

    local function set_indy_showings(data)
        sorted_movies = {}
        for _, movie in ipairs(data.movies or {}) do
            local shows = {}
            for _, show in ipairs(movie.shows or {}) do
                shows[#shows+1] = normalize_show(show)
            end
            sorted_movies[#sorted_movies+1] = {
                name = movie.name,
                image = movie.image or movie.name:gsub('[^%w]', ''):lower(),
                mpaa = movie.mpaa or "",
                badges = movie.badges or {},
                shows = shows,
            }
        end
        movies_on_screen = #sorted_movies
        display_cfg.movies_per_page = data.movies_per_page or 4
        display_cfg.page_interval = data.page_interval or 5
        display_cfg.hide_poster = data.hide_poster ~= false
        display_cfg.display_badges = data.display_badges ~= false
        display_cfg.show_logo = data.show_logo == true
        data_source = "indy"
    end

    local function get_paged_movies()
        local per_page = display_cfg.movies_per_page or 4
        if data_source ~= "indy" or #sorted_movies <= per_page then
            return sorted_movies, math.max(#sorted_movies, 1)
        end
        local pages = math.max(1, math.ceil(#sorted_movies / per_page))
        local interval = math.max(1, display_cfg.page_interval or 5)
        local page = math.floor(sys.now() / interval) % pages
        local start_idx = page * per_page + 1
        local out = {}
        for i = start_idx, math.min(start_idx + per_page - 1, #sorted_movies) do
            out[#out+1] = sorted_movies[i]
        end
        return out, per_page
    end

    local function get_display_cfg()
        return display_cfg
    end

    local function get_data_source()
        return data_source
    end

    local function get_sorted_movies()
        return sorted_movies
    end

    local function set_bload(new_bload)
        if new_bload == bload then return end
        bload = new_bload
        return parse_bload()
    end

    local function set_date(new_date)
        if new_date == date then return end
        date = new_date
        return parse_bload()
    end

    local function get_movies_on_screen()
        return movies_on_screen
    end

    return {
        set_bload = set_bload;
        set_date = set_date;
        set_indy_showings = set_indy_showings;
        force_parse = parse_bload;

        get_sorted_movies = get_sorted_movies;
        get_paged_movies = get_paged_movies;
        get_movies_on_screen = get_movies_on_screen;
        get_display_cfg = get_display_cfg;
        get_data_source = get_data_source;
    }
end)()

util.json_watch("config.json", function(config)
    image_files = {}
    loaded_images = {}

    gl.setup(1920, 1080)

    rotation = config.rotation or 0
    local setup_rotation = config.__metadata.device_data.rotation
    if setup_rotation and setup_rotation ~= -1 then
        rotation = setup_rotation
    end

    st = util.screen_transform(rotation)

    for _, image in ipairs(config.images) do
        image_files[image.file.filename:lower():gsub('.jpg', ''):gsub('[^%w]', '')] = resource.open_file(image.file.asset_name)
    end

    bload_threshold = config.bload_threshold
    bload_fallback = resource.load_image(config.bload_fallback.asset_name)

    local split = config.__metadata.device_data.split
    if split then
        screen_idx = split[1]
        screen_cnt = split[2]
    else
        screen_idx = 1
        screen_cnt = 1
    end

    logo = resource.load_image{
        file = config.logo.asset_name,
        mipmap = true,
    }

    bload.force_parse()

    node.gc()
end)

util.file_watch("BLOAD.txt", bload.set_bload)

util.json_watch("showings.json", function(data)
    bload.set_indy_showings(data)
end)

util.data_mapper{
    ["date/set"] = function(date)
        print("date set to", date)
        bload.set_date(date)
    end;
    ["source/set"] = function(src)
        if src == "indy" then
            bload_age = 0
        end
    end;
}

local function layouter(rotation, num_shows)
    if rotation == 90 or rotation == 270 then
        if num_shows <= 3 then
            return 1, 3
        elseif num_shows <= 8 then
            return 2, 4
        elseif num_shows <= 10 then
            return 2, 5
        elseif num_shows <= 15 then
            return 3, 5
        else
            return 3, 6
        end
    else
        if num_shows <= 4 then
            return 2, 2
        elseif num_shows <= 6 then
            return 3, 2
        elseif num_shows <= 9 then
            return 3, 3
        elseif num_shows <= 12 then
            return 4, 3
        elseif num_shows <= 16 then
            return 4, 4
        else
            return 5, 4
        end
    end
end

local function show_bload()
    local cfg = bload.get_display_cfg()
    local movies, page_size = bload.get_paged_movies()

    local cols, rows = layouter(rotation, math.max(page_size, #movies))

    local cell_w = WIDTH / cols
    local cell_h = HEIGHT / rows
    local now = current_offset()

    for idx = 1, #movies+1 do
        local x = (idx - 1)%cols * (cell_w)
        local y = math.floor((idx - 1)/cols) * cell_h
        local movie = movies[idx]
        if movie then
            bgfill:draw(x, y, x+cell_w, y+cell_h)
            local split = math.min(cell_h-150, cell_h/1.5)

            local image
            local file = image_files[movie.image]
            if not cfg.hide_poster and file then
                image = loaded_images[movie.image]
                if not image then
                    print("loading image", movie.image)
                    loaded_images[movie.image] = resource.load_image{
                        file = file:copy(),
                    }
                end
            end

            if image then
                image:draw(x+1, y+1, x+cell_w-1, y+split)
            else
                local width = 99999
                local size = 60
                while width > cell_w -5 do
                    size = size - 5
                    width = res.font:width(movie.name, size)
                end
                local name_x = x + (cell_w-width) / 2
                res.font:write(name_x, y+(split-size)/2, movie.name, size, 0,0,0,1)
            end

            -- info line (rating + optional movie badges)
            local info_h = 50
            if cfg.display_badges and movie.badges and #movie.badges > 0 then
                info_h = 72
            end
            infofill:draw(x+1, y+split, x+cell_w-1, y+split+info_h)
            local width = res.font:width(movie.mpaa, 30)
            local info_x = x + (cell_w-width) / 2
            res.font:write(info_x, y+split+10, movie.mpaa, 30, 0,0,0,1)
            if cfg.display_badges and movie.badges and #movie.badges > 0 then
                local badge_text = table.concat(movie.badges, "  ")
                local badge_size = 16
                while badge_size > 10 and res.font:width(badge_text, badge_size) > cell_w - 10 do
                    badge_size = badge_size - 1
                end
                local badge_w = res.font:width(badge_text, badge_size)
                res.font:write(x + (cell_w-badge_w)/2, y+split+38, badge_text, badge_size, 0,0,0,1)
            end

            -- showtime grid
            local times_y = y + split + info_h + 1
            local times_h = cell_h - split - info_h - 2
            local time_cols, time_rows
            if #movie.shows <= 1 then
                time_cols = 1
                time_rows = 1
            elseif #movie.shows <= 2 then
                time_cols = 2
                time_rows = 1
            elseif #movie.shows <= 4 then
                time_cols = 2
                time_rows = 2
            elseif #movie.shows <= 6 then
                time_cols = 3
                time_rows = 2
            elseif #movie.shows <= 9 then
                time_cols = 3
                time_rows = 3
            elseif #movie.shows <= 15 then
                time_cols = 5
                time_rows = 3
            elseif #movie.shows <= 18 then
                time_cols = 6
                time_rows = 3
            elseif #movie.shows <= 20 then
                time_cols = 5
                time_rows = 4
            elseif #movie.shows <= 24 then
                time_cols = 6
                time_rows = 4
            else -- 30 MAX
                time_cols = 6
                time_rows = 5
            end

            local show_w = cell_w / time_cols
            local show_h = times_h / time_rows
            for si = 1, #movie.shows do
                local show = movie.shows[si]
                local col = (si - 1) % time_cols
                local row = math.floor((si - 1) / time_cols)
                local show_x = math.floor(x + 1 + col * show_w)
                local show_y = math.floor(times_y + row * show_h)
                local show_x2 = math.floor(x + 1 + (col + 1) * show_w)
                local show_y2 = math.floor(times_y + (row + 1) * show_h)
                local slot_w = show_x2 - show_x
                local slot_h = show_y2 - show_y

                fgfill:draw(show_x, show_y, show_x2, show_y2)

                local showtime = show.showtime
                local gap = 4
                local extra_reserve = 0
                local tag_font = math.max(12, math.floor(slot_h * 0.30))

                if cfg.display_badges then
                    if show.threed == true then
                        local icon_h = math.floor(slot_h * 0.42)
                        extra_reserve = extra_reserve + math.floor(icon_h * 920 / 716) + gap
                    end
                    if show.sensory == true then
                        extra_reserve = extra_reserve + res.font:width('SENS', tag_font) + 4 + gap
                    end
                    if show.open_caption == true then
                        extra_reserve = extra_reserve + res.font:width('OC', tag_font) + 4 + gap
                    end
                end

                local slot_font = math.floor(math.min(
                    (slot_w - extra_reserve) / (#showtime.string * 0.62),
                    slot_h * 0.62
                ))
                local width = res.font:width(showtime.string, slot_font)
                local started = now > showtime.offset + 15 or show.past
                local total_w = width + extra_reserve
                local start_x = math.floor(show_x + (slot_w - total_w) / 2)
                local show_y_text = math.floor(show_y + (slot_h - slot_font) / 2 + slot_font * 0.05)
                local cursor_x = start_x + width + gap

                local color = {1,1,1,1}

                if show.seats == 0 then
                    color[1], color[2], color[3] = 1, .2, .2
                elseif show.seats <= 20 then
                    color[1], color[2], color[3] = 1, .8, .2
                end

                if started then
                    color = {.5,.5,.5,1}
                end

                res.font:write(start_x, show_y_text, showtime.string, slot_font, unpack(color))

                if cfg.display_badges then
                    if show.threed == true then
                        local icon_h = math.floor(slot_h * 0.42)
                        local icon_w = math.floor(icon_h * 920 / 716)
                        local icon_y = math.floor(show_y + (slot_h - icon_h) / 2)
                        badge_3d:draw(cursor_x, icon_y, cursor_x + icon_w, icon_y + icon_h)
                        cursor_x = cursor_x + icon_w + gap
                    end

                    local function draw_tag(text, fill)
                        local tw = res.font:width(text, tag_font)
                        local tag_w = tw + 4
                        local tag_h = tag_font + 4
                        local tag_y = math.floor(show_y + (slot_h - tag_h) / 2)
                        fill:draw(cursor_x, tag_y, cursor_x + tag_w, tag_y + tag_h)
                        res.font:write(cursor_x + 2, tag_y + 2, text, tag_font, 1, 1, 1, 1)
                        cursor_x = cursor_x + tag_w + gap
                    end

                    if show.sensory == true then
                        draw_tag('SENS', badge_green)
                    end
                    if show.open_caption == true then
                        draw_tag('OC', badge_blue)
                    end
                end

                if started then
                    strike_through_color:use{color = color}
                    strike_through:draw(start_x-10, show_y_text+slot_font/2-slot_font*0.05, start_x+width+10, show_y_text+slot_font/2-slot_font*0.05+2, 1)
                    strike_through_color:deactivate()
                end
            end
        else
            if cfg.show_logo then
                util.draw_correct(logo, x, y, x+cell_w, y+cell_h-1)
            else
                bgfill:draw(x, y, x+cell_w, y+cell_h-1)
            end
        end
    end
end

local bload_age = 0

util.data_mapper{
    ["age/set"] = function(age)
        bload_age = tonumber(age)
    end;
}

local function show_fallback()
    util.draw_correct(bload_fallback, 0, 0, WIDTH, HEIGHT)
end

function node.render()
    gl.clear(0,0,0,1)
    st()

    local movies = bload.get_paged_movies()
    local stale = bload.get_data_source() ~= "indy" and bload_age > bload_threshold

    if #movies == 0 or stale then
        show_fallback()
    else
        show_bload()
    end
end

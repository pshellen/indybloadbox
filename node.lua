-- Copyright (C) 2016-2019 Florian Wesch <fw@info-beamer.com>

gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)

util.no_globals()

local json = require "json"
local matrix = require "matrix2d"

local font = resource.load_font "font.ttf"
local black = resource.create_colored_texture(0, 0, 0, 1)
local badge_blue = resource.create_colored_texture(2/255, 122/255, 193/255, 1)
local badge_green = resource.create_colored_texture(0.02, 0.55, 0.18, 1)
local badge_3d = resource.load_image "3D.png"
local white = resource.create_colored_texture(1, 1, 1, 1)

local indy_id
local screen = {name = ""}
local local_time = ""

local border, blur
local clock_offset -- unix time minus sys.now(), sent by the service
local st, vid_scaler
local portrait, rotation, logo, logo_name
local debug = true
local outdated = false
local layout = {}

local my_serial = sys.get_env "SERIAL"
local scale = 1

local REF_W, REF_H = 1920, 1080

local function scale_x(x)
    return x * WIDTH / REF_W
end

local function scale_y(y)
    return y * HEIGHT / REF_H
end

local function scale_s(s)
    return s * math.min(WIDTH / REF_W, HEIGHT / REF_H)
end

local function compute_layout()
    layout.poster_pad = scale_x(4)
    layout.badge_w = scale_x(572)
    -- Size off the shorter side so portrait stays readable
    local short = math.min(WIDTH, HEIGHT)
    layout.badge_3d_size = short * 0.09
    layout.badge_size = scale_s(76.8)
    if portrait then
        layout.poster_x1 = layout.poster_pad
        layout.poster_x2 = WIDTH - layout.poster_pad
        layout.info_center_x = WIDTH / 2
        layout.badge_center_x = layout.info_center_x
        layout.info_w = WIDTH - scale_x(40)
        -- A 270-degree screen transform reverses logical Y across the
        -- physical display. These values intentionally run bottom-to-top so
        -- the physical order is logo, status, poster, title, showtime.
        layout.logo_y = HEIGHT * 0.88
        layout.logo_h = HEIGHT * 0.10
        layout.logo_w = WIDTH * 0.58
        layout.badge_y = HEIGHT * 0.825
        layout.badge_h = HEIGHT * 0.05
        layout.poster_y = HEIGHT * 0.14
        layout.poster_y2 = HEIGHT * 0.86
        layout.movie_y = HEIGHT * 0.075
        layout.screen_y = HEIGHT * 0.03
        layout.title_size = short * 0.08
        layout.showtime_size = short * 0.048
        layout.show_screen_name = false
        layout.show_extras = false
    else
        -- Horizontal screens use the width: poster on the left, branding and
        -- show information stacked in a dedicated panel on the right.
        layout.poster_x1 = WIDTH * 0.025
        layout.poster_x2 = WIDTH * 0.63
        layout.poster_y = HEIGHT * 0.04
        layout.poster_y2 = HEIGHT * 0.96
        layout.info_center_x = WIDTH * 0.68
        layout.badge_center_x = layout.info_center_x
        layout.info_w = WIDTH * 0.56
        layout.logo_y = HEIGHT * 0.06
        layout.logo_h = HEIGHT * 0.19
        layout.logo_w = WIDTH * 0.40
        layout.divider_y = HEIGHT * 0.285
        layout.divider_w = WIDTH * 0.26
        layout.badge_y = HEIGHT * 0.33
        layout.badge_h = HEIGHT * 0.068
        layout.badge_size = short * 0.05
        layout.movie_y = HEIGHT * 0.445
        layout.meta_y = HEIGHT * 0.565
        layout.meta_size = short * 0.04
        layout.screen_y = HEIGHT * 0.645
        layout.countdown_y = HEIGHT * 0.755
        layout.countdown_size = short * 0.045
        layout.progress_w = WIDTH * 0.30
        layout.progress_h = scale_s(10)
        layout.screen_name_y = HEIGHT * 0.85
        layout.title_size = scale_s(88)
        layout.showtime_size = short * 0.075
        layout.screen_name_size = short * 0.05
        layout.clock_y = HEIGHT * 0.035
        layout.clock_size = short * 0.04
        layout.show_screen_name = true
        layout.show_extras = true
    end
    layout.poster_h = layout.poster_y2 - layout.poster_y
    layout.bottom_size = short * 0.048
end

local function fit_text(text, max_size, max_width, min_size)
    min_size = min_size or 16
    local size = max_size
    while size > min_size do
        if font:width(text, size) <= max_width then
            return size
        end
        size = size - 2
    end
    return min_size
end

local function draw_centered_text(text, y, size, max_width, center_x)
    size = fit_text(text, size, max_width, 16)
    local w = font:width(text, size)
    center_x = center_x or WIDTH / 2
    font:write(center_x - w / 2, y, text, size, 1, 1, 1, 1)
end

local function draw_badge(text, upcoming)
    if not text or text == "" then
        return
    end

    local size = fit_text(text, layout.badge_size, layout.badge_w - scale_x(40), 20)
    local text_w = font:width(text, size)
    local pad_x = scale_x(28)
    local pad_y = scale_y(5)
    local box_w = math.min(layout.badge_w, text_w + pad_x * 2)
    local box_h = math.max(layout.badge_h, size + pad_y * 2)
    local x1 = layout.badge_center_x - box_w / 2
    local y1 = layout.badge_y
    local fill = upcoming and badge_green or badge_blue

    fill:draw(x1, y1, x1 + box_w, y1 + box_h)
    font:write(
        x1 + (box_w - text_w) / 2,
        y1 + (box_h - size) / 2,
        text,
        size,
        1, 1, 1, 1
    )
end

local function draw_title_row(show)
    local title = show.name or ""
    local size = layout.title_size
    local max_w = layout.info_w
    local gap = scale_x(20)
    local badge_w, badge_h = 0, 0

    if show.is_3d and badge_3d then
        local bw, bh = badge_3d:size()
        badge_h = layout.badge_3d_size
        badge_w = badge_h * (bw / math.max(bh, 1))
        if badge_w > WIDTH * 0.22 then
            badge_w = WIDTH * 0.22
            badge_h = badge_w * (bh / math.max(bw, 1))
        end
        max_w = max_w - badge_w - gap
    end

    size = fit_text(title, size, max_w, 16)
    local text_w = font:width(title, size)
    local total_w = text_w
    if badge_w > 0 then
        total_w = total_w + gap + badge_w
    end

    local x = layout.info_center_x - total_w / 2
    local y = layout.movie_y

    if badge_w > 0 then
        local bw, bh = badge_3d:size()
        local iy = y + (size - badge_h) / 2
        local ix1, iy1, ix2, iy2 = util.scale_into(badge_w, badge_h, bw, bh)
        badge_3d:draw(x + ix1, iy + iy1, x + ix2, iy + iy2)
        x = x + badge_w + gap
    end

    font:write(x, y, title, size, 1, 1, 1, 1)
end

local function draw_header_logo()
    if logo then
        local lw, lh = logo:size()
        local ix1, iy1, ix2, iy2 = util.scale_into(layout.logo_w, layout.logo_h, lw, lh)
        local lx1 = layout.info_center_x - layout.logo_w / 2
        logo:draw(lx1 + ix1, layout.logo_y + iy1, lx1 + ix2, layout.logo_y + iy2)
    end
end

local function now_unix()
    if clock_offset then
        return sys.now() + clock_offset
    end
end

local function status_rgb()
    if screen.show and screen.show.upcoming then
        return 0.02, 0.55, 0.18
    end
    return 2/255, 122/255, 193/255
end

local function status_fill()
    if screen.show and screen.show.upcoming then
        return badge_green
    end
    return badge_blue
end

local function draw_divider()
    local x1 = layout.info_center_x - layout.divider_w / 2
    local h = scale_s(4)
    status_fill():draw(
        x1, layout.divider_y, x1 + layout.divider_w, layout.divider_y + h
    )
end

local function draw_meta_row(show)
    -- "[PG-13]  ·  1H 38M" centered under the title
    local size = layout.meta_size
    local rating = show.rating or ""
    local runtime = show.runtime_label or ""
    if rating == "" and runtime == "" then
        return
    end

    local pad_x, pad_y = scale_x(14), scale_y(6)
    local line = math.max(2, scale_s(3))
    local sep = "  \194\183  "
    local rating_w = rating ~= "" and (font:width(rating, size) + pad_x * 2) or 0
    local sep_w = (rating ~= "" and runtime ~= "") and font:width(sep, size) or 0
    local runtime_w = runtime ~= "" and font:width(runtime, size) or 0
    local total = rating_w + sep_w + runtime_w
    local x = layout.info_center_x - total / 2
    local y = layout.meta_y

    if rating ~= "" then
        local y1, y2 = y - pad_y, y + size + pad_y
        white:draw(x, y1, x + rating_w, y1 + line)
        white:draw(x, y2 - line, x + rating_w, y2)
        white:draw(x, y1, x + line, y2)
        white:draw(x + rating_w - line, y1, x + rating_w, y2)
        font:write(x + pad_x, y, rating, size, 1, 1, 1, 1)
        x = x + rating_w
    end
    if sep_w > 0 then
        font:write(x, y, sep, size, 1, 1, 1, 0.6)
        x = x + sep_w
    end
    if runtime ~= "" then
        font:write(x, y, runtime, size, 1, 1, 1, 0.9)
    end
end

local function draw_countdown(show)
    local now = now_unix()
    if not now or not show.unix then
        return
    end
    local r, g, b = status_rgb()
    -- brighten slightly so the countdown reads well on the dark backdrop
    r, g, b = math.min(1, r + 0.2), math.min(1, g + 0.25), math.min(1, b + 0.2)
    if show.upcoming then
        local secs = show.unix - now
        local text
        if secs <= 60 then
            text = "STARTING NOW"
        else
            text = ("STARTS IN %d MIN"):format(math.ceil(secs / 60))
        end
        local size = fit_text(text, layout.countdown_size, layout.info_w, 16)
        local w = font:width(text, size)
        font:write(layout.info_center_x - w / 2, layout.countdown_y, text, size, r, g, b, 1)
    elseif (show.runtime or 0) > 0 then
        -- Progress through the feature runtime (does not include trailers)
        local frac = (now - show.unix) / (show.runtime * 60)
        frac = math.max(0, math.min(1, frac))
        local x1 = layout.info_center_x - layout.progress_w / 2
        local y1 = layout.countdown_y + layout.countdown_size / 2 - layout.progress_h / 2
        local y2 = y1 + layout.progress_h
        white:draw(x1, y1, x1 + layout.progress_w, y2, 0.2)
        status_fill():draw(
            x1, y1, x1 + layout.progress_w * frac, y2
        )
    end
end

local function draw_clock()
    if not local_time or local_time == "" then
        return
    end
    local size = layout.clock_size
    local w = font:width(local_time, size)
    font:write(WIDTH * 0.975 - w, layout.clock_y, local_time, size, 1, 1, 1, 0.8)
end

local function draw_backdrop(tex)
    -- Blurred, darkened copy of the poster covering the whole screen.
    -- The blur comes from sampling low mipmap levels, so the texture
    -- must be loaded with mipmap = true.
    if not tex or not blur then
        return
    end
    local w, h = tex:size()
    local s = math.max(WIDTH / w, HEIGHT / h) * 1.1
    local dw, dh = w * s, h * s
    local x1, y1 = (WIDTH - dw) / 2, (HEIGHT - dh) / 2
    blur:use{
        dim = 0.42,
        spread = {0.035, 0.035 * w / h},
    }
    tex:draw(x1, y1, x1 + dw, y1 + dh)
    blur:deactivate()
end

local function draw_show_info()
    if not screen.show then
        return
    end
    draw_header_logo()
    if layout.show_extras then
        draw_divider()
        draw_clock()
    end
    draw_badge(screen.show.status_label, screen.show.upcoming)
    draw_title_row(screen.show)
    if layout.show_extras then
        draw_meta_row(screen.show)
    end
    local show_time = "SHOW TIME: " .. ((screen.show.start or ""):upper())
    draw_centered_text(show_time, layout.screen_y, layout.showtime_size, layout.info_w, layout.info_center_x)
    if layout.show_extras then
        draw_countdown(screen.show)
    end
    if layout.show_screen_name then
        draw_centered_text(
            (screen.name or ""):upper(),
            layout.screen_name_y,
            layout.screen_name_size,
            layout.info_w,
            layout.info_center_x
        )
    end
end

util.file_watch("border.glsl", function(raw)
    border = resource.create_shader(raw)
end)

util.file_watch("blur.glsl", function(raw)
    blur = resource.create_shader(raw)
end)

util.file_watch("config.json", function(raw)
    local config = json.decode(raw)
    pp(config)

    debug = false

    indy_id = nil
    rotation = 0
    local primary_logo_name = config.corner_logo and config.corner_logo.asset_name
    local legacy_logo_name = config.main_logo and config.main_logo.asset_name
    if primary_logo_name and primary_logo_name ~= "box.png" then
        logo_name = primary_logo_name
    elseif legacy_logo_name and legacy_logo_name ~= "box.png" then
        logo_name = legacy_logo_name
    else
        logo_name = primary_logo_name or legacy_logo_name or "box.png"
    end
    logo = resource.load_image(logo_name)
    print("configured logo is " .. tostring(logo_name))

    for idx = 1, #config.signs do
        local sign = config.signs[idx]
        if sign.serial == my_serial then
            indy_id = sign.indy_id
            rotation = sign.rotation
            debug = sign.debug
        end
    end
    print("my screen indy id is " .. tostring(indy_id))

    gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)
    st = util.screen_transform(rotation)
    print("screen size is " .. WIDTH .. "x" .. HEIGHT)

    vid_scaler = matrix.trans(NATIVE_WIDTH/2, NATIVE_HEIGHT/2) *
                 matrix.scale(scale, scale) *
                 matrix.trans(-NATIVE_WIDTH/2, -NATIVE_HEIGHT/2)

    portrait = rotation == 90 or rotation == 270
    compute_layout()
end)

util.json_watch("screen.json", function(new_screen)
    screen = new_screen
end)

util.data_mapper{
    ["time/set"] = function(new_local_time)
        local_time = new_local_time
    end;
    ["time/unix"] = function(unix)
        unix = tonumber(unix)
        if unix then
            clock_offset = unix - sys.now()
        end
    end;
}

local function get_assets()
    if not screen.show then
        return {{
            media = {
                asset_name = logo_name,
                type = "fallback",
            },
            duration = 5
        }}
    end

    return {{
        media = {
            asset_name = screen.show.poster_file,
            fallback_asset_name = screen.show.fallback_poster_file,
            type = screen.show.media_type or "image",
        },
        duration = 86400
    }}
end

local function fitted_poster_rect(media_w, media_h)
    local area_x1, area_y1 = layout.poster_x1, layout.poster_y
    local area_w = layout.poster_x2 - layout.poster_x1
    local area_h = layout.poster_y2 - layout.poster_y
    local ix1, iy1, ix2, iy2 = util.scale_into(area_w, area_h, media_w, media_h)
    -- Portrait posters on a horizontal screen should hug the left padding
    -- instead of floating in the center of an oversized poster region.
    if not portrait then
        local fitted_w = ix2 - ix1
        ix1 = 0
        ix2 = fitted_w
    end
    return area_x1 + ix1, area_y1 + iy1, area_x1 + ix2, area_y1 + iy2
end

local function draw_hugged_poster(media_w, media_h, draw_media)
    local x1, y1, x2, y2 = fitted_poster_rect(media_w, media_h)
    local border_color = {0.45, 0.78, 1.0, 1.0}
    if screen.show and screen.show.color then
        border_color = screen.show.color
    end
    border:use{
        size = {media_w, media_h},
        radius = scale_s(22),
        border = scale_x(8),
        borderColor = border_color,
        time = 0,
    }
    draw_media(x1, y1, x2, y2)
    border:deactivate()
end

local function Fallback(asset_name, duration)
    local obj = resource.load_image(asset_name)
    local started

    local function start()
        started = sys.now()
    end
    local function draw()
        local w, h = obj:size()
        local max_w = WIDTH * 0.80
        local max_h = HEIGHT * 0.38
        local box_x = (WIDTH - max_w) / 2
        local box_y = HEIGHT * 0.16
        black:draw(0, 0, WIDTH, HEIGHT)
        local x1, y1, x2, y2 = util.scale_into(max_w, max_h, w, h)
        obj:draw(box_x + x1, box_y + y1, box_x + x2, box_y + y2)
        draw_centered_text(
            (screen.name or ""):upper(),
            HEIGHT * 0.68,
            math.min(WIDTH, HEIGHT) * 0.09,
            WIDTH * 0.90
        )
        return sys.now() - started > duration
    end
    local function unload()
        obj:dispose()
    end
    return {
        start = start;
        draw = draw;
        unload = unload;
    }
end

local function Image(asset_name, duration)
    print("started new image " .. asset_name)
    local obj = resource.load_image{file = asset_name, mipmap = true}
    local started

    local function start()
        started = sys.now()
    end
    local function draw()
        black:draw(0, 0, WIDTH, HEIGHT)
        draw_backdrop(obj)

        local w, h = obj:size()
        draw_hugged_poster(w, h, function(x1, y1, x2, y2)
            obj:draw(x1, y1, x2, y2)
        end)

        if screen.show then
            draw_show_info()
        end

        return sys.now() - started > duration
    end
    local function unload()
        obj:dispose()
    end
    return {
        start = start;
        draw = draw;
        unload = unload;
    }
end

local function Video(asset_name, duration, fallback_asset_name)
    print("started new video " .. asset_name)
    local file = resource.open_file(asset_name)
    local fallback_obj
    if fallback_asset_name and fallback_asset_name ~= "" then
        fallback_obj = resource.load_image{file = fallback_asset_name, mipmap = true}
    end
    local obj
    local video_failed = false

    local function start()
    end
    local function draw()
        black:draw(0, 0, WIDTH, HEIGHT)
        draw_backdrop(fallback_obj)

        if fallback_obj then
            local fw, fh = fallback_obj:size()
            draw_hugged_poster(fw, fh, function(x1, y1, x2, y2)
                fallback_obj:draw(x1, y1, x2, y2)
            end)
        end

        if not obj and not video_failed then
            local ok, loaded = pcall(resource.load_video, {
                file = file;
                raw = true;
            })
            if ok then
                obj = loaded
            else
                print("video load failed: " .. tostring(loaded))
                video_failed = true
            end
        end

        if obj then
            local ok, state, vw, vh = pcall(function()
                return obj:state()
            end)
            if not ok then
                print("video decode failed: " .. tostring(state))
                obj:dispose()
                obj = nil
                video_failed = true
            elseif state == "finished" then
                obj:dispose()
                obj = nil
            elseif state == "loaded" then
                draw_hugged_poster(vw, vh, function(x1, y1, x2, y2)
                    obj:place(x1, y1, x2, y2)
                end)
            end
        end

        if screen.show then
            draw_show_info()
        end

        return false
    end

    local function unload()
        if obj then
            obj:dispose()
        end
        if fallback_obj then
            fallback_obj:dispose()
        end
    end
    return {
        start = start;
        draw = draw;
        unload = unload;
    }
end

local function Player()
    local offset = 0
    local current = Fallback(logo_name, 5)
    local next
    local current_key = ""

    local function asset_key()
        if not screen.show or screen.show.poster_file == "" then
            return "fallback:" .. logo_name
        end
        return (screen.show.media_type or "image") .. ":" .. screen.show.poster_file
    end

    current.start()
    current_key = asset_key()

    local function draw()
        local key = asset_key()
        if key ~= current_key then
            current.unload()
            current_key = key
            next = nil
            offset = 0
            current = Fallback(logo_name, 5)
            current.start()
        end

        if not next then
            local assets = get_assets()
            offset = offset + 1
            if offset > #assets then
                offset = 1
            end

            local asset = assets[offset]
            next = ({
                image = Image;
                video = Video;
                fallback = Fallback;
            })[asset.media.type](
                asset.media.asset_name,
                asset.duration,
                asset.media.fallback_asset_name
            )
        end

        local ended = current.draw()

        if ended then
            current.unload()
            current = next
            next = nil
            current.start()
        end
    end

    return {
        draw = draw;
    }
end

local player = Player()

function node.render()
    gl.clear(0, 0, 0, 1)
    st()

    gl.translate(WIDTH/2, HEIGHT/2)
    gl.scale(scale, scale)
    gl.translate(-WIDTH/2, -HEIGHT/2)

    player.draw()

    if not indy_id then
        font:write(WIDTH/2-120, HEIGHT/2+140, "NO SCREEN CONFIGURED", 24, 1,1,1,.1)
        font:write(WIDTH/2-60, HEIGHT/2+165, my_serial, 20, 1,1,1,.1)
        return
    elseif outdated then
        font:write(WIDTH/2-110, HEIGHT/2+140, "NO RECENT SCHEDULE", 24, 1,1,1,.1)
        font:write(WIDTH/2-60, HEIGHT/2+165, my_serial, 20, 1,1,1,.1)
        return
    end

    if debug then
        local x, y = WIDTH-250, 10
        font:write(x, y, "Serial: " .. my_serial, 12, 1,1,1,1); y=y+12
        font:write(x, y, ("Time: %s"):format(local_time), 12, 1,1,1,1); y=y+12
        if screen.show then
            font:write(x, y, "Show: "..screen.show.name, 12, 1,1,1,1); y=y+12
            font:write(x, y, "Status: "..(screen.show.status_label or ""), 12, 1,1,1,1); y=y+12
            font:write(x, y, "Media: "..(screen.show.media_type or ""), 12, 1,1,1,1); y=y+12
        end
    end
end

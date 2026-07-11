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
local top_logo = resource.load_image "logo.png"

local indy_id
local screen = {name = ""}
local local_time = ""

local border
local st, vid_scaler
local portrait, rotation, main_logo, main_logo_name
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
    local short = math.min(WIDTH, HEIGHT)
    layout.bottom_pad = scale_y(8)
    layout.bottom_size = short * 0.048
    layout.footer_h = math.max(short * 0.11, layout.bottom_size * 2.8)
    layout.corner_size = layout.footer_h - layout.bottom_pad * 2

    if portrait then
        layout.title_size = short * 0.08
    else
        layout.title_size = scale_s(64)
    end

    layout.badge_3d_size = short * 0.09
    layout.badge_size = scale_s(76.8)
    layout.badge_w = scale_x(572)

    local info_gap = scale_y(12)
    -- Rotated portrait signs clip the logical bottom edge on the physical display.
    local safe_inset = portrait and math.max(scale_y(100), HEIGHT * 0.10) or scale_y(32)

    layout.footer_y = HEIGHT - safe_inset - layout.footer_h
    layout.bottom_y = layout.footer_y + (layout.footer_h - layout.bottom_size) / 2

    -- The screen name now sits inside the footer at the bottom right,
    -- so the showtime can use the space directly above the footer.
    layout.showtime_y = layout.footer_y - info_gap - layout.bottom_size
    layout.movie_y = layout.showtime_y - info_gap - layout.title_size

    -- Reserve space for logo.png above the poster.
    -- These values use the short side of the display so they remain
    -- consistent on both portrait and landscape screens.
    layout.top_logo_y = short * 0.025
    layout.top_logo_h = short * 0.10
    layout.top_logo_w = WIDTH * 0.55
    layout.top_logo_gap = short * 0.06

    layout.poster_pad = scale_x(4)
    layout.poster_x1 = layout.poster_pad
    layout.poster_x2 = WIDTH - layout.poster_pad
    layout.poster_y = layout.top_logo_y + layout.top_logo_h + layout.top_logo_gap
    layout.poster_h = math.max(scale_y(280), layout.movie_y - layout.poster_y - scale_y(16))
    layout.poster_y2 = layout.poster_y + layout.poster_h
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

local function draw_centered_text(text, y, size, max_width)
    size = fit_text(text, size, max_width, 16)
    local w = font:width(text, size)
    font:write((WIDTH - w) / 2, y, text, size, 1, 1, 1, 1)
end

local function draw_top_logo()
    if not top_logo then
        return
    end

    local lw, lh = top_logo:size()
    local max_w = layout.top_logo_w
    local max_h = layout.top_logo_h
    local box_x = (WIDTH - max_w) / 2
    local box_y = layout.top_logo_y
    local x1, y1, x2, y2 = util.scale_into(max_w, max_h, lw, lh)

    top_logo:draw(
        box_x + x1,
        box_y + y1,
        box_x + x2,
        box_y + y2
    )
end

local function draw_badge(text, upcoming)
    if not text or text == "" then
        return
    end

    local size = fit_text(text, layout.badge_size, layout.badge_w - scale_x(40), 20)
    local text_w = font:width(text, size)
    local pad_x = scale_x(28)
    local pad_y = scale_y(18)
    local box_w = math.min(layout.badge_w, text_w + pad_x * 2)
    local box_h = size + pad_y * 2
    local x1 = (WIDTH - box_w) / 2
    -- Overlap the top edge of the poster, matching the reference layout
    local y1 = layout.poster_y - box_h * 0.4
    local fill = upcoming and badge_green or badge_blue

    fill:draw(x1, y1, x1 + box_w, y1 + box_h)
    font:write(x1 + (box_w - text_w) / 2, y1 + pad_y, text, size, 1, 1, 1, 1)
end

local function draw_title_row(show)
    local title = show.name or ""
    local size = layout.title_size
    local max_w = WIDTH - scale_x(40)
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

    local x = (WIDTH - total_w) / 2
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

local function draw_bottom_bar()
    local screen_label = (screen.name or ""):upper()

    if screen_label == "" then
        return
    end

    local right_pad = scale_x(40)
    local max_width = WIDTH * 0.40
    local size = fit_text(
        screen_label,
        layout.bottom_size,
        max_width,
        16
    )
    local text_w = font:width(screen_label, size)

    -- Screen name in the bottom-right corner.
    font:write(
        WIDTH - text_w - right_pad,
        layout.bottom_y,
        screen_label,
        size,
        1, 1, 1, 1
    )
end

local function draw_show_info()
    if not screen.show then
        return
    end

    local show_time = (screen.show.start or ""):upper()

    draw_badge(screen.show.status_label, screen.show.upcoming)
    draw_title_row(screen.show)

    if show_time ~= "" then
        draw_centered_text(
            "Show Start: " .. show_time,
            layout.showtime_y,
            layout.bottom_size,
            WIDTH - scale_x(40)
        )
    end

    draw_bottom_bar()
end

util.file_watch("border.glsl", function(raw)
    border = resource.create_shader(raw)
end)

local function resolve_sign(signs, serial)
    for idx = 1, #signs do
        if signs[idx].serial == serial then
            return signs[idx]
        end
    end
    if #signs == 1 then
        print("WARNING: device serial " .. serial .. " not in config; using the only configured sign")
        return signs[1]
    end
    return nil
end

util.file_watch("config.json", function(raw)
    local config = json.decode(raw)
    pp(config)

    debug = false

    indy_id = nil
    rotation = 0
    main_logo_name = config.main_logo.asset_name
    main_logo = resource.load_image(config.main_logo.asset_name)

    local sign = resolve_sign(config.signs, my_serial)
    if sign then
        indy_id = sign.indy_id
        rotation = sign.rotation
        debug = sign.debug
    else
        print("WARNING: no sign configured for device serial " .. my_serial)
    end
    print("my screen indy id is " .. tostring(indy_id) .. ", rotation is " .. tostring(rotation))

    gl.setup(NATIVE_WIDTH, NATIVE_HEIGHT)
    st = util.screen_transform(rotation)
    print("screen size is " .. WIDTH .. "x" .. HEIGHT)

    vid_scaler = matrix.trans(NATIVE_WIDTH/2, NATIVE_HEIGHT/2) *
                 matrix.scale(scale, scale) *
                 matrix.trans(-NATIVE_WIDTH/2, -NATIVE_HEIGHT/2)

    portrait = rotation == 90 or rotation == 270
    if portrait == false and WIDTH > HEIGHT then
        print("WARNING: landscape canvas (" .. WIDTH .. "x" .. HEIGHT .. ") - portrait-mounted signs need rotation 90 or 270")
    end
    compute_layout()
end)

util.json_watch("screen.json", function(new_screen)
    screen = new_screen
end)

util.data_mapper{
    ["time/set"] = function(new_local_time)
        local_time = new_local_time
    end;
}

local function get_assets()
    if not screen.show then
        return {{
            media = {
                asset_name = main_logo_name,
                type = "fallback",
            },
            duration = 5
        }}
    end

    return {{
        media = {
            asset_name = screen.show.poster_file,
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
        local max_w = scale_x(500)
        local max_h = scale_y(220)
        local box_x = (WIDTH - max_w) / 2
        local box_y = (HEIGHT - max_h) / 2
        black:draw(0, 0, WIDTH, HEIGHT)
        local x1, y1, x2, y2 = util.scale_into(max_w, max_h, w, h)
        obj:draw(box_x + x1, box_y + y1, box_x + x2, box_y + y2)
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
    local obj = resource.load_image(asset_name)
    local started

    local function start()
        started = sys.now()
    end
    local function draw()
        black:draw(0, 0, WIDTH, HEIGHT)
        draw_top_logo()

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

local function Video(asset_name)
    print("started new video " .. asset_name)
    local file = resource.open_file(asset_name)
    local obj

    local function start()
    end
    local function draw()
        black:draw(0, 0, WIDTH, HEIGHT)
        draw_top_logo()

        if not obj then
            obj = resource.load_video{
                file = file;
                raw = true;
            }
        end

        local state, vw, vh = obj:state()
        if state == "finished" then
            obj:dispose()
            obj = nil
        elseif state == "loaded" then
            draw_hugged_poster(vw, vh, function(x1, y1, x2, y2)
                obj:place(x1, y1, x2, y2)
            end)
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
    end
    return {
        start = start;
        draw = draw;
        unload = unload;
    }
end

local function Player()
    local offset = 0
    local current = Fallback(main_logo_name, 5)
    local next
    local current_key = ""

    local function asset_key()
        if not screen.show or screen.show.poster_file == "" then
            return "fallback:" .. main_logo_name
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
            current = Fallback(main_logo_name, 5)
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
            })[asset.media.type](asset.media.asset_name, asset.duration)
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
        font:write(x, y, ("Canvas: %dx%d rot %d"):format(WIDTH, HEIGHT, rotation), 12, 1,1,1,1); y=y+12
        font:write(x, y, ("Footer: y=%d h=%d"):format(layout.footer_y or -1, layout.footer_h or -1), 12, 1,1,1,1); y=y+12
        font:write(x, y, ("Showtime y=%d"):format(layout.showtime_y or -1), 12, 1,1,1,1); y=y+12
        if screen.show then
            font:write(x, y, "Show: "..screen.show.name, 12, 1,1,1,1); y=y+12
            font:write(x, y, "Status: "..(screen.show.status_label or ""), 12, 1,1,1,1); y=y+12
            font:write(x, y, "Start: "..(screen.show.start or ""), 12, 1,1,1,1); y=y+12
            font:write(x, y, "Media: "..(screen.show.media_type or ""), 12, 1,1,1,1); y=y+12
        end
    end
end

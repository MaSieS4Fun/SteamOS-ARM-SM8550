-- TODO: Make a vec2 class so we can alias .x and indices.

local steamdeck_lcd_colorimetry_spec = {
    r = { x = 0.602, y = 0.355 },
    g = { x = 0.340, y = 0.574 },
    b = { x = 0.164, y = 0.121 },
    w = { x = 0.3070, y = 0.3220 }
}

local steamdeck_lcd_colorimetry_measured = {
    r = { x = 0.603, y = 0.349 },
    g = { x = 0.335, y = 0.571 },
    b = { x = 0.163, y = 0.115 },
    w = { x = 0.296, y = 0.307 }
}

gamescope.config.known_displays.steamdeck_lcd = {
    pretty_name = "Steam Deck LCD",
    dynamic_refresh_rates = {
        40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
        50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
        60
    },
    hdr = {
        -- Setup some fallbacks or undocking with HDR
        -- for this display.
        supported = false,
        force_enabled = false,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 500,
        max_frame_average_luminance = 500,
        min_content_light_level = 0.5
    },
    -- Use measured colorimetry instead.
    --colorimetry = steamdeck_lcd_colorimetry_spec,
    colorimetry = steamdeck_lcd_colorimetry_measured,
    dynamic_modegen = function(base_mode, refresh)
        debug("Generating mode "..refresh.."Hz for Steam Deck LCD")
        local mode = base_mode

        -- These are only tuned for 800x1280.
        gamescope.modegen.set_resolution(mode, 800, 1280)

        -- hfp, hsync, hbp
        gamescope.modegen.set_h_timings(mode, 40, 4, 40)
        -- vfp, vsync, vbp
        gamescope.modegen.set_v_timings(mode, 30, 4, 8)
        mode.clock = gamescope.modegen.calc_max_clock(mode, refresh)
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)

        --debug(inspect(mode))
        return mode
    end,
    matches = function(display)
        local lcd_types = {
            { vendor = "WLC", model = "ANX7530 U" },
            { vendor = "ANX", model = "ANX7530 U" },
            { vendor = "VLV", model = "ANX7530 U" },
            { vendor = "VLV", model = "Jupiter" },
        }

        for index, value in ipairs(lcd_types) do
            if value.vendor == display.vendor and value.model == display.model then
                debug("[steamdeck_lcd] Matched vendor: "..value.vendor.." model: "..value.model)
                return 5000
            end
        end

        return -1
    end
} 
debug("Registered Steam Deck LCD as a known display")
--debug(inspect(gamescope.config.known_displays.steamdeck_lcd))

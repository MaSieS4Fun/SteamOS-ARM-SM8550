-- AYN Odin 2 / SM8550 internal DSI (no useful EDID — Steam reports "Unidentified EDID").
-- Without a known display profile, gamescope color management can scan out black
-- while input/touch still hits the composited 1920x1080 layer.

local odin2_dsi_colorimetry = {
    r = { x = 0.640, y = 0.330 },
    g = { x = 0.300, y = 0.600 },
    b = { x = 0.150, y = 0.060 },
    w = { x = 0.312, y = 0.329 },
}

gamescope.config.known_displays.ayn_odin2_dsi = {
    pretty_name = "AYN Odin 2 DSI",
    hdr = {
        supported = false,
        force_enabled = false,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 400,
        max_frame_average_luminance = 400,
        min_content_light_level = 0.5,
    },
    colorimetry = odin2_dsi_colorimetry,
    matches = function(display)
        -- Odin DSI panel exposes empty vendor/model in DRM (no EDID blob).
        if (display.vendor == nil or display.vendor == "")
            and (display.model == nil or display.model == "") then
            debug("[ayn_odin2_dsi] Matched empty vendor/model (SM8550 DSI)")
            return 4000
        end
        return -1
    end,
}
debug("Registered AYN Odin 2 DSI as a known display")

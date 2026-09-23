gamescope.modegen = {}

gamescope.modegen.adjust_front_porch = function(mode, vfp)
    local vsync = mode.vsync_end - mode.vsync_start
    local vbp = mode.vtotal - mode.vsync_end

    mode.vsync_start = mode.vdisplay + vfp
    mode.vsync_end = mode.vsync_start + vsync
    mode.vtotal = mode.vsync_end + vbp
end

gamescope.modegen.set_h_timings = function(mode, hfp, hsync, hbp)
    mode.hsync_start = mode.hdisplay + hfp
    mode.hsync_end = mode.hsync_start + hsync
    mode.htotal = mode.hsync_end + hbp
end

gamescope.modegen.set_v_timings = function(mode, vfp, vsync, vbp)
    mode.vsync_start = mode.vdisplay + vfp
    mode.vsync_end = mode.vsync_start + vsync
    mode.vtotal = mode.vsync_end + vbp
end

gamescope.modegen.set_resolution = function(mode, width, height)
    mode.hdisplay = width
    mode.vdisplay = height
end

gamescope.modegen.calc_max_clock = function(mode, refresh)
    -- LuaJIT does not have // operator, sad face.
    return math.floor( ( ( mode.htotal * mode.vtotal * refresh ) + 999 ) / 1000 )
end

gamescope.modegen.calc_vrefresh = function(mode, refresh)
    return math.floor( (1000 * mode.clock) / (mode.htotal * mode.vtotal) )
end

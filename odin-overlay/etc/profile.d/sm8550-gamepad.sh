# Native rsinput pad as SDL2 gamecontroller (not mouse).
export SDL_GAMECONTROLLERCONFIG_FILE="${SDL_GAMECONTROLLERCONFIG_FILE:-/etc/sdl2/qcom-gamecontrollerdb.txt}"
export SDL_VIDEO_X11_DGAMOUSE=0

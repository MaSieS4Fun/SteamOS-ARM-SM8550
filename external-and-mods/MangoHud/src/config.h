#pragma once
#ifndef MANGOHUD_CONFIG_H
#define MANGOHUD_CONFIG_H

#include "overlay_params.h"
#include <string>

void parseConfigFile(overlay_params& p);
std::string get_program_name();
// Default conf/presets dir under XDG_CONFIG_HOME:
//   desktop:  ".../MangoHud/"
//   steam:    ".../MangoHud/steam/"  (mangoapp-steam / mangohud-steam / MANGOHUD_PROFILE=steam)
std::string get_mangohud_config_subdir();
void parseConfigLine(std::string line, std::unordered_map<std::string, std::string>& options);
#endif //MANGOHUD_CONFIG_H

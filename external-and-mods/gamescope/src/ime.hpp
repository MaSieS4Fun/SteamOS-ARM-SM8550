// Input Method Editor

#pragma once

#include "wlserver.hpp"

void create_ime_manager(struct wlserver_t *wlserver);

struct wlserver_input_method *create_local_ime();
void destroy_ime(struct wlserver_input_method * ime);
void type_text(struct wlserver_input_method *ime, const char *text);

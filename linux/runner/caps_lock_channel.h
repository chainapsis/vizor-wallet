#ifndef RUNNER_CAPS_LOCK_CHANNEL_H_
#define RUNNER_CAPS_LOCK_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Owned by the view; reads GDK state for both X11 and Wayland.
void register_caps_lock_channel(FlView* view, GtkWindow* window);

#endif

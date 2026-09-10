// Test-only umbrella header: Flutter's Linux channel layer without GTK, so the
// Ledger handler compiles on any host that has glib. Points at the engine
// sources that ship with the Flutter SDK (see run_ledger_ble_tests.sh).
#ifndef VIZOR_TEST_CHANNEL_SHIM_FLUTTER_LINUX_H_
#define VIZOR_TEST_CHANNEL_SHIM_FLUTTER_LINUX_H_

#define __FLUTTER_LINUX_INSIDE__
#include "flutter/shell/platform/linux/public/flutter_linux/fl_value.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_binary_messenger.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_message_codec.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_method_response.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_method_codec.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_method_call.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_method_channel.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_event_channel.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_standard_message_codec.h"
#include "flutter/shell/platform/linux/public/flutter_linux/fl_standard_method_codec.h"
#undef __FLUTTER_LINUX_INSIDE__

// Only named by register_ledger_ble_handler, which the tests never call.
typedef struct _FlView FlView;
typedef struct _FlEngine FlEngine;
G_BEGIN_DECLS
FlEngine* fl_view_get_engine(FlView* view);
FlBinaryMessenger* fl_engine_get_binary_messenger(FlEngine* engine);
G_END_DECLS

#endif  // VIZOR_TEST_CHANNEL_SHIM_FLUTTER_LINUX_H_

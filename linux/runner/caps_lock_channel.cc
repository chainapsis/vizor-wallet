#include "caps_lock_channel.h"

#include <cstring>

namespace {
struct CapsLockChannel {
  GtkWindow* window;
  GdkKeymap* keymap;
  FlMethodChannel* channel;
  gulong state_handler;
  gulong keys_handler;
  gulong focus_handler;
};

FlValue* read_state(CapsLockChannel* self) {
  if (!gtk_window_is_active(self->window) || self->keymap == nullptr) {
    return fl_value_new_null();
  }
  return fl_value_new_bool(gdk_keymap_get_caps_lock_state(self->keymap));
}

void publish(CapsLockChannel* self) {
  g_autoptr(FlValue) value = read_state(self);
  fl_method_channel_invoke_method(self->channel, "onStateChanged", value,
                                  nullptr, nullptr, nullptr);
}

void state_changed(GdkKeymap*, gpointer data) {
  // Wayland delivers modifiers after keyboard focus enters. Keep listening
  // after the initial focus snapshot so that update is never lost.
  publish(static_cast<CapsLockChannel*>(data));
}

void focus_changed(GObject*, GParamSpec*, gpointer data) {
  publish(static_cast<CapsLockChannel*>(data));
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  if (std::strcmp(fl_method_call_get_name(call), "getCapsLockState") == 0) {
    g_autoptr(FlValue) state = read_state(static_cast<CapsLockChannel*>(data));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

void dispose_channel(GtkWidget*, gpointer data) {
  auto* self = static_cast<CapsLockChannel*>(data);
  if (self->keymap != nullptr) {
    g_signal_handler_disconnect(self->keymap, self->state_handler);
    g_signal_handler_disconnect(self->keymap, self->keys_handler);
    g_object_unref(self->keymap);
  }
  g_signal_handler_disconnect(self->window, self->focus_handler);
  fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                            nullptr);
  g_object_unref(self->channel);
  delete self;
}
}  // namespace

void register_caps_lock_channel(FlView* view, GtkWindow* window) {
  auto* self = new CapsLockChannel{};
  self->window = window;
  self->keymap = gdk_keymap_get_for_display(
      gtk_widget_get_display(GTK_WIDGET(view)));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.zcash.wallet/caps_lock", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call, self,
                                            nullptr);
  if (self->keymap != nullptr) {
    g_object_ref(self->keymap);
    self->state_handler = g_signal_connect(self->keymap, "state-changed",
                                          G_CALLBACK(state_changed), self);
    self->keys_handler = g_signal_connect(self->keymap, "keys-changed",
                                         G_CALLBACK(state_changed), self);
  }
  self->focus_handler = g_signal_connect(window, "notify::is-active",
                                         G_CALLBACK(focus_changed), self);
  g_signal_connect(view, "destroy", G_CALLBACK(dispose_channel), self);
}

#include <flutter_linux/flutter_linux.h>

#include <glib/gstdio.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

namespace {

FlMethodChannel* payment_channel = nullptr;
FlMethodCallHandler payment_handler = nullptr;
gpointer payment_handler_data = nullptr;

void Record(const char* event, gchar** arguments = nullptr) {
  FILE* file = fopen(g_getenv("VIZOR_TEST_EVENTS"), "a");
  g_assert_nonnull(file);
  fprintf(file, "%s\t%d", event, getpid());
  for (int i = 0; arguments != nullptr && arguments[i] != nullptr; ++i) {
    fprintf(file, "\t%s", arguments[i]);
  }
  fprintf(file, "\n");
  fclose(file);
}

gboolean Draw(GtkWidget* widget, cairo_t* cr, gpointer data) {
  cairo_set_source_rgb(cr, 0.055, 0.075, 0.075);
  cairo_paint(cr);
  cairo_set_source_rgb(cr, 0.9, 0.94, 0.9);
  cairo_select_font_face(cr, "Sans", CAIRO_FONT_SLANT_NORMAL,
                        CAIRO_FONT_WEIGHT_NORMAL);
  cairo_set_font_size(cr, 28);
  cairo_move_to(cr, 48, 80);
  cairo_show_text(cr, "Vizor native runner test");
  cairo_set_font_size(cr, 18);
  cairo_move_to(cr, 48, 120);
  cairo_show_text(cr, "Flutter content is substituted; GTK lifecycle is real.");
  return FALSE;
}

gboolean FirstFrame(gpointer data) {
  g_signal_emit_by_name(data, "first-frame");
  Record("first-frame");
  return G_SOURCE_REMOVE;
}

gboolean Control(gpointer data) {
  GtkWidget* view = GTK_WIDGET(data);
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(view));
  const gchar* path = g_getenv("VIZOR_TEST_CONTROL");
  g_autofree gchar* command = nullptr;
  if (!g_file_get_contents(path, &command, nullptr, nullptr)) {
    return G_SOURCE_CONTINUE;
  }
  g_unlink(path);
  g_strstrip(command);
  if (strcmp(command, "payment-ready") == 0) {
    g_assert_nonnull(payment_channel);
    FlMethodCall take{"takePendingUris"};
    payment_handler(payment_channel, &take, payment_handler_data);
    FlMethodCall ready{"ready"};
    payment_handler(payment_channel, &ready, payment_handler_data);
    Record("payment-ready");
  }
  if (strcmp(command, "close") == 0) {
    gtk_window_close(window);
    return G_SOURCE_REMOVE;
  }
  if (strcmp(command, "state") == 0) {
    const auto state = gdk_window_get_state(gtk_widget_get_window(
        GTK_WIDGET(window)));
    g_autofree gchar* value = g_strdup_printf(
        "{\"visible\":%s,\"iconified\":%s,\"active\":%s,\"windows\":%u}",
        gtk_widget_get_visible(GTK_WIDGET(window)) ? "true" : "false",
        state & GDK_WINDOW_STATE_ICONIFIED ? "true" : "false",
        gtk_window_is_active(window) ? "true" : "false",
        g_list_length(gtk_application_get_windows(
            gtk_window_get_application(window))));
    g_autofree gchar* output = g_strconcat(path, ".state", nullptr);
    g_file_set_contents(output, value, -1, nullptr);
  }
  if (strcmp(command, "capture") == 0) {
    GdkWindow* surface = gtk_widget_get_window(GTK_WIDGET(window));
    g_autoptr(GdkPixbuf) capture = gdk_pixbuf_get_from_window(
        surface, 0, 0, gdk_window_get_width(surface),
        gdk_window_get_height(surface));
    g_autoptr(GdkPixbuf) small =
        gdk_pixbuf_scale_simple(capture, 640, 360, GDK_INTERP_BILINEAR);
    g_autofree gchar* output = g_strconcat(path, ".png", nullptr);
    gdk_pixbuf_save(small, output, "png", nullptr, nullptr);
  }
  return G_SOURCE_CONTINUE;
}

gboolean CloseAfterDeadline(gpointer data) {
  // Bound a failed test through a normal window close, never a process signal.
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(data));
  if (GTK_IS_WINDOW(top)) gtk_window_close(GTK_WINDOW(top));
  return G_SOURCE_REMOVE;
}

}  // namespace

FlDartProject* fl_dart_project_new() { return g_new0(FlDartProject, 1); }

void fl_dart_project_free(FlDartProject* project) {
  g_strfreev(project->arguments);
  g_free(project);
}

void fl_dart_project_set_dart_entrypoint_arguments(FlDartProject* project,
                                                 gchar** arguments) {
  project->arguments = g_strdupv(arguments);
}

FlView* fl_view_new(FlDartProject* project) {
  GtkWidget* view = gtk_drawing_area_new();
  g_signal_new("first-frame", GTK_TYPE_DRAWING_AREA, G_SIGNAL_RUN_LAST, 0,
               nullptr, nullptr, nullptr, G_TYPE_NONE, 0);
  Record("engine", project->arguments);
  g_signal_connect(view, "draw", G_CALLBACK(Draw), nullptr);
  const gchar* delay = g_getenv("VIZOR_TEST_FRAME_DELAY_MS");
  g_timeout_add_full(G_PRIORITY_DEFAULT, delay == nullptr ? 30 : atoi(delay),
                     FirstFrame, g_object_ref(view), g_object_unref);
  g_timeout_add_full(G_PRIORITY_DEFAULT, 20, Control, g_object_ref(view),
                     g_object_unref);
  g_timeout_add_seconds_full(G_PRIORITY_DEFAULT, 45, CloseAfterDeadline,
                             g_object_ref(view), g_object_unref);
  return view;
}

void fl_view_set_background_color(FlView* view, const GdkRGBA* color) {}

void fl_register_plugins(FlPluginRegistry* registry) { Record("plugins"); }

void fl_value_unref(FlValue* value) { delete value; }
void fl_method_response_free(FlMethodResponse* response) {
  delete response->value;
  delete response;
}
FlValue* fl_value_new_list() { return new FlValue(); }
FlValue* fl_value_new_string(const gchar* value) {
  return new FlValue{{value}};
}
void fl_value_append_take(FlValue* list, FlValue* value) {
  list->strings.insert(list->strings.end(), value->strings.begin(),
                       value->strings.end());
  delete value;
}
const gchar* fl_method_call_get_name(FlMethodCall* call) { return call->name; }
FlMethodResponse* fl_method_success_response_new(FlValue* value) {
  return new FlMethodResponse{value == nullptr ? nullptr : new FlValue(*value)};
}
FlMethodResponse* fl_method_not_implemented_response_new() {
  return new FlMethodResponse{nullptr};
}
static void RecordUris(FlValue* value) {
  if (value == nullptr) return;
  for (const auto& uri : value->strings) {
    gchar* arguments[] = {const_cast<gchar*>(uri.c_str()), nullptr};
    Record("payment-uri", arguments);
  }
}
void fl_method_call_respond(FlMethodCall* call, FlMethodResponse* response,
                            GError**) {
  if (strcmp(call->name, "takePendingUris") == 0) RecordUris(response->value);
}
FlStandardMethodCodec* fl_standard_method_codec_new() {
  return G_OBJECT(g_object_new(G_TYPE_OBJECT, nullptr));
}
FlEngine* fl_view_get_engine(FlView* view) { return G_OBJECT(view); }
GObject* fl_engine_get_binary_messenger(FlEngine* engine) { return engine; }
FlMethodChannel* fl_method_channel_new(GObject*, const gchar*, GObject*) {
  payment_channel = G_OBJECT(g_object_new(G_TYPE_OBJECT, nullptr));
  g_object_add_weak_pointer(payment_channel,
                             reinterpret_cast<gpointer*>(&payment_channel));
  return payment_channel;
}
void fl_method_channel_set_method_call_handler(
    FlMethodChannel*, FlMethodCallHandler handler, gpointer data, GDestroyNotify) {
  payment_handler = handler;
  payment_handler_data = data;
}
void fl_method_channel_invoke_method(FlMethodChannel*, const gchar* method,
                                      FlValue* value, GCancellable*,
                                      GAsyncReadyCallback, gpointer) {
  g_assert_cmpstr(method, ==, "onUris");
  RecordUris(value);
}

extern "C" gint __real_gtk_dialog_run(GtkDialog* dialog);

extern "C" gint __wrap_gtk_dialog_run(GtkDialog* dialog) {
  Record("dialog");
  g_timeout_add(150, [](gpointer data) -> gboolean {
    gtk_dialog_response(GTK_DIALOG(data), GTK_RESPONSE_CLOSE);
    return G_SOURCE_REMOVE;
  }, dialog);
  return __real_gtk_dialog_run(dialog);
}

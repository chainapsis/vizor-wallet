#ifndef VIZOR_TEST_FLUTTER_LINUX_H_
#define VIZOR_TEST_FLUTTER_LINUX_H_

#include <gtk/gtk.h>
#include <string>
#include <vector>

// Only Flutter is substituted: the production runner, GTK, GApplication,
// D-Bus, native window manager, and OS lock all run normally in this test.
struct FlDartProject {
  gchar** arguments;
};
using FlView = GtkWidget;
using FlPluginRegistry = GtkWidget;

FlDartProject* fl_dart_project_new();
void fl_dart_project_free(FlDartProject* project);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(FlDartProject, fl_dart_project_free)
void fl_dart_project_set_dart_entrypoint_arguments(FlDartProject* project,
                                                 gchar** arguments);
FlView* fl_view_new(FlDartProject* project);
void fl_view_set_background_color(FlView* view, const GdkRGBA* color);
#define FL_PLUGIN_REGISTRY(view) (view)

// Substitute only the Flutter channel boundary; URI dispatch and buffering
// continue to execute in the production runner.
using FlEngine = GObject;
using FlStandardMethodCodec = GObject;
using FlMethodChannel = GObject;
struct FlValue { std::vector<std::string> strings; };
struct FlMethodCall { const gchar* name; };
struct FlMethodResponse { FlValue* value; };
using FlMethodCallHandler = void (*)(FlMethodChannel*, FlMethodCall*, gpointer);

void fl_value_unref(FlValue* value);
void fl_method_response_free(FlMethodResponse* response);
G_DEFINE_AUTOPTR_CLEANUP_FUNC(FlValue, fl_value_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(FlMethodResponse, fl_method_response_free)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(FlStandardMethodCodec, g_object_unref)
FlValue* fl_value_new_list();
FlValue* fl_value_new_string(const gchar* value);
void fl_value_append_take(FlValue* list, FlValue* value);
const gchar* fl_method_call_get_name(FlMethodCall* call);
FlMethodResponse* fl_method_success_response_new(FlValue* value);
FlMethodResponse* fl_method_not_implemented_response_new();
void fl_method_call_respond(FlMethodCall*, FlMethodResponse*, GError**);
FlStandardMethodCodec* fl_standard_method_codec_new();
FlEngine* fl_view_get_engine(FlView* view);
GObject* fl_engine_get_binary_messenger(FlEngine* engine);
FlMethodChannel* fl_method_channel_new(GObject*, const gchar*, GObject*);
void fl_method_channel_set_method_call_handler(
    FlMethodChannel*, FlMethodCallHandler, gpointer, GDestroyNotify);
void fl_method_channel_invoke_method(
    FlMethodChannel*, const gchar*, FlValue*, GCancellable*, GAsyncReadyCallback,
    gpointer);
#define FL_METHOD_RESPONSE(value) (value)
#define FL_METHOD_CODEC(value) (value)

#endif

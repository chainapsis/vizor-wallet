#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* payment_uri_channel;
  GPtrArray* pending_payment_uris;
  gboolean payment_uri_dart_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void register_icon_theme_paths() {
  GtkIconTheme* icon_theme = gtk_icon_theme_get_default();

  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* bundled_icons =
        g_build_filename(exe_dir, "data", "icons", nullptr);
    if (g_file_test(bundled_icons, G_FILE_TEST_IS_DIR)) {
      gtk_icon_theme_append_search_path(icon_theme, bundled_icons);
    }
  }

  if (g_file_test(APP_ICON_THEME_PATH, G_FILE_TEST_IS_DIR)) {
    gtk_icon_theme_append_search_path(icon_theme, APP_ICON_THEME_PATH);
  }
}

static gboolean is_zcash_uri(const gchar* value) {
  return value != nullptr && g_ascii_strncasecmp(value, "zcash:", 6) == 0;
}

static void add_pending_payment_uri(MyApplication* self, const gchar* value) {
  if (!is_zcash_uri(value)) {
    return;
  }
  g_ptr_array_add(self->pending_payment_uris, g_strdup(value));
}

static FlValue* take_pending_payment_uris(MyApplication* self) {
  FlValue* uris = fl_value_new_list();
  for (guint i = 0; i < self->pending_payment_uris->len; ++i) {
    const gchar* uri =
        static_cast<const gchar*>(g_ptr_array_index(self->pending_payment_uris, i));
    fl_value_append_take(uris, fl_value_new_string(uri));
  }
  g_ptr_array_set_size(self->pending_payment_uris, 0);
  return uris;
}

static void flush_pending_payment_uris(MyApplication* self) {
  if (!self->payment_uri_dart_ready || self->payment_uri_channel == nullptr ||
      self->pending_payment_uris->len == 0) {
    return;
  }

  g_autoptr(FlValue) uris = take_pending_payment_uris(self);
  fl_method_channel_invoke_method(self->payment_uri_channel, "onUris", uris,
                                  nullptr, nullptr, nullptr);
}

static void payment_uri_method_call_cb(FlMethodChannel* channel,
                                       FlMethodCall* method_call,
                                       gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (std::strcmp(method, "takePendingUris") == 0) {
    g_autoptr(FlValue) uris = take_pending_payment_uris(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(uris));
  } else if (std::strcmp(method, "ready") == 0) {
    self->payment_uri_dart_ready = TRUE;
    flush_pending_payment_uris(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static void register_payment_uri_channel(MyApplication* self, FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlEngine* engine = fl_view_get_engine(view);
  self->payment_uri_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "com.zcash.wallet/payment_uri",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->payment_uri_channel,
                                            payment_uri_method_call_cb,
                                            g_object_ref(self), g_object_unref);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  register_icon_theme_paths();
  gtk_window_set_default_icon_name(APP_ICON_NAME);

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  gtk_window_set_icon_name(window, APP_ICON_NAME);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, APP_DISPLAY_NAME);
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, APP_DISPLAY_NAME);
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  register_payment_uri_channel(self, view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  for (gchar** argument = self->dart_entrypoint_arguments;
       argument != nullptr && *argument != nullptr; ++argument) {
    add_pending_payment_uri(self, *argument);
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_object(&self->payment_uri_channel);
  g_clear_pointer(&self->pending_payment_uris, g_ptr_array_unref);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_payment_uris = g_ptr_array_new_with_free_func(g_free);
  self->payment_uri_dart_ready = FALSE;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

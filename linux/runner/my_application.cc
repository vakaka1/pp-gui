#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void my_application_activate(GApplication* application) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  gtk_window_set_title(window, "PP GUI");
  gtk_window_set_default_size(window, 430, 760);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  GError* icon_error = nullptr;
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* exe_dir =
      exe_path != nullptr ? g_path_get_dirname(exe_path) : g_get_current_dir();
  g_autofree gchar* bundled_icon = g_build_filename(
      exe_dir, "data", "flutter_assets", "assets", "app_icon_512.png", nullptr);
  if (!gtk_window_set_icon_from_file(window, bundled_icon, &icon_error) &&
      icon_error) {
    g_clear_error(&icon_error);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
  gtk_widget_show(GTK_WIDGET(window));
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
}

static void my_application_init(MyApplication* self) {
  (void)self;
}

MyApplication* my_application_new() {
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id",
                                     APPLICATION_ID,
                                     "flags",
                                     G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}

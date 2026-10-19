/*
 * vana-shell — the openVana 1.0 desktop shell.
 *
 * Draws a black background, a bottom panel with the openVana start button
 * and a clock, and a start menu listing every installed application
 * (Chromium, Android apps from Waydroid, Windows apps from Wine).
 *
 * Send SIGUSR1 to toggle the start menu (bound to the Super key).
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
#include <gio/gdesktopappinfo.h>
#include <glib-unix.h>

#ifndef VANA_DATADIR
#define VANA_DATADIR "/usr/share/openvana"
#endif

#define PANEL_HEIGHT 44

static GtkWidget *menu_win;
static GtkWidget *app_list;
static GtkWidget *search_entry;
static GtkWidget *clock_label;

static const char *css =
    "window.vana-bg { background: #000000; }"
    "window.vana-panel { background: rgba(10,10,10,0.92); }"
    "window.vana-menu { background: #101010; border: 1px solid #1f1f1f;"
    "  border-radius: 14px; }"
    "button.vana-start { padding: 4px; margin: 4px 6px; border: none;"
    "  background: transparent; border-radius: 10px; box-shadow: none; }"
    "button.vana-start:hover { background: #1c1c1c; }"
    "label.vana-clock { color: #f0f0ec; margin: 0 14px; font-size: 13px; }"
    "entry.vana-search { margin: 14px; padding: 8px 12px; border-radius: 10px;"
    "  background: #1a1a1a; color: #f0f0ec; border: 1px solid #262626; }"
    "entry.vana-search:focus { border-color: #4CDB9A; }"
    "list { background: transparent; }"
    "list row { padding: 6px 10px; border-radius: 8px; margin: 0 8px; }"
    "list row:hover, list row:selected { background: #0E3B2C; }"
    "list row label { color: #f0f0ec; }"
    "button.vana-action { color: #f0f0ec; background: #1a1a1a; border: none;"
    "  border-radius: 8px; padding: 6px 10px; box-shadow: none; }"
    "button.vana-action:hover { background: #0E3B2C; }"
    "label.vana-title { color: #4CDB9A; font-weight: bold; margin: 14px 14px 0; }";

static void menu_hide(void) { gtk_widget_hide(menu_win); }

static void spawn(const char *const *argv)
{
    GError *err = NULL;
    if (!g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH,
                       NULL, NULL, NULL, &err)) {
        g_warning("spawn %s: %s", argv[0], err->message);
        g_error_free(err);
    }
}

/* ---------- application list ---------- */

static gint app_cmp(gconstpointer a, gconstpointer b)
{
    return g_utf8_collate(g_app_info_get_display_name(G_APP_INFO(a)),
                          g_app_info_get_display_name(G_APP_INFO(b)));
}

static void on_row_activated(GtkListBox *box, GtkListBoxRow *row, gpointer d)
{
    GAppInfo *app = g_object_get_data(G_OBJECT(row), "app");
    GError *err = NULL;
    menu_hide();
    if (app && !g_app_info_launch(app, NULL, NULL, &err)) {
        g_warning("launch: %s", err->message);
        g_error_free(err);
    }
}

static gboolean filter_row(GtkListBoxRow *row, gpointer d)
{
    const char *q = gtk_entry_get_text(GTK_ENTRY(search_entry));
    if (!q || !*q)
        return TRUE;
    GAppInfo *app = g_object_get_data(G_OBJECT(row), "app");
    g_autofree char *name = g_utf8_casefold(g_app_info_get_display_name(app), -1);
    g_autofree char *needle = g_utf8_casefold(q, -1);
    return strstr(name, needle) != NULL;
}

static void rebuild_apps(void)
{
    GList *children = gtk_container_get_children(GTK_CONTAINER(app_list));
    for (GList *l = children; l; l = l->next)
        gtk_widget_destroy(l->data);
    g_list_free(children);

    GList *apps = g_list_sort(g_app_info_get_all(), app_cmp);
    for (GList *l = apps; l; l = l->next) {
        GAppInfo *app = l->data;
        if (!g_app_info_should_show(app))
            continue;
        GtkWidget *row = gtk_list_box_row_new();
        GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
        GIcon *gicon = g_app_info_get_icon(app);
        GtkWidget *img = gicon
            ? gtk_image_new_from_gicon(gicon, GTK_ICON_SIZE_DND)
            : gtk_image_new_from_icon_name("application-x-executable",
                                           GTK_ICON_SIZE_DND);
        gtk_image_set_pixel_size(GTK_IMAGE(img), 28);
        GtkWidget *lbl = gtk_label_new(g_app_info_get_display_name(app));
        gtk_label_set_xalign(GTK_LABEL(lbl), 0);
        gtk_label_set_ellipsize(GTK_LABEL(lbl), PANGO_ELLIPSIZE_END);
        gtk_box_pack_start(GTK_BOX(box), img, FALSE, FALSE, 0);
        gtk_box_pack_start(GTK_BOX(box), lbl, TRUE, TRUE, 0);
        gtk_container_add(GTK_CONTAINER(row), box);
        g_object_set_data_full(G_OBJECT(row), "app", g_object_ref(app),
                               g_object_unref);
        gtk_container_add(GTK_CONTAINER(app_list), row);
    }
    g_list_free_full(apps, g_object_unref);
    gtk_widget_show_all(app_list);
}

/* ---------- file pickers for APK / EXE ---------- */

static char *pick_file(const char *title, const char *filter_name,
                       const char *const *patterns)
{
    GtkWidget *dlg = gtk_file_chooser_dialog_new(
        title, NULL, GTK_FILE_CHOOSER_ACTION_OPEN, "_Cancel",
        GTK_RESPONSE_CANCEL, "_Open", GTK_RESPONSE_ACCEPT, NULL);
    GtkFileFilter *f = gtk_file_filter_new();
    gtk_file_filter_set_name(f, filter_name);
    for (; *patterns; patterns++)
        gtk_file_filter_add_pattern(f, *patterns);
    gtk_file_chooser_add_filter(GTK_FILE_CHOOSER(dlg), f);
    gtk_file_chooser_set_current_folder(GTK_FILE_CHOOSER(dlg),
                                        g_get_user_special_dir(G_USER_DIRECTORY_DOWNLOAD)
                                            ?: g_get_home_dir());
    char *path = NULL;
    if (gtk_dialog_run(GTK_DIALOG(dlg)) == GTK_RESPONSE_ACCEPT)
        path = gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dlg));
    gtk_widget_destroy(dlg);
    return path;
}

static void on_install_apk(GtkButton *b, gpointer d)
{
    static const char *const pats[] = {"*.apk", "*.APK", NULL};
    menu_hide();
    g_autofree char *p = pick_file("Install Android app", "Android apps", pats);
    if (p) {
        const char *argv[] = {"vana-apk", "install", p, NULL};
        spawn(argv);
    }
}

static void on_run_exe(GtkButton *b, gpointer d)
{
    static const char *const pats[] = {"*.exe", "*.EXE", "*.msi", "*.MSI", NULL};
    menu_hide();
    g_autofree char *p = pick_file("Run Windows program", "Windows programs", pats);
    if (p) {
        const char *argv[] = {"vana-exe", p, NULL};
        spawn(argv);
    }
}

static void on_power(GtkButton *b, gpointer cmd)
{
    const char *argv[] = {"doas", "-n", cmd, NULL};
    spawn(argv);
}

/* ---------- start menu ---------- */

static void menu_show(void)
{
    rebuild_apps();
    gtk_entry_set_text(GTK_ENTRY(search_entry), "");
    gtk_widget_show_all(menu_win);
    gtk_widget_grab_focus(search_entry);
}

static void menu_toggle(void)
{
    if (gtk_widget_get_visible(menu_win))
        menu_hide();
    else
        menu_show();
}

static gboolean on_sigusr1(gpointer d)
{
    menu_toggle();
    return G_SOURCE_CONTINUE;
}

static gboolean on_menu_key(GtkWidget *w, GdkEventKey *ev, gpointer d)
{
    if (ev->keyval == GDK_KEY_Escape) {
        menu_hide();
        return TRUE;
    }
    if (ev->keyval == GDK_KEY_Return && gtk_widget_has_focus(search_entry)) {
        /* launch the first visible match */
        GList *rows = gtk_container_get_children(GTK_CONTAINER(app_list));
        for (GList *l = rows; l; l = l->next)
            if (gtk_widget_get_child_visible(l->data)) {
                on_row_activated(NULL, l->data, NULL);
                break;
            }
        g_list_free(rows);
        return TRUE;
    }
    return FALSE;
}

static void on_search_changed(GtkEditable *e, gpointer d)
{
    gtk_list_box_invalidate_filter(GTK_LIST_BOX(app_list));
}

static GtkWidget *action_button(const char *label, GCallback cb, gpointer data)
{
    GtkWidget *b = gtk_button_new_with_label(label);
    gtk_style_context_add_class(gtk_widget_get_style_context(b), "vana-action");
    g_signal_connect(b, "clicked", cb, data);
    return b;
}

static void build_menu(void)
{
    menu_win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_style_context_add_class(gtk_widget_get_style_context(menu_win), "vana-menu");
    gtk_widget_set_size_request(menu_win, 380, -1);
    gtk_layer_init_for_window(GTK_WINDOW(menu_win));
    gtk_layer_set_namespace(GTK_WINDOW(menu_win), "vana-menu");
    gtk_layer_set_layer(GTK_WINDOW(menu_win), GTK_LAYER_SHELL_LAYER_OVERLAY);
    gtk_layer_set_anchor(GTK_WINDOW(menu_win), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(menu_win), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_margin(GTK_WINDOW(menu_win), GTK_LAYER_SHELL_EDGE_LEFT, 8);
    gtk_layer_set_margin(GTK_WINDOW(menu_win), GTK_LAYER_SHELL_EDGE_BOTTOM, 8);
    gtk_layer_set_keyboard_mode(GTK_WINDOW(menu_win),
                                GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);
    g_signal_connect(menu_win, "key-press-event", G_CALLBACK(on_menu_key), NULL);
    g_signal_connect(menu_win, "delete-event",
                     G_CALLBACK(gtk_widget_hide_on_delete), NULL);

    GtkWidget *vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    GtkWidget *title = gtk_label_new("openVana 1.0");
    gtk_label_set_xalign(GTK_LABEL(title), 0);
    gtk_style_context_add_class(gtk_widget_get_style_context(title), "vana-title");

    search_entry = gtk_search_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(search_entry), "Search apps");
    gtk_style_context_add_class(gtk_widget_get_style_context(search_entry), "vana-search");
    g_signal_connect(search_entry, "changed", G_CALLBACK(on_search_changed), NULL);

    app_list = gtk_list_box_new();
    gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(app_list), TRUE);
    gtk_list_box_set_filter_func(GTK_LIST_BOX(app_list), filter_row, NULL, NULL);
    g_signal_connect(app_list, "row-activated", G_CALLBACK(on_row_activated), NULL);
    GtkWidget *scroll = gtk_scrolled_window_new(NULL, NULL);
    gtk_scrolled_window_set_policy(GTK_SCROLLED_WINDOW(scroll),
                                   GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(scroll), 380);
    gtk_container_add(GTK_CONTAINER(scroll), app_list);

    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_container_set_border_width(GTK_CONTAINER(actions), 12);
    gtk_box_pack_start(GTK_BOX(actions),
                       action_button("Install APK…", G_CALLBACK(on_install_apk), NULL),
                       FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(actions),
                       action_button("Run EXE…", G_CALLBACK(on_run_exe), NULL),
                       FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(actions),
                     action_button("⏻", G_CALLBACK(on_power), "poweroff"),
                     FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(actions),
                     action_button("⟳", G_CALLBACK(on_power), "reboot"),
                     FALSE, FALSE, 0);

    gtk_box_pack_start(GTK_BOX(vbox), title, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), search_entry, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), scroll, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(vbox), actions, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(menu_win), vbox);
}

/* ---------- background + panel ---------- */

static void build_background(GdkMonitor *mon)
{
    GtkWidget *w = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_style_context_add_class(gtk_widget_get_style_context(w), "vana-bg");
    gtk_layer_init_for_window(GTK_WINDOW(w));
    gtk_layer_set_namespace(GTK_WINDOW(w), "vana-background");
    gtk_layer_set_monitor(GTK_WINDOW(w), mon);
    gtk_layer_set_layer(GTK_WINDOW(w), GTK_LAYER_SHELL_LAYER_BACKGROUND);
    gtk_layer_set_exclusive_zone(GTK_WINDOW(w), -1);
    for (int e = 0; e < GTK_LAYER_SHELL_EDGE_ENTRY_NUMBER; e++)
        gtk_layer_set_anchor(GTK_WINDOW(w), e, TRUE);
    gtk_widget_show_all(w);
}

static gboolean update_clock(gpointer d)
{
    g_autoptr(GDateTime) now = g_date_time_new_now_local();
    g_autofree char *s = g_date_time_format(now, "%H:%M\n%d.%m.%Y");
    gtk_label_set_text(GTK_LABEL(clock_label), s);
    return G_SOURCE_CONTINUE;
}

static void build_panel(void)
{
    GtkWidget *w = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_style_context_add_class(gtk_widget_get_style_context(w), "vana-panel");
    gtk_widget_set_size_request(w, -1, PANEL_HEIGHT);
    gtk_layer_init_for_window(GTK_WINDOW(w));
    gtk_layer_set_namespace(GTK_WINDOW(w), "vana-panel");
    gtk_layer_set_layer(GTK_WINDOW(w), GTK_LAYER_SHELL_LAYER_TOP);
    gtk_layer_set_anchor(GTK_WINDOW(w), GTK_LAYER_SHELL_EDGE_BOTTOM, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(w), GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_anchor(GTK_WINDOW(w), GTK_LAYER_SHELL_EDGE_RIGHT, TRUE);
    gtk_layer_auto_exclusive_zone_enable(GTK_WINDOW(w));

    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    GtkWidget *start = gtk_button_new();
    gtk_style_context_add_class(gtk_widget_get_style_context(start), "vana-start");
    gtk_widget_set_tooltip_text(start, "Start");
    GdkPixbuf *pb = gdk_pixbuf_new_from_file_at_size(VANA_DATADIR "/logo.svg",
                                                     30, 30, NULL);
    gtk_button_set_image(GTK_BUTTON(start),
                         pb ? gtk_image_new_from_pixbuf(pb)
                            : gtk_image_new_from_icon_name("start-here", GTK_ICON_SIZE_DND));
    gtk_button_set_always_show_image(GTK_BUTTON(start), TRUE);
    if (pb)
        g_object_unref(pb);
    g_signal_connect_swapped(start, "clicked", G_CALLBACK(menu_toggle), NULL);

    clock_label = gtk_label_new("");
    gtk_label_set_justify(GTK_LABEL(clock_label), GTK_JUSTIFY_RIGHT);
    gtk_style_context_add_class(gtk_widget_get_style_context(clock_label), "vana-clock");
    update_clock(NULL);
    g_timeout_add_seconds(10, update_clock, NULL);

    gtk_box_pack_start(GTK_BOX(box), start, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(box), clock_label, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(w), box);
    gtk_widget_show_all(w);
}

int main(int argc, char **argv)
{
    gtk_init(&argc, &argv);
    if (!gtk_layer_is_supported()) {
        g_printerr("vana-shell: compositor lacks wlr-layer-shell\n");
        return 1;
    }

    GtkCssProvider *prov = gtk_css_provider_new();
    gtk_css_provider_load_from_data(prov, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(),
                                              GTK_STYLE_PROVIDER(prov),
                                              GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    GdkDisplay *dpy = gdk_display_get_default();
    for (int i = 0; i < gdk_display_get_n_monitors(dpy); i++)
        build_background(gdk_display_get_monitor(dpy, i));
    build_panel();
    build_menu();

    g_unix_signal_add(SIGUSR1, on_sigusr1, NULL);
    gtk_main();
    return 0;
}

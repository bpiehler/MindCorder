#include <pebble.h>
#include "protocol.h"

Window *s_window = NULL;
static Window *s_idle_window = NULL;
static bool s_phone_connected = false;

static void safe_window_push(Window *new_window, bool animated) {
  Window *old_window = s_window;
  s_window = new_window;
  if (new_window) {
    window_stack_push(new_window, animated);
  }
  if (old_window) {
    window_stack_remove(old_window, false);
    window_destroy(old_window);
  }
}

extern int storage_get_note_count(void);
extern bool storage_get_note_id(int index, uint32_t *note_id);
extern bool storage_get_title(uint32_t note_id, char *buf, size_t bufsize, uint32_t *timestamp);

// ---- Idle Screen ----
static TextLayer *s_idle_title, *s_idle_subtitle;

static void idle_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_idle_title = text_layer_create(GRect(0, 50, bounds.size.w, 40));
  text_layer_set_text(s_idle_title, "MindCorder");
  text_layer_set_font(s_idle_title, fonts_get_system_font(FONT_KEY_GOTHIC_28_BOLD));
  text_layer_set_text_alignment(s_idle_title, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_idle_title));

  s_idle_subtitle = text_layer_create(GRect(0, 95, bounds.size.w, 30));
  text_layer_set_text(s_idle_subtitle, "Tap Select to Record");
  text_layer_set_font(s_idle_subtitle, fonts_get_system_font(FONT_KEY_GOTHIC_18));
  text_layer_set_text_alignment(s_idle_subtitle, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_idle_subtitle));
}

static void idle_window_unload(Window *window) {
  text_layer_destroy(s_idle_subtitle);
  text_layer_destroy(s_idle_title);
  if (s_idle_window == window) {
    s_idle_window = NULL;
  }
}

void window_idle_push(void) {
  Window *win = window_create();
  s_idle_window = win;
  window_set_window_handlers(win, (WindowHandlers){
    .load = idle_window_load,
    .unload = idle_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

// ---- Listening Screen ----
static TextLayer *s_listening_label;

static void listening_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_listening_label = text_layer_create(GRect(0, 90, bounds.size.w, 30));
  text_layer_set_text(s_listening_label, "Listening...");
  text_layer_set_font(s_listening_label, fonts_get_system_font(FONT_KEY_GOTHIC_24_BOLD));
  text_layer_set_text_alignment(s_listening_label, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_listening_label));
}

static void listening_window_unload(Window *window) {
  text_layer_destroy(s_listening_label);
}

void window_listening_push(void) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = listening_window_load,
    .unload = listening_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

// ---- Processing Screen ----
static TextLayer *s_processing_label;
static TextLayer *s_processing_title;

static void processing_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_processing_label = text_layer_create(GRect(0, 80, bounds.size.w, 30));
  text_layer_set_text(s_processing_label, "Processing...");
  text_layer_set_font(s_processing_label, fonts_get_system_font(FONT_KEY_GOTHIC_24));
  text_layer_set_text_alignment(s_processing_label, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_processing_label));

  s_processing_title = text_layer_create(GRect(10, 120, bounds.size.w - 20, 40));
  text_layer_set_text(s_processing_title, "");
  text_layer_set_font(s_processing_title, fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD));
  text_layer_set_text_alignment(s_processing_title, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_processing_title));
}

static void processing_window_unload(Window *window) {
  text_layer_destroy(s_processing_label);
  text_layer_destroy(s_processing_title);
  s_processing_label = NULL;
  s_processing_title = NULL;
}

void window_processing_push(void) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = processing_window_load,
    .unload = processing_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

void update_processing_title(const char *title) {
  if (s_processing_title) {
    text_layer_set_text(s_processing_title, title);
  }
}

// ---- Summary Screen ----
static ScrollLayer *s_summary_scroll;
static TextLayer *s_summary_title, *s_summary_body;

static void summary_scroll_click_config_provider(void *context) {
  window_single_click_subscribe(BUTTON_ID_SELECT, select_click_handler);
  window_single_click_subscribe(BUTTON_ID_BACK, back_click_handler);
}

static void summary_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_summary_scroll = scroll_layer_create(bounds);
  scroll_layer_set_callbacks(s_summary_scroll, (ScrollLayerCallbacks){
    .click_config_provider = summary_scroll_click_config_provider
  });
  scroll_layer_set_click_config_onto_window(s_summary_scroll, window);

#ifdef PBL_ROUND
  scroll_layer_set_paging(s_summary_scroll, true);
#endif

  s_summary_title = text_layer_create(GRect(10, PBL_IF_ROUND_ELSE(20, 10), bounds.size.w - 20, 30));
  text_layer_set_text(s_summary_title, s_current_title);
  text_layer_set_font(s_summary_title, fonts_get_system_font(FONT_KEY_GOTHIC_18_BOLD));
  text_layer_set_text_alignment(s_summary_title, GTextAlignmentCenter);

  s_summary_body = text_layer_create(GRect(10, PBL_IF_ROUND_ELSE(55, 45), bounds.size.w - 20, 2000));
  text_layer_set_text(s_summary_body, s_current_body);
  text_layer_set_font(s_summary_body, fonts_get_system_font(FONT_KEY_GOTHIC_14));
  text_layer_set_overflow_mode(s_summary_body, GTextOverflowModeWordWrap);
#ifdef PBL_ROUND
  text_layer_set_text_alignment(s_summary_body, GTextAlignmentCenter);
#endif

  scroll_layer_add_child(s_summary_scroll, text_layer_get_layer(s_summary_title));
  scroll_layer_add_child(s_summary_scroll, text_layer_get_layer(s_summary_body));
  layer_add_child(root, scroll_layer_get_layer(s_summary_scroll));

#ifdef PBL_ROUND
  text_layer_enable_screen_text_flow_and_paging(s_summary_body, 8);
#endif

  GSize body_size = text_layer_get_content_size(s_summary_body);
  text_layer_set_size(s_summary_body, GSize(bounds.size.w - 20, body_size.h + 10));
  
  int content_height = PBL_IF_ROUND_ELSE(55, 45) + body_size.h + PBL_IF_ROUND_ELSE(30, 20);
  scroll_layer_set_content_size(s_summary_scroll, GSize(bounds.size.w, content_height));
}

static void summary_window_unload(Window *window) {
  text_layer_destroy(s_summary_body);
  text_layer_destroy(s_summary_title);
  scroll_layer_destroy(s_summary_scroll);
}

void window_summary_push(const char *title, const char *body) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = summary_window_load,
    .unload = summary_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

// ---- Note List Screen ----
static MenuLayer *s_menu_layer;
int s_menu_index = 0;

static uint16_t menu_get_num_rows_callback(MenuLayer *menu_layer, uint16_t section_index, void *context) {
  int count = storage_get_note_count();
  return count > 0 ? count : 1;
}

static void menu_draw_row_callback(GContext *ctx, const Layer *cell_layer, MenuIndex *cell_index, void *context) {
  uint32_t note_id;
  char title[MAX_TITLE_LEN];
  uint32_t timestamp;

  if (storage_get_note_id(cell_index->row, &note_id) &&
      storage_get_title(note_id, title, sizeof(title), &timestamp)) {
    menu_cell_basic_draw(ctx, cell_layer, title, NULL, NULL);
  } else {
    menu_cell_basic_draw(ctx, cell_layer, "No notes yet", NULL, NULL);
  }
}

static void menu_select_callback(MenuLayer *menu_layer, MenuIndex *cell_index, void *context) {
  s_menu_index = cell_index->row;
  select_click_handler(context, NULL);
}

static void notelist_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_menu_layer = menu_layer_create(GRect(0, 0, bounds.size.w, bounds.size.h));
  static const MenuLayerCallbacks s_menu_callbacks = {
    .get_num_rows = menu_get_num_rows_callback,
    .draw_row = menu_draw_row_callback,
    .select_click = menu_select_callback,
  };
  menu_layer_set_callbacks(s_menu_layer, NULL, s_menu_callbacks);
  menu_layer_set_click_config_onto_window(s_menu_layer, window);
  layer_add_child(root, menu_layer_get_layer(s_menu_layer));
}

static void notelist_window_unload(Window *window) {
  menu_layer_destroy(s_menu_layer);
  s_menu_layer = NULL;
  if (s_window == window) {
    s_window = s_idle_window;
  }
  if (is_current_state_notelist()) {
    force_state_idle();
  }
}

void window_notelist_push(void) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = notelist_window_load,
    .unload = notelist_window_unload,
  });
  if (s_window && s_window != s_idle_window) {
    safe_window_push(win, true);
  } else {
    s_window = win;
    window_stack_push(win, true);
  }
}

void refresh_notelist(void) {
  if (s_menu_layer) {
    menu_layer_reload_data(s_menu_layer);
  }
}

// ---- Fetching Screen ----
static TextLayer *s_fetching_label;

static void fetching_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_fetching_label = text_layer_create(GRect(0, 90, bounds.size.w, 30));
  text_layer_set_text(s_fetching_label, "Loading...");
  text_layer_set_font(s_fetching_label, fonts_get_system_font(FONT_KEY_GOTHIC_24));
  text_layer_set_text_alignment(s_fetching_label, GTextAlignmentCenter);
  layer_add_child(root, text_layer_get_layer(s_fetching_label));
}

static void fetching_window_unload(Window *window) {
  text_layer_destroy(s_fetching_label);
}

void window_fetching_push(void) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = fetching_window_load,
    .unload = fetching_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

// ---- Error Screen ----
static TextLayer *s_error_label;

static void error_window_load(Window *window) {
  Layer *root = window_get_root_layer(window);
  GRect bounds = layer_get_bounds(root);

  s_error_label = text_layer_create(GRect(10, 90, bounds.size.w - 20, 40));
  text_layer_set_text(s_error_label, s_error_message);
  text_layer_set_font(s_error_label, fonts_get_system_font(FONT_KEY_GOTHIC_18));
  text_layer_set_text_alignment(s_error_label, GTextAlignmentCenter);
  text_layer_set_overflow_mode(s_error_label, GTextOverflowModeWordWrap);
  layer_add_child(root, text_layer_get_layer(s_error_label));
}

static void error_window_unload(Window *window) {
  text_layer_destroy(s_error_label);
}

void window_error_push(const char *message) {
  Window *win = window_create();
  window_set_window_handlers(win, (WindowHandlers){
    .load = error_window_load,
    .unload = error_window_unload,
  });
  window_set_click_config_provider(win, click_config_provider);
  safe_window_push(win, true);
}

// ---- Connection Indicator ----
void set_connection_status(bool connected) {
  s_phone_connected = connected;
}

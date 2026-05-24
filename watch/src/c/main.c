#include <pebble.h>
#include "protocol.h"

typedef enum {
  STATE_IDLE,
  STATE_LISTENING,
  STATE_PROCESSING,
  STATE_SUMMARY_READY,
  STATE_NOTELIST,
  STATE_FETCHING,
  STATE_ERROR,
} AppState;

static AppState s_state = (AppState)0xFF;
uint32_t s_outgoing_msg_id = 0;
uint32_t s_last_incoming_msg_id = 0;
uint32_t s_session_id = 0;

char s_current_title[MAX_TITLE_LEN];
char s_current_body[MAX_BODY_LEN];
static uint32_t s_current_note_id = 0;
char s_error_message[64];

extern void dictation_init(void);
extern bool dictation_start(void);
extern void dictation_cancel(void);
extern bool dictation_is_in_progress(void);
extern const char *dictation_get_result(void);
extern DictationSessionStatus dictation_get_status(void);

extern void app_message_init(void);
extern bool app_message_send_dictation(uint32_t note_id, const char *text);
extern bool app_message_send_fetch_note(uint32_t note_id);
extern bool app_message_send_handshake(void);

extern void storage_init(void);
extern void storage_add_note(uint32_t note_id, const char *title);
extern void storage_cache_body(uint32_t note_id, const char *body);
extern bool storage_get_cached_body(uint32_t note_id, char *buf, size_t bufsize);
extern int storage_get_note_count(void);
extern bool storage_get_note_id(int index, uint32_t *note_id);
extern bool storage_get_title(uint32_t note_id, char *buf, size_t bufsize, uint32_t *timestamp);

extern void window_idle_push(void);
extern void window_listening_push(void);
extern void window_processing_push(void);
extern void window_summary_push(const char *title, const char *body);
extern void window_notelist_push(void);
extern void window_fetching_push(void);
extern void window_error_push(const char *message);
extern void update_processing_title(const char *title);
extern void refresh_notelist(void);
extern void set_connection_status(bool connected);

static void set_state(AppState new_state);

void select_click_handler(void *context, void *data) {
  switch (s_state) {
    case STATE_IDLE:
      if (dictation_start()) {
        set_state(STATE_LISTENING);
      }
      break;
    case STATE_SUMMARY_READY:
      set_state(STATE_IDLE);
      break;
    case STATE_ERROR:
      set_state(STATE_IDLE);
      break;
    case STATE_NOTELIST:;
      uint32_t note_id;
      if (storage_get_note_id(s_menu_index, &note_id)) {
        s_current_note_id = note_id;
        if (storage_get_cached_body(note_id, s_current_body, sizeof(s_current_body))) {
          storage_get_title(note_id, s_current_title, sizeof(s_current_title), NULL);
          set_state(STATE_SUMMARY_READY);
        } else {
          set_state(STATE_FETCHING);
          app_message_send_fetch_note(note_id);
        }
      }
      break;
    default:
      break;
  }
}

static void back_click_handler(void *context, void *data) {
  switch (s_state) {
    case STATE_LISTENING:
      dictation_cancel();
      set_state(STATE_IDLE);
      break;
    case STATE_PROCESSING:
    case STATE_SUMMARY_READY:
      set_state(STATE_IDLE);
      break;
    case STATE_NOTELIST:
    case STATE_FETCHING:
      set_state(STATE_IDLE);
      break;
    case STATE_ERROR:
      set_state(STATE_IDLE);
      break;
    default:
      break;
  }
}

static void up_click_handler(void *context, void *data) {
}

static void down_click_handler(void *context, void *data) {
}

void click_config_provider(void *context) {
  window_single_click_subscribe(BUTTON_ID_SELECT, select_click_handler);
  window_single_click_subscribe(BUTTON_ID_UP, up_click_handler);
  window_single_click_subscribe(BUTTON_ID_DOWN, down_click_handler);
  window_single_click_subscribe(BUTTON_ID_BACK, back_click_handler);
}

void handle_dictation_result(void *data) {
  DictationSessionStatus status = dictation_get_status();
  if (status == DictationSessionStatusSuccess) {
    const char *text = dictation_get_result();
    if (text && strlen(text) > 0) {
      s_current_note_id = (uint32_t)time(NULL);
      app_message_send_dictation(s_current_note_id, text);
      set_state(STATE_PROCESSING);
    } else {
      set_state(STATE_IDLE);
    }
  } else {
    snprintf(s_error_message, sizeof(s_error_message), "Dictation failed");
    set_state(STATE_ERROR);
  }
}

void handle_incoming_data(uint8_t command, DictionaryIterator *iter) {
  Tuple *tuple;

  switch (command) {
    case CMD_TITLE:
      tuple = dict_find(iter, KEY_TITLE);
      if (tuple) {
        strncpy(s_current_title, tuple->value->cstring, sizeof(s_current_title) - 1);
        if (s_state == STATE_PROCESSING) {
          update_processing_title(s_current_title);
        }
      }
      break;

    case CMD_CHUNK: {
      static uint8_t reassembly_buf[MAX_TOTAL_BODY];
      static int chunk_index, chunk_total, accumulated;
      static bool reassembly_active = false;

      Tuple *idx = dict_find(iter, KEY_CHUNK_INDEX);
      Tuple *total = dict_find(iter, KEY_CHUNK_TOTAL);
      Tuple *data = dict_find(iter, KEY_SUMMARY_CHUNK);

      if (!idx || !data) break;

      if (!reassembly_active) {
        if (!total) break;
        chunk_total = total->value->int32;
        chunk_index = 0;
        accumulated = 0;
        reassembly_active = true;
      }

      if (idx->value->int32 != chunk_index++) break;
      int datalen = data->length;
      if (accumulated + datalen > MAX_TOTAL_BODY) break;
      memcpy(reassembly_buf + accumulated, data->value->data, datalen);
      accumulated += datalen;

      tuple = dict_find(iter, KEY_COMPLETE);
      if (tuple || (total && chunk_index >= chunk_total)) {
        reassembly_active = false;
        reassembly_buf[accumulated] = '\0';
        strncpy(s_current_body, (char *)reassembly_buf, sizeof(s_current_body) - 1);
        storage_cache_body(s_current_note_id, s_current_body);
        set_state(STATE_SUMMARY_READY);
      }
      break;
    }

    case CMD_NOTE_RESPONSE:
      tuple = dict_find(iter, KEY_TITLE);
      if (tuple) strncpy(s_current_title, tuple->value->cstring, sizeof(s_current_title) - 1);
      tuple = dict_find(iter, KEY_BODY);
      if (tuple) {
        strncpy(s_current_body, tuple->value->cstring, sizeof(s_current_body) - 1);
        storage_cache_body(s_current_note_id, s_current_body);
      }
      set_state(STATE_SUMMARY_READY);
      break;

    case CMD_RESET:
      set_state(STATE_IDLE);
      break;

    case CMD_HANDSHAKE_ACK:
      tuple = dict_find(iter, KEY_SESSION_ID);
      if (tuple) {
        s_session_id = tuple->value->int32;
      }
      break;
  }
}

static void set_state(AppState new_state) {
  if (s_state == new_state && new_state != STATE_ERROR) return;
  s_state = new_state;

  switch (new_state) {
    case STATE_IDLE:
      window_idle_push();
      break;
    case STATE_LISTENING:
      window_listening_push();
      break;
    case STATE_PROCESSING:
      window_processing_push();
      break;
    case STATE_SUMMARY_READY:
      storage_add_note(s_current_note_id, s_current_title);
      vibes_double_pulse();
      window_summary_push(s_current_title, s_current_body);
      break;
    case STATE_NOTELIST:
      s_menu_index = 0;
      window_notelist_push();
      break;
    case STATE_FETCHING:
      window_fetching_push();
      break;
    case STATE_ERROR:
      window_error_push(s_error_message);
      break;
  }
}

static void init(void) {
  s_session_id = (uint32_t)time(NULL);
  s_current_title[0] = '\0';
  s_current_body[0] = '\0';
  s_error_message[0] = '\0';

  storage_init();
  dictation_init();
  app_message_init();
  app_message_send_handshake();

  set_state(STATE_IDLE);
}

static void deinit(void) {
  dictation_cancel();
}

int main(void) {
  init();
  app_event_loop();
  deinit();
}

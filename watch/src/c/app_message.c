#include <pebble.h>
#include "protocol.h"

extern void handle_incoming_data(uint8_t command, DictionaryIterator *iter);
extern uint32_t s_outgoing_msg_id;
extern uint32_t s_last_incoming_msg_id;
extern uint32_t s_session_id;

static void inbox_received_callback(DictionaryIterator *iter, void *context) {
  Tuple *cmd = dict_find(iter, KEY_COMMAND);
  Tuple *msg_id = dict_find(iter, KEY_MSG_ID);
  Tuple *session_id = dict_find(iter, KEY_SESSION_ID);

  if (!cmd) return;

  if (msg_id) {
    uint32_t mid = msg_id->value->uint32;
    if (session_id) {
      uint32_t sid = session_id->value->uint32;
      if (sid == s_session_id && mid <= s_last_incoming_msg_id) {
        return;
      }
      if (sid != s_session_id) {
        s_session_id = sid;
        s_last_incoming_msg_id = 0;
      }
    }
    s_last_incoming_msg_id = mid;
  }

  handle_incoming_data(cmd->value->uint8, iter);
}

static void outbox_sent_callback(DictionaryIterator *iter, void *context) {
}

static void outbox_failed_callback(DictionaryIterator *iter, AppMessageResult reason, void *context) {
  APP_LOG(APP_LOG_LEVEL_DEBUG, "AppMessage send failed: %d", reason);
}

void app_message_init(void) {
  app_message_register_inbox_received(inbox_received_callback);
  app_message_register_outbox_sent(outbox_sent_callback);
  app_message_register_outbox_failed(outbox_failed_callback);
  app_message_open(4096, 2048);
}

static void add_common_keys(DictionaryIterator *iter) {
  dict_write_uint32(iter, KEY_MSG_ID, s_outgoing_msg_id++);
  dict_write_uint32(iter, KEY_SESSION_ID, s_session_id);
}

bool app_message_send_dictation(uint32_t note_id, const char *text) {
  DictionaryIterator *iter;
  AppMessageResult result = app_message_outbox_begin(&iter);
  if (result != APP_MSG_OK) return false;

  dict_write_uint8(iter, KEY_COMMAND, CMD_DICTATION_RESULT);
  add_common_keys(iter);
  dict_write_uint32(iter, KEY_NOTE_ID, note_id);
  dict_write_cstring(iter, KEY_RAW_TEXT, text);

  result = app_message_outbox_send();
  return result == APP_MSG_OK;
}

bool app_message_send_fetch_note(uint32_t note_id) {
  DictionaryIterator *iter;
  AppMessageResult result = app_message_outbox_begin(&iter);
  if (result != APP_MSG_OK) return false;

  dict_write_uint8(iter, KEY_COMMAND, CMD_FETCH_NOTE);
  add_common_keys(iter);
  dict_write_uint32(iter, KEY_NOTE_ID, note_id);

  result = app_message_outbox_send();
  return result == APP_MSG_OK;
}

bool app_message_send_handshake(void) {
  DictionaryIterator *iter;
  AppMessageResult result = app_message_outbox_begin(&iter);
  if (result != APP_MSG_OK) return false;

  dict_write_uint8(iter, KEY_COMMAND, CMD_HANDSHAKE);
  add_common_keys(iter);
  dict_write_uint32(iter, KEY_LAST_INCOMING_MSG_ID, s_last_incoming_msg_id);

  result = app_message_outbox_send();
  return result == APP_MSG_OK;
}

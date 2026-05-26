#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <stdint.h>

#define APP_UUID_STR "E2ECDBEB-2D2B-412F-AD1D-9059180EBC47"

// AppMessage key indices — must match package.json messageKeys order
typedef enum {
  KEY_MSG_ID = 10000,
  KEY_COMMAND = 10001,
  KEY_RAW_TEXT = 10002,
  KEY_NOTE_ID = 10003,
  KEY_SUMMARY_CHUNK = 10004,
  KEY_CHUNK_INDEX = 10005,
  KEY_CHUNK_TOTAL = 10006,
  KEY_CHUNK_RESET = 10007,
  KEY_TITLE = 10008,
  KEY_BODY = 10009,
  KEY_COMPLETE = 10010,
  KEY_FETCH_NOTE = 10011,
  KEY_SESSION_ID = 10012,
  KEY_LAST_INCOMING_MSG_ID = 10013,
} AppMessageKey;

// Commands: Watch -> Phone
typedef enum {
  CMD_HANDSHAKE = 0,
  CMD_DICTATION_RESULT = 1,
  CMD_FETCH_NOTE = 2,
} WatchCommand;

// Commands: Phone -> Watch
typedef enum {
  CMD_HANDSHAKE_ACK = 0,
  CMD_TITLE = 10,
  CMD_CHUNK = 11,
  CMD_COMPLETE = 12,
  CMD_RESET = 13,
  CMD_NOTE_RESPONSE = 14,
} PhoneCommand;

#define MAX_CHUNK_SIZE 2048
#define MAX_TOTAL_BODY 8192
#define CHUNK_TIMEOUT_MS 10000
#define MAX_TITLE_LEN 128
#define MAX_BODY_LEN 4096
#define MAX_NOTES 50

extern int s_menu_index;
extern Window *s_window;
extern uint32_t s_outgoing_msg_id;
extern uint32_t s_last_incoming_msg_id;
extern uint32_t s_session_id;
extern char s_current_title[];
extern char s_current_body[];
extern char s_error_message[];
extern void click_config_provider(void *context);
extern void select_click_handler(void *context, void *data);
extern void force_state_idle(void);
extern bool is_current_state_notelist(void);
extern void back_click_handler(void *context, void *data);

#endif

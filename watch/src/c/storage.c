#include <pebble.h>
#include "protocol.h"

#define STORAGE_KEY_INDEX_COUNT 0x10
#define STORAGE_KEY_INDEX_IDS   0x11
#define STORAGE_KEY_CACHED_BODY_ID 0x12
#define STORAGE_KEY_META_BASE 0x100
#define STORAGE_KEY_BODY_BASE 0x1000

static int s_note_count = 0;
static uint32_t s_note_ids[MAX_NOTES];

typedef struct {
  uint32_t note_id;
  char title[MAX_TITLE_LEN];
  uint32_t timestamp;
  uint8_t flags;
} __attribute__((packed)) NoteMeta;

void storage_init(void) {
  int bytes_read = persist_read_data(STORAGE_KEY_INDEX_COUNT, &s_note_count, sizeof(s_note_count));
  if (bytes_read == sizeof(s_note_count) && s_note_count > 0 && s_note_count <= MAX_NOTES) {
    int ids_size = s_note_count * sizeof(uint32_t);
    int total = persist_read_data(STORAGE_KEY_INDEX_IDS, s_note_ids, ids_size);
    if (total != ids_size) {
      s_note_count = 0;
    }
  } else {
    s_note_count = 0;
  }
}

void storage_add_note(uint32_t note_id, const char *title) {
  int existing = -1;
  for (int i = 0; i < s_note_count; i++) {
    if (s_note_ids[i] == note_id) {
      existing = i;
      break;
    }
  }

  NoteMeta meta = {
    .note_id = note_id,
    .timestamp = (uint32_t)time(NULL),
    .flags = 0,
  };
  strncpy(meta.title, title ? title : "Untitled", sizeof(meta.title) - 1);
  persist_write_data(STORAGE_KEY_META_BASE + note_id, &meta, sizeof(meta));

  if (existing >= 0) {
    memmove(&s_note_ids[1], &s_note_ids[0], existing * sizeof(uint32_t));
    s_note_ids[0] = note_id;
  } else {
    if (s_note_count < MAX_NOTES) s_note_count++;
    memmove(&s_note_ids[1], &s_note_ids[0], (s_note_count - 1) * sizeof(uint32_t));
    s_note_ids[0] = note_id;
  }

  persist_write_data(STORAGE_KEY_INDEX_COUNT, &s_note_count, sizeof(s_note_count));
  persist_write_data(STORAGE_KEY_INDEX_IDS, s_note_ids, s_note_count * sizeof(uint32_t));
}

void storage_cache_body(uint32_t note_id, const char *body) {
  uint32_t old_cached_id = 0;
  if (persist_exists(STORAGE_KEY_CACHED_BODY_ID)) {
    persist_read_data(STORAGE_KEY_CACHED_BODY_ID, &old_cached_id, sizeof(old_cached_id));
  }

  if (old_cached_id != 0 && old_cached_id != note_id) {
    persist_delete(STORAGE_KEY_BODY_BASE + old_cached_id);
  }

  size_t len = strlen(body) + 1;
  persist_write_data(STORAGE_KEY_BODY_BASE + note_id, body, len);
  persist_write_data(STORAGE_KEY_CACHED_BODY_ID, &note_id, sizeof(note_id));
}

bool storage_get_cached_body(uint32_t note_id, char *buf, size_t bufsize) {
  int bytes = persist_read_data(STORAGE_KEY_BODY_BASE + note_id, buf, bufsize);
  if (bytes > 0) {
    buf[bytes < (int)bufsize ? (size_t)bytes : bufsize - 1u] = '\0';
    return true;
  }
  return false;
}

bool storage_get_note_id(int index, uint32_t *note_id) {
  if (index < 0 || index >= s_note_count) return false;
  *note_id = s_note_ids[index];
  return true;
}

bool storage_get_title(uint32_t note_id, char *buf, size_t bufsize, uint32_t *timestamp) {
  NoteMeta meta;
  int bytes = persist_read_data(STORAGE_KEY_META_BASE + note_id, &meta, sizeof(meta));
  if (bytes == sizeof(meta)) {
    strncpy(buf, meta.title, bufsize - 1);
    buf[bufsize - 1] = '\0';
    if (timestamp) *timestamp = meta.timestamp;
    return true;
  }
  return false;
}

int storage_get_note_count(void) {
  return s_note_count;
}

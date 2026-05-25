#include <pebble.h>

static DictationSession *s_session = NULL;
static char s_transcription[2048];
static bool s_in_progress = false;
static DictationSessionStatus s_last_status;

extern void handle_dictation_result(void *data);

static void dictation_callback(DictationSession *session, DictationSessionStatus status,
                                char *transcription, void *context) {
  s_in_progress = false;
  s_last_status = status;

  if (status == DictationSessionStatusSuccess && transcription) {
    strncpy(s_transcription, transcription, sizeof(s_transcription) - 1);
    s_transcription[sizeof(s_transcription) - 1] = '\0';
  } else {
    s_transcription[0] = '\0';
  }

  app_timer_register(200, handle_dictation_result, NULL);
}

bool dictation_init(void) {
  if (s_session) return true;

  s_session = dictation_session_create(sizeof(s_transcription), dictation_callback, NULL);
  if (!s_session) return false;

  dictation_session_enable_confirmation(s_session, false);
  dictation_session_enable_error_dialogs(s_session, false);
  return true;
}

bool dictation_start(void) {
  if (!s_session || s_in_progress) {
    return false;
  }

  s_in_progress = true;
  s_transcription[0] = '\0';
  s_last_status = (DictationSessionStatus)-1;

  DictationSessionStatus result = dictation_session_start(s_session);
  if (result != DictationSessionStatusSuccess) {
    s_in_progress = false;
    return false;
  }
  return true;
}

void dictation_cancel(void) {
  if (s_session && s_in_progress) {
    dictation_session_stop(s_session);
    s_in_progress = false;
  }
}

bool dictation_is_in_progress(void) {
  return s_in_progress;
}

const char *dictation_get_result(void) {
  return (s_last_status == DictationSessionStatusSuccess && s_transcription[0])
         ? s_transcription : NULL;
}

DictationSessionStatus dictation_get_status(void) {
  return s_last_status;
}

void dictation_deinit(void) {
  if (s_session) {
    dictation_session_destroy(s_session);
    s_session = NULL;
  }
}

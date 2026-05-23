#include <pebble.h>
#include "xsmc.h"
#include "xsHost.h"

// Helper to duplicate strings in Pebble's memory environment
static char *my_strdup(const char *s) {
  if (!s) return NULL;
  size_t len = strlen(s) + 1;
  char *dup = malloc(len);
  if (dup) {
    memcpy(dup, s, len);
  }
  return dup;
}

// ============================================================================
// Haptic / Vibes Bindings
// ============================================================================

void xs_vibes_short_pulse(xsMachine *the) {
  vibes_short_pulse();
}

void xs_vibes_long_pulse(xsMachine *the) {
  vibes_long_pulse();
}

void xs_vibes_double_pulse(xsMachine *the) {
  vibes_double_pulse();
}

void xs_vibes_cancel(xsMachine *the) {
  vibes_cancel();
}

void xs_vibes_pattern(xsMachine *the) {
  xsSlot tmp;
  xsmcGet(tmp, xsArg(0), xsID("length"));
  int count = xsmcToInteger(tmp);
  if (count <= 0) return;
  
  uint32_t *durations = malloc(count * sizeof(uint32_t));
  if (!durations) xsUnknownError("no memory");
  
  for (int i = 0; i < count; i++) {
    xsmcGetIndex(xsVar(0), xsArg(0), i);
    durations[i] = xsmcToInteger(xsVar(0));
  }
  
  VibePattern pattern = {
    .durations = durations,
    .num_segments = count,
  };
  vibes_enqueue_custom_pattern(pattern);
  free(durations);
}

// ============================================================================
// Voice Dictation Bindings
// ============================================================================

struct PebbleDictationRecord {
  xsMachine *the;
  xsSlot obj;
  xsSlot *onReadable;
  xsSlot *onError;
  DictationSession *session;
  char *transcription;
};
typedef struct PebbleDictationRecord PebbleDictationRecord;
typedef struct PebbleDictationRecord *PebbleDictation;

static void dictationStatusCallback(DictationSession *session,
                                    DictationSessionStatus status,
                                    char *transcription,
                                    void *context) {
  PebbleDictation pd = context;
  if (!pd) return;

  xsBeginHost(pd->the);
  if (status == DictationSessionStatusSuccess) {
    if (pd->transcription) {
      free(pd->transcription);
      pd->transcription = NULL;
    }
    if (transcription) {
      pd->transcription = my_strdup(transcription);
    }
    xsCallFunction0(xsReference(pd->onReadable), pd->obj);
  } else {
    xsmcVars(1);
    xsmcSetInteger(xsVar(0), (xsIntegerValue)status);
    xsCallFunction1(xsReference(pd->onError), pd->obj, xsVar(0));
  }
  xsEndHost(pd->the);
}

void xs_dictation_destructor(void *data) {
  PebbleDictation pd = data;
  if (!pd) return;
  if (pd->session) {
    dictation_session_destroy(pd->session);
  }
  if (pd->transcription) {
    free(pd->transcription);
  }
  free(pd);
}

static void xs_dictation_mark(xsMachine* the, void* it, xsMarkRoot markRoot) {
  PebbleDictation pd = it;
  if (pd->onReadable) (*markRoot)(the, pd->onReadable);
  if (pd->onError) (*markRoot)(the, pd->onError);
}

static const xsHostHooks xsDictationHooks = {
  xs_dictation_destructor,
  xs_dictation_mark,
  NULL
};

void xs_dictation_create(xsMachine *the) {
  xsmcVars(2);
  
  if (!xsmcHas(xsArg(0), xsID("onReadable")))
    xsUnknownError("onReadable required");
  xsmcGet(xsVar(0), xsArg(0), xsID("onReadable"));
  
  if (!xsmcHas(xsArg(0), xsID("onError")))
    xsUnknownError("onError required");
  xsmcGet(xsVar(1), xsArg(0), xsID("onError"));
  
  PebbleDictation pd = calloc(1, sizeof(PebbleDictationRecord));
  if (!pd) xsUnknownError("no memory");
  
  xsmcSetHostData(xsThis, pd);
  xsSetHostHooks(xsThis, (xsHostHooks *)&xsDictationHooks);
  
  pd->the = the;
  pd->obj = xsThis;
  xsRemember(pd->obj);
  pd->onReadable = xsmcToReference(xsVar(0));
  pd->onError = xsmcToReference(xsVar(1));
  
  pd->session = dictation_session_create(512, dictationStatusCallback, pd);
  if (!pd->session) {
    xsUnknownError("failed to create dictation session");
  }
}

void xs_dictation_start(xsMachine *the) {
  PebbleDictation pd = xsmcGetHostDataValidate(xsThis, (void *)&xsDictationHooks);
  if (pd && pd->session) {
    DictationSessionStatus status = dictation_session_start(pd->session);
    xsmcSetInteger(xsResult, (xsIntegerValue)status);
  } else {
    xsmcSetInteger(xsResult, (xsIntegerValue)DictationSessionStatusFailureInternalError);
  }
}

void xs_dictation_stop(xsMachine *the) {
  PebbleDictation pd = xsmcGetHostDataValidate(xsThis, (void *)&xsDictationHooks);
  if (pd && pd->session) {
    DictationSessionStatus status = dictation_session_stop(pd->session);
    xsmcSetInteger(xsResult, (xsIntegerValue)status);
  } else {
    xsmcSetInteger(xsResult, (xsIntegerValue)DictationSessionStatusFailureInternalError);
  }
}

void xs_dictation_read(xsMachine *the) {
  PebbleDictation pd = xsmcGetHostDataValidate(xsThis, (void *)&xsDictationHooks);
  if (pd && pd->transcription) {
    xsmcSetString(xsResult, pd->transcription);
  } else {
    xsmcSetNull(xsResult);
  }
}

void xs_dictation_close(xsMachine *the) {
  PebbleDictation pd = xsmcGetHostDataValidate(xsThis, (void *)&xsDictationHooks);
  xsForget(pd->obj);
  xs_dictation_destructor(pd);
  xsmcSetHostData(xsThis, NULL);
  xsmcSetHostDestructor(xsThis, NULL);
}

// ============================================================================
// Main Application Lifecycle
// ============================================================================

int main(void) {
  Window *w = window_create();
  window_stack_push(w, true);

  // Configure Moddable XS VM memory allocations to prevent heap crashes
  ModdableCreationRecord record = {
    .recordSize = sizeof(ModdableCreationRecord),
    .stack = 0,       // Use default stack size
    .slot = 8192,     // 8KB slot heap size
    .chunk = 32768,   // 32KB chunk heap size (for loading custom modules)
    .flags = 0
  };

  moddable_createMachine(&record);

  window_destroy(w);
}

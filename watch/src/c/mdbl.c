#include <pebble.h>

int main(void) {
  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: main() entered");

  Window *w = window_create();
  window_stack_push(w, true);
  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: window created and pushed");

  ModdableCreationRecord record = {
    .recordSize = sizeof(ModdableCreationRecord),
    .slot = 65536,
    .chunk = 16384,
    .stack = 4096,
    .flags = 0
  };
  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: moddable_createMachine(slot=%lu chunk=%lu stack=%u)",
          (unsigned long)record.slot, (unsigned long)record.chunk, record.stack);
  moddable_createMachine(&record);
  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: moddable_createMachine returned");

  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: entering event loop");
  app_event_loop();
  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: event loop exited");

  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: destroying window");
  window_destroy(w);

  APP_LOG(APP_LOG_LEVEL_DEBUG, "MDBL: main() exiting");
}
#include <pebble.h>

int main(void) {
  Window *w = window_create();
  window_stack_push(w, true);

  // Enable XS instrumentation to log memory usage stats for debugging.
  // Remove or set flags to 0 once the app is stable.
  ModdableCreationRecord record = {
    .recordSize = sizeof(ModdableCreationRecord),
    .flags = kModdableCreationFlagLogInstrumentation
  };
  moddable_createMachine(&record);

  window_destroy(w);
}

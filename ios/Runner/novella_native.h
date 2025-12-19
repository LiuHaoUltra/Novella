#ifndef novella_native_h
#define novella_native_h

#include <stdint.h>

// Dummy function to force the linker to include Rust symbols on iOS.
// This must be called from AppDelegate to prevent symbol stripping.
int32_t dummy_method_to_enforce_bundling(void);

#endif /* novella_native_h */

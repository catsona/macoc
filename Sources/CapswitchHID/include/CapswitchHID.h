#ifndef CAPSWITCH_HID_H
#define CAPSWITCH_HID_H

#include <stdbool.h>
#include <stdint.h>

// Caps Lock lock-state APIs return KERN_SUCCESS (0) or a Mach/IOKit code.
int32_t CapswitchReadCapsLock(bool *enabled);
int32_t CapswitchWriteCapsLock(bool enabled);

// Sets only the physical Caps Lock LED on keyboards exposing an output LED
// element. Does not change modifier state. Blocking; call off the event tap.
// Returns an IOKit error if any supported device fails; updatedCount counts
// successfully written elements, including when another keyboard fails.
int32_t CapswitchWriteCapsLED(bool enabled, uint32_t *updatedCount);

// Remaps HID usage 0x700000039 (physical Caps Lock) to 0x70000006E (F19).
// Uses IOHIDEventSystemClient directly in the current process. Does not
// launch hidutil or require root, a privileged helper or a virtual driver.
//
// The opaque manager remembers the registry IDs of keyboard services modified
// by Capswitch; other service mappings are preserved on apply and restoration.
// IDs are persisted in the application's CFPreferences for crash recovery.
typedef void *CapswitchRemapperRef;

typedef enum {
    CapswitchRemapOK = 0,
    CapswitchRemapOutOfMemory = 1,
    CapswitchRemapClientUnavailable = 2,
    CapswitchRemapNoKeyboards = 3,
    CapswitchRemapInvalidExistingMappings = 4,
    CapswitchRemapConflict = 5,
    CapswitchRemapSetFailed = 6,
    CapswitchRemapVerificationFailed = 7,
    CapswitchRemapMissingRegistryID = 8,
    CapswitchRemapPersistenceFailed = 9
} CapswitchRemapResult;

CapswitchRemapperRef CapswitchRemapperCreate(void);
void CapswitchRemapperDestroy(CapswitchRemapperRef manager);

// A return of CapswitchRemapOK means every connected keyboard service has the
// Caps->F19 pair; keyboardCount must also be greater than zero.
int32_t CapswitchRemapperApply(
    CapswitchRemapperRef manager,
    uint32_t *keyboardCount,
    uint32_t *mappedCount
);

// Remove our exact Caps->F19 pair from services that Capswitch itself changed.
// Re-read each service before altering it to preserve other remappers' changes.
int32_t CapswitchRemapperRestore(CapswitchRemapperRef manager);

// Read-only diagnostics. No HID mappings are changed.
int32_t CapswitchRemapperInspect(
    CapswitchRemapperRef manager,
    uint32_t *keyboardCount,
    uint32_t *mappedCount
);

#endif

#ifndef CAPSWITCH_HID_H
#define CAPSWITCH_HID_H

#include <stdbool.h>
#include <stdint.h>

// Returns KERN_SUCCESS (0) or an IOKit/Mach error code.
int32_t CapswitchReadCapsLock(bool *enabled);
int32_t CapswitchWriteCapsLock(bool enabled);

#endif

#include "CapswitchHID.h"

#include <IOKit/IOKitLib.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDParameter.h>
#include <mach/mach.h>

static kern_return_t OpenHIDSystem(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching(kIOHIDSystemClass)
    );
    if (service == IO_OBJECT_NULL) {
        return KERN_FAILURE;
    }

    kern_return_t result = IOServiceOpen(
        service,
        mach_task_self(),
        kIOHIDParamConnectType,
        connection
    );
    IOObjectRelease(service);
    return result;
}

int32_t CapswitchReadCapsLock(bool *enabled) {
    if (enabled == NULL) {
        return KERN_INVALID_ARGUMENT;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = OpenHIDSystem(&connection);
    if (result != KERN_SUCCESS) {
        return result;
    }

    result = IOHIDGetModifierLockState(
        connection,
        kIOHIDCapsLockState,
        enabled
    );
    IOServiceClose(connection);
    return result;
}

int32_t CapswitchWriteCapsLock(bool enabled) {
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = OpenHIDSystem(&connection);
    if (result != KERN_SUCCESS) {
        return result;
    }

    result = IOHIDSetModifierLockState(
        connection,
        kIOHIDCapsLockState,
        enabled
    );
    IOServiceClose(connection);
    return result;
}

#include "CapswitchHID.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDUsageTables.h>

typedef struct {
    bool enabled;
    uint32_t count;
    IOReturn error;
} LEDUpdate;

static void SetKeyboardLED(const void *value, void *context) {
    IOHIDDeviceRef device = (IOHIDDeviceRef)value;
    LEDUpdate *update = context;
    CFArrayRef elements = IOHIDDeviceCopyMatchingElements(
        device, NULL, kIOHIDOptionsTypeNone
    );
    if (elements == NULL) {
        return;
    }

    bool opened = false;
    for (CFIndex i = 0; i < CFArrayGetCount(elements); ++i) {
        IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elements, i);
        if (IOHIDElementGetUsagePage(element) != kHIDPage_LEDs
            || IOHIDElementGetUsage(element) != kHIDUsage_LED_CapsLock
            || IOHIDElementGetType(element) != kIOHIDElementTypeOutput) {
            continue;
        }

        if (!opened) {
            IOReturn result = IOHIDDeviceOpen(device, kIOHIDOptionsTypeNone);
            if (result != kIOReturnSuccess) {
                update->error = result;
                break;
            }
            opened = true;
        }

        IOHIDValueRef ledValue = IOHIDValueCreateWithIntegerValue(
            kCFAllocatorDefault, element, 0, update->enabled ? 1 : 0
        );
        IOReturn result = ledValue == NULL ? kIOReturnNoMemory
            : IOHIDDeviceSetValue(device, element, ledValue);
        if (ledValue != NULL) {
            CFRelease(ledValue);
        }
        if (result == kIOReturnSuccess) {
            update->count += 1;
        } else {
            update->error = result;
        }
    }

    if (opened) {
        IOHIDDeviceClose(device, kIOHIDOptionsTypeNone);
    }
    CFRelease(elements);
}

int32_t CapswitchWriteCapsLED(bool enabled, uint32_t *updatedCount) {
    if (updatedCount == NULL) {
        return kIOReturnBadArgument;
    }
    *updatedCount = 0;

    IOHIDManagerRef manager = IOHIDManagerCreate(
        kCFAllocatorDefault, kIOHIDOptionsTypeNone
    );
    int page = kHIDPage_GenericDesktop;
    int usage = kHIDUsage_GD_Keyboard;
    CFNumberRef pageValue = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usageValue = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    if (manager == NULL || pageValue == NULL || usageValue == NULL) {
        if (manager != NULL) CFRelease(manager);
        if (pageValue != NULL) CFRelease(pageValue);
        if (usageValue != NULL) CFRelease(usageValue);
        return kIOReturnNoMemory;
    }

    const void *keys[] = { CFSTR(kIOHIDDeviceUsagePageKey), CFSTR(kIOHIDDeviceUsageKey) };
    const void *values[] = { pageValue, usageValue };
    CFDictionaryRef matching = CFDictionaryCreate(
        NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(pageValue);
    CFRelease(usageValue);
    if (matching == NULL) {
        CFRelease(manager);
        return kIOReturnNoMemory;
    }

    // Enumerate afresh so hot-plugged keyboards and wake need no cached handles.
    // Open devices individually: one inaccessible keyboard must not block others.
    IOHIDManagerSetDeviceMatching(manager, matching);
    CFRelease(matching);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    LEDUpdate update = { .enabled = enabled, .count = 0, .error = kIOReturnSuccess };
    if (devices != NULL) {
        CFSetApplyFunction(devices, SetKeyboardLED, &update);
        CFRelease(devices);
    }
    CFRelease(manager);
    *updatedCount = update.count;
    return update.error;
}

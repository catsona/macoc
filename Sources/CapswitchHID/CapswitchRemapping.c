#include "CapswitchHID.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>
#include <stdlib.h>

#define CAPSWITCH_CAPS_USAGE UINT64_C(0x700000039)
#define CAPSWITCH_F19_USAGE  UINT64_C(0x70000006E)

// These exact property names are documented in Apple Technical Note TN2450.
#define SOURCE_KEY CFSTR("HIDKeyboardModifierMappingSrc")
#define DEST_KEY   CFSTR("HIDKeyboardModifierMappingDst")
#define MAPPING_KEY CFSTR("UserKeyMapping")
#define OWNED_SERVICES_KEY CFSTR("CapswitchOwnedKeyboardServiceIDs")

typedef struct {
    CFMutableSetRef ownedServices;
} CapswitchRemapper;

static bool PersistOwnedServices(CapswitchRemapper *manager) {
    CFIndex count = CFSetGetCount(manager->ownedServices);
    const void **ids = count > 0 ? calloc((size_t)count, sizeof(void *)) : NULL;

    if (count > 0 && ids == NULL) {
        return false;
    }

    if (count > 0) {
        CFSetGetValues(manager->ownedServices, ids);
    }

    CFArrayRef array = CFArrayCreate(
        kCFAllocatorDefault, ids, count, &kCFTypeArrayCallBacks
    );
    free(ids);

    if (array == NULL) {
        return false;
    }

    CFPreferencesSetAppValue(
        OWNED_SERVICES_KEY, array, kCFPreferencesCurrentApplication
    );
    bool persisted = CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
    CFRelease(array);
    return persisted;
}

CapswitchRemapperRef CapswitchRemapperCreate(void) {
    CapswitchRemapper *manager = calloc(1, sizeof(*manager));
    if (manager == NULL) {
        return NULL;
    }

    manager->ownedServices = CFSetCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeSetCallBacks
    );
    if (manager->ownedServices == NULL) {
        free(manager);
        return NULL;
    }

    CFTypeRef saved = CFPreferencesCopyAppValue(
        OWNED_SERVICES_KEY, kCFPreferencesCurrentApplication
    );
    if (saved != NULL && CFGetTypeID(saved) == CFArrayGetTypeID()) {
        CFArrayRef ids = (CFArrayRef)saved;
        for (CFIndex i = 0; i < CFArrayGetCount(ids); i++) {
            CFTypeRef id = CFArrayGetValueAtIndex(ids, i);
            if (CFGetTypeID(id) == CFNumberGetTypeID()) {
                CFSetAddValue(manager->ownedServices, id);
            }
        }
    }
    if (saved != NULL) {
        CFRelease(saved);
    }

    return manager;
}

void CapswitchRemapperDestroy(CapswitchRemapperRef reference) {
    CapswitchRemapper *manager = (CapswitchRemapper *)reference;
    if (manager == NULL) {
        return;
    }
    if (manager->ownedServices != NULL) {
        CFRelease(manager->ownedServices);
    }
    free(manager);
}

static bool KeyboardService(IOHIDServiceClientRef service) {
    return IOHIDServiceClientConformsTo(
        service, kHIDPage_GenericDesktop, kHIDUsage_GD_Keyboard
    ) != 0;
}

static CFNumberRef ServiceID(IOHIDServiceClientRef service) {
    CFTypeRef id = IOHIDServiceClientGetRegistryID(service);
    if (id == NULL || CFGetTypeID(id) != CFNumberGetTypeID()) {
        return NULL;
    }
    return (CFNumberRef)id; // Get: borrowed, not released by the caller.
}

static CFArrayRef CopyMappings(IOHIDServiceClientRef service) {
    CFTypeRef property = IOHIDServiceClientCopyProperty(service, MAPPING_KEY);

    if (property == NULL) {
        // A missing UserKeyMapping property means there are no active pairs.
        return CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
    }

    if (CFGetTypeID(property) != CFArrayGetTypeID()) {
        CFRelease(property);
        return NULL;
    }
    return (CFArrayRef)property;
}

static bool ReadPair(
    CFTypeRef object, uint64_t *source, uint64_t *destination
) {
    if (CFGetTypeID(object) != CFDictionaryGetTypeID()) {
        return false;
    }

    CFDictionaryRef mapping = (CFDictionaryRef)object;
    CFTypeRef src = CFDictionaryGetValue(mapping, SOURCE_KEY);
    CFTypeRef dst = CFDictionaryGetValue(mapping, DEST_KEY);

    if (src == NULL || dst == NULL
        || CFGetTypeID(src) != CFNumberGetTypeID()
        || CFGetTypeID(dst) != CFNumberGetTypeID()) {
        return false;
    }

    int64_t signedSource = 0;
    int64_t signedDestination = 0;
    if (!CFNumberGetValue((CFNumberRef)src, kCFNumberSInt64Type, &signedSource)
        || !CFNumberGetValue((CFNumberRef)dst, kCFNumberSInt64Type, &signedDestination)
        || signedSource < 0 || signedDestination < 0) {
        return false;
    }

    *source = (uint64_t)signedSource;
    *destination = (uint64_t)signedDestination;
    return true;
}

// -1: malformed; 0: not mapped; 1: Caps->F19 already mapped; 2: conflict.
static int MappingState(CFArrayRef mappings) {
    bool found = false;

    for (CFIndex i = 0; i < CFArrayGetCount(mappings); i++) {
        uint64_t source = 0;
        uint64_t destination = 0;
        if (!ReadPair(CFArrayGetValueAtIndex(mappings, i), &source, &destination)) {
            return -1;
        }

        if (source == CAPSWITCH_CAPS_USAGE
            && destination == CAPSWITCH_F19_USAGE) {
            found = true;
            continue;
        }

        if (source == CAPSWITCH_CAPS_USAGE
            || source == CAPSWITCH_F19_USAGE
            || destination == CAPSWITCH_CAPS_USAGE
            || destination == CAPSWITCH_F19_USAGE) {
            return 2;
        }
    }

    return found ? 1 : 0;
}

static CFDictionaryRef CreateOurMapping(void) {
    int64_t source = (int64_t)CAPSWITCH_CAPS_USAGE;
    int64_t destination = (int64_t)CAPSWITCH_F19_USAGE;
    CFNumberRef sourceValue = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt64Type, &source
    );
    CFNumberRef destinationValue = CFNumberCreate(
        kCFAllocatorDefault, kCFNumberSInt64Type, &destination
    );

    if (sourceValue == NULL || destinationValue == NULL) {
        if (sourceValue != NULL) CFRelease(sourceValue);
        if (destinationValue != NULL) CFRelease(destinationValue);
        return NULL;
    }

    const void *keys[] = { SOURCE_KEY, DEST_KEY };
    const void *values[] = { sourceValue, destinationValue };
    CFDictionaryRef mapping = CFDictionaryCreate(
        kCFAllocatorDefault, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks
    );
    CFRelease(sourceValue);
    CFRelease(destinationValue);
    return mapping;
}

static int32_t InspectService(
    IOHIDServiceClientRef service, bool *mapped
) {
    CFArrayRef current = CopyMappings(service);
    if (current == NULL) {
        return CapswitchRemapInvalidExistingMappings;
    }

    int state = MappingState(current);
    CFRelease(current);
    if (state < 0) {
        return CapswitchRemapInvalidExistingMappings;
    }
    if (state == 2) {
        return CapswitchRemapConflict;
    }

    *mapped = state == 1;
    return CapswitchRemapOK;
}

// Keeps a separate record of ownership for each HID keyboard service so
// removing our remap will never remove another program's mapping.
static int32_t InstallService(
    CapswitchRemapper *manager, IOHIDServiceClientRef service
) {
    CFNumberRef id = ServiceID(service);
    if (id == NULL) {
        return CapswitchRemapMissingRegistryID;
    }

    CFArrayRef current = CopyMappings(service);
    if (current == NULL) {
        return CapswitchRemapInvalidExistingMappings;
    }

    int state = MappingState(current);
    if (state < 0) {
        CFRelease(current);
        return CapswitchRemapInvalidExistingMappings;
    }
    if (state == 2) {
        CFRelease(current);
        return CapswitchRemapConflict;
    }
    if (state == 1) {
        // Existing Caps->F19 mapping may belong to somebody else.
        // Only the per-service ownership record authorizes restoration.
        CFRelease(current);
        return CapswitchRemapOK;
    }

    CFDictionaryRef ourMapping = CreateOurMapping();
    CFMutableArrayRef desired = CFArrayCreateMutableCopy(
        kCFAllocatorDefault, 0, current
    );
    CFRelease(current);

    if (ourMapping == NULL || desired == NULL) {
        if (ourMapping != NULL) CFRelease(ourMapping);
        if (desired != NULL) CFRelease(desired);
        return CapswitchRemapOutOfMemory;
    }
    CFArrayAppendValue(desired, ourMapping);
    CFRelease(ourMapping);

    // Persist ownership before writing so a crash immediately after writing
    // does not leave behind a remap the next launch cannot recognize.
    CFSetAddValue(manager->ownedServices, id);
    if (!PersistOwnedServices(manager)) {
        // No keyboard remapping has been performed yet; fail closed.
        CFSetRemoveValue(manager->ownedServices, id);
        CFRelease(desired);
        return CapswitchRemapPersistenceFailed;
    }

    bool set = IOHIDServiceClientSetProperty(service, MAPPING_KEY, desired);
    CFRelease(desired);

    if (!set) {
        // Keep the ownership record: a partially accepted write can be safely
        // removed by Restore after observing the exact pair on this service.
        return CapswitchRemapSetFailed;
    }

    bool mapped = false;
    int32_t result = InspectService(service, &mapped);
    if (result != CapswitchRemapOK) {
        return result;
    }
    return mapped ? CapswitchRemapOK : CapswitchRemapVerificationFailed;
}

static int32_t WithKeyboardServices(
    CapswitchRemapper *manager,
    bool install,
    uint32_t *total,
    uint32_t *mapped
) {
    if (total != NULL) *total = 0;
    if (mapped != NULL) *mapped = 0;
    if (manager == NULL) return CapswitchRemapOutOfMemory;

    IOHIDEventSystemClientRef system =
        IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (system == NULL) {
        return CapswitchRemapClientUnavailable;
    }

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == NULL) {
        CFRelease(system);
        return CapswitchRemapClientUnavailable;
    }

    uint32_t keyboardCount = 0;
    uint32_t mappedCount = 0;
    int32_t result = CapswitchRemapOK;

    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)
            CFArrayGetValueAtIndex(services, i);
        if (!KeyboardService(service)) {
            continue;
        }

        keyboardCount++;

        if (install) {
            result = InstallService(manager, service);
        } else {
            bool isMapped = false;
            result = InspectService(service, &isMapped);
        }
        if (result != CapswitchRemapOK) {
            break;
        }

        bool isMapped = false;
        result = InspectService(service, &isMapped);
        if (result != CapswitchRemapOK) {
            break;
        }
        if (isMapped) mappedCount++;
    }

    CFRelease(services);
    CFRelease(system);

    if (total != NULL) *total = keyboardCount;
    if (mapped != NULL) *mapped = mappedCount;

    if (result != CapswitchRemapOK) {
        return result;
    }
    return keyboardCount > 0 ? CapswitchRemapOK : CapswitchRemapNoKeyboards;
}

int32_t CapswitchRemapperApply(
    CapswitchRemapperRef reference,
    uint32_t *keyboardCount,
    uint32_t *mappedCount
) {
    return WithKeyboardServices(
        (CapswitchRemapper *)reference, true, keyboardCount, mappedCount
    );
}

int32_t CapswitchRemapperInspect(
    CapswitchRemapperRef reference,
    uint32_t *keyboardCount,
    uint32_t *mappedCount
) {
    return WithKeyboardServices(
        (CapswitchRemapper *)reference, false, keyboardCount, mappedCount
    );
}

int32_t CapswitchRemapperRestore(CapswitchRemapperRef reference) {
    CapswitchRemapper *manager = (CapswitchRemapper *)reference;
    if (manager == NULL) return CapswitchRemapOutOfMemory;

    IOHIDEventSystemClientRef system =
        IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (system == NULL) return CapswitchRemapClientUnavailable;

    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (services == NULL) {
        CFRelease(system);
        return CapswitchRemapClientUnavailable;
    }

    int32_t result = CapswitchRemapOK;
    CFMutableSetRef connected = CFSetCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeSetCallBacks
    );
    if (connected == NULL) {
        CFRelease(services);
        CFRelease(system);
        return CapswitchRemapOutOfMemory;
    }

    for (CFIndex i = 0; i < CFArrayGetCount(services); i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)
            CFArrayGetValueAtIndex(services, i);
        if (!KeyboardService(service)) continue;

        CFNumberRef id = ServiceID(service);
        if (id == NULL) {
            result = CapswitchRemapMissingRegistryID;
            break;
        }
        CFSetAddValue(connected, id);

        if (!CFSetContainsValue(manager->ownedServices, id)) continue;

        CFArrayRef current = CopyMappings(service);
        if (current == NULL) {
            result = CapswitchRemapInvalidExistingMappings;
            break;
        }

        CFMutableArrayRef desired = CFArrayCreateMutable(
            kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks
        );
        if (desired == NULL) {
            CFRelease(current);
            result = CapswitchRemapOutOfMemory;
            break;
        }

        bool found = false;
        for (CFIndex j = 0; j < CFArrayGetCount(current); j++) {
            CFTypeRef entry = CFArrayGetValueAtIndex(current, j);
            uint64_t source = 0;
            uint64_t destination = 0;

            if (!ReadPair(entry, &source, &destination)) {
                result = CapswitchRemapInvalidExistingMappings;
                break;
            }
            if (source == CAPSWITCH_CAPS_USAGE
                && destination == CAPSWITCH_F19_USAGE) {
                found = true;
            } else {
                CFArrayAppendValue(desired, entry);
            }
        }
        CFRelease(current);

        if (result == CapswitchRemapOK && found) {
            if (!IOHIDServiceClientSetProperty(service, MAPPING_KEY, desired)) {
                result = CapswitchRemapSetFailed;
            } else {
                // Verify only that our exact rule disappeared. A third party
                // may have added another rule during our lifetime; it must
                // not prevent us from restoring (or erasing that rule).
                CFArrayRef verified = CopyMappings(service);
                if (verified == NULL) {
                    result = CapswitchRemapInvalidExistingMappings;
                } else {
                    for (CFIndex k = 0; k < CFArrayGetCount(verified); k++) {
                        uint64_t source = 0;
                        uint64_t destination = 0;
                        CFTypeRef entry = CFArrayGetValueAtIndex(verified, k);

                        if (!ReadPair(entry, &source, &destination)) {
                            result = CapswitchRemapInvalidExistingMappings;
                            break;
                        }
                        if (source == CAPSWITCH_CAPS_USAGE
                            && destination == CAPSWITCH_F19_USAGE) {
                            result = CapswitchRemapVerificationFailed;
                            break;
                        }
                    }
                    CFRelease(verified);
                }
            }
        }

        CFRelease(desired);
        if (result != CapswitchRemapOK) break;

        CFSetRemoveValue(manager->ownedServices, id);
        if (!PersistOwnedServices(manager)) {
            result = CapswitchRemapPersistenceFailed;
            break;
        }
    }

    // IDs for disconnected services can be discarded; macOS discards their
    // key mappings when the keyboard service is removed.
    if (result == CapswitchRemapOK) {
        CFIndex count = CFSetGetCount(manager->ownedServices);
        const void **ids = count > 0 ? calloc((size_t)count, sizeof(void *)) : NULL;
        if (count > 0 && ids == NULL) {
            result = CapswitchRemapOutOfMemory;
        } else {
            if (count > 0) CFSetGetValues(manager->ownedServices, ids);
            for (CFIndex i = 0; i < count; i++) {
                if (!CFSetContainsValue(connected, ids[i])) {
                    CFSetRemoveValue(manager->ownedServices, ids[i]);
                }
            }
            free(ids);
            if (!PersistOwnedServices(manager)) {
                result = CapswitchRemapPersistenceFailed;
            }
        }
    }

    CFRelease(connected);
    CFRelease(services);
    CFRelease(system);
    return result;
}

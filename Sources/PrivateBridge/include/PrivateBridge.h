#pragma once
#import <CoreGraphics/CoreGraphics.h>

/// C ABI called from Swift. All functions are defensive: they return an
/// error instead of crashing when the private classes are missing.
///
/// Error codes (int):
///  0 = success
/// -1 = private API unavailable (class or selector missing)
/// -2 = invalid arguments
/// -3 = creation failed (nil objects / applySettings returned NO)
/// -4 = mirror configuration failed
#ifdef __cplusplus
extern "C" {
#endif

/// Non-zero when all four private classes + required selectors exist.
int PrivateVirtualDisplayAvailable(void);

/// Create a hiDPI virtual display and retain it globally.
/// widths/heights/refreshes: arrays of `count` logical modes.
/// On success writes the new CGDirectDisplayID to `outDisplayID`.
int PrivateVirtualDisplayCreate(
    unsigned int vendorID,
    unsigned int productID,
    unsigned int serialNum,
    const char *name,
    unsigned int maxPixelsWide,
    unsigned int maxPixelsHigh,
    double mmWide,
    double mmHigh,
    unsigned int hiDPI,
    const unsigned int *widths,
    const unsigned int *heights,
    const double *refreshes,
    int count,
    unsigned int *outDisplayID);

/// Release a previously created virtual display. Safe to call with unknown IDs.
void PrivateVirtualDisplayDestroy(unsigned int displayID);

/// Mirror `physicalDisplayID` onto `virtualDisplayID` (physical shows the
/// virtual's content, DCP downsamples 2x -> panel). Pass virtualDisplayID == 0
/// to unmirror `physicalDisplayID`.
int PrivateMirrorPhysicalOntoVirtual(unsigned int physicalDisplayID, unsigned int virtualDisplayID);

#ifdef __cplusplus
}
#endif

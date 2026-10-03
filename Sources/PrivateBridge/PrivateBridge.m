#import "PrivateBridge.h"
#import "CGVirtualDisplayPrivate.h"

static NSMutableDictionary<NSNumber *, CGVirtualDisplay *> *gDisplays = nil;
static NSObject *gLock = nil;

__attribute__((constructor)) static void PrivateBridgeInit(void) {
    gDisplays = [NSMutableDictionary new];
    gLock = [NSObject new];
}

int PrivateVirtualDisplayAvailable(void) {
    Class descriptor = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class vdisplay = NSClassFromString(@"CGVirtualDisplay");
    Class settings = NSClassFromString(@"CGVirtualDisplaySettings");
    Class mode = NSClassFromString(@"CGVirtualDisplayMode");
    if (!descriptor || !vdisplay || !settings || !mode) return 0;
    // Required selectors (from KhaosT header + Chromium usage).
    if (![descriptor instancesRespondToSelector:@selector(init)]) return 0;
    if (![vdisplay instancesRespondToSelector:@selector(initWithDescriptor:)]) return 0;
    if (![vdisplay instancesRespondToSelector:@selector(applySettings:)]) return 0;
    if (![settings instancesRespondToSelector:@selector(init)]) return 0;
    if (![mode instancesRespondToSelector:@selector(initWithWidth:height:refreshRate:)]) return 0;
    return 1;
}

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
    unsigned int *outDisplayID)
{
    if (!widths || !heights || !refreshes || count <= 0 || !outDisplayID || !name) return -2;
    if (!PrivateVirtualDisplayAvailable()) return -1;

    Class DescriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class DisplayClass = NSClassFromString(@"CGVirtualDisplay");
    Class SettingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    Class ModeClass = NSClassFromString(@"CGVirtualDisplayMode");
    if (!DescriptorClass || !DisplayClass || !SettingsClass || !ModeClass) return -1;

    @autoreleasepool {
        CGVirtualDisplayDescriptor *descriptor = [[DescriptorClass alloc] init];
        if (!descriptor) return -3;
        descriptor.vendorID = vendorID;
        descriptor.productID = productID;
        descriptor.serialNum = serialNum;
        descriptor.name = [NSString stringWithUTF8String:name];
        descriptor.maxPixelsWide = maxPixelsWide;
        descriptor.maxPixelsHigh = maxPixelsHigh;
        descriptor.sizeInMillimeters = CGSizeMake(mmWide, mmHigh);
        // Dedicated queue: the main queue can be blocked by the caller's
        // online-wait poll, which previously deadlocked activation.
        dispatch_queue_t q = dispatch_queue_create("com.simplehidpiscaler.virtual", DISPATCH_QUEUE_SERIAL);
        if ([descriptor respondsToSelector:@selector(setDispatchQueue:)]) {
            [descriptor setDispatchQueue:q];
        } else {
            descriptor.queue = q;
        }

        NSMutableArray *modes = [NSMutableArray arrayWithCapacity:count];
        for (int i = 0; i < count; i++) {
            CGVirtualDisplayMode *m = [[ModeClass alloc] initWithWidth:widths[i]
                                                               height:heights[i]
                                                          refreshRate:refreshes[i]];
            if (m) [modes addObject:m];
        }
        if (modes.count == 0) return -2;

        CGVirtualDisplaySettings *settings = [[SettingsClass alloc] init];
        if (!settings) return -3;
        settings.hiDPI = hiDPI;
        settings.modes = modes;

        CGVirtualDisplay *display = [[DisplayClass alloc] initWithDescriptor:descriptor];
        if (!display) return -3;
        if (![display applySettings:settings]) return -3;

        CGDirectDisplayID did = [display displayID];
        if (did == 0) return -3;

        @synchronized (gLock) {
            gDisplays[@(did)] = display;
        }
        // Break any potential retain cycle warnings: keep descriptor alive via display.
        (void)descriptor;
        *outDisplayID = (unsigned int)did;
        return 0;
    }
}

void PrivateVirtualDisplayDestroy(unsigned int displayID) {
    if (displayID == 0) return;
    @synchronized (gLock) {
        [gDisplays removeObjectForKey:@(displayID)];
    }
    // Removing the last retain lets WindowServer tear the virtual display down.
}

int PrivateMirrorPhysicalOntoVirtual(unsigned int physicalDisplayID, unsigned int virtualDisplayID) {
    if (physicalDisplayID == 0) return -2;
    if (physicalDisplayID == virtualDisplayID) return -5; // never mirror a display onto itself
    CGDisplayConfigRef config = NULL;
    CGError err = CGBeginDisplayConfiguration(&config);
    if (err != kCGErrorSuccess) return -10;
    // Public API: display `physical` mirrors `virtual`. 0 unmirrors.
    err = CGConfigureDisplayMirrorOfDisplay(config,
                                            (CGDirectDisplayID)physicalDisplayID,
                                            (CGDirectDisplayID)virtualDisplayID);
    if (err != kCGErrorSuccess) {
        int code = (err == kCGErrorFailure) ? -11 : -12;
        CGCancelDisplayConfiguration(config);
        return code;
    }
    err = CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
    return (err == kCGErrorSuccess) ? 0 : -13;
}

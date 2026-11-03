#import "TBDiagnostics.h"
#import "TBPrivateAPI.h"
#import <objc/runtime.h>
#include <math.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <IOKit/IOKitLib.h>

static NSString *const kCoreBrightness = @"/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness";
static NSString *const kDFRBrightness = @"/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness";

static NSString *SysctlString(const char *name) {
    size_t size = 0;
    if (sysctlbyname(name, NULL, &size, NULL, 0) != 0 || size == 0) return @"-";
    char *buffer = calloc(size + 1, 1);
    if (!buffer) return @"-";
    if (sysctlbyname(name, buffer, &size, NULL, 0) != 0) { free(buffer); return @"-"; }
    NSString *s = [NSString stringWithUTF8String:buffer] ?: @"-";
    free(buffer);
    return s;
}

static NSString *Flat(id value) {
    if ([value isKindOfClass:NSNumber.class]) return [value description];
    if ([value isKindOfClass:NSDictionary.class]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in @[@"Brightness", @"NitsPhysical", @"Nits"]) {
            id number = value[key];
            if ([number isKindOfClass:NSNumber.class])
                [parts addObject:[NSString stringWithFormat:@"%@=%@", key, number]];
        }
        return [parts componentsJoinedByString:@" "];
    }
    return value ? @"(unsupported value)" : @"(nil)";
}

/// Runs a probe step; a missing selector or an exception counts as failure.
static BOOL Attempt(BOOL (^step)(void)) {
    @try {
        return step();
    } @catch (NSException *e) {
        NSLog(@"TBDiagnostics: %@: %@", e.name, e.reason);
        return NO;
    }
}

static DFRBrightnessClient *NewDFRClient(void) {
    TBLoadPrivateFrameworks();
    Class cls = NSClassFromString(@"DFRBrightnessClient");
    return cls ? [[cls alloc] init] : nil;
}

static BrightnessSystemClient *NewCBClient(void) {
    TBLoadPrivateFrameworks();
    Class cls = NSClassFromString(@"BrightnessSystemClient");
    return cls ? [[cls alloc] init] : nil;
}

static unsigned DFRDisplayID(DFRBrightnessClient *dfr) {
    unsigned value = [dfr respondsToSelector:@selector(getDFRDisplayID)] ? [dfr getDFRDisplayID] : 0;
    return value == UINT32_MAX ? 0 : value;
}

static BOOL HasDisplayAPI(BrightnessSystemClient *cb) {
    return [cb respondsToSelector:@selector(copyPropertyForKey:andDisplay:)]
        && [cb respondsToSelector:@selector(setProperty:withKey:andDisplay:)];
}

@implementation TBDiagnostics

+ (NSArray<NSArray<NSString *> *> *)collectSections {
    TBLoadPrivateFrameworks();
    NSMutableArray<NSArray<NSString *> *> *sections = [NSMutableArray array];
    void (^section)(NSString *, NSString * (^)(void)) = ^(NSString *title, NSString * (^body)(void)) {
        NSString *text;
        @try {
            text = body();
        } @catch (NSException *e) {
            text = [NSString stringWithFormat:@"<exception %@: %@>", e.name, e.reason];
        }
        [sections addObject:@[title, text]];
    };

    section(@"Mac", ^{ return [self macSection]; });
    section(@"IORegistry", ^{ return [self registrySection]; });
    section(@"Private classes", ^{ return [self classesSection]; });
    section(@"corebrightnessd", ^{ return [self coreBrightnessSection]; });
    section(@"DFRBrightness", ^{ return [self dfrSection]; });
    return sections;
}

+ (NSString *)macSection {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    return [@[
        [NSString stringWithFormat:@"model: %@", SysctlString("hw.model")],
        [NSString stringWithFormat:@"chip: %@", SysctlString("machdep.cpu.brand_string")],
        [NSString stringWithFormat:@"macOS: %ld.%ld.%ld (%@)", (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion, SysctlString("kern.osversion")],
    ] componentsJoinedByString:@"\n"];
}

/// Registry entries whose name or class mentions the Touch Bar or a backlight.
+ (NSString *)registrySection {
    NSRegularExpression *interesting = [NSRegularExpression regularExpressionWithPattern:@"dfr|touch ?bar|backlight"
                                                                                 options:NSRegularExpressionCaseInsensitive error:nil];
    // Allow only known numeric backlight properties. Unknown registry data stays on the Mac.
    NSSet<NSString *> *allowed = [NSSet setWithArray:@[@"dfr-brightness-control", @"brightness", @"dimming-step", @"dimming-factor"]];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSUInteger entries = 0;
    for (NSString *plane in @[@kIOServicePlane, @kIODeviceTreePlane]) {
        io_iterator_t it = 0;
        if (IORegistryCreateIterator(kIOMainPortDefault, plane.UTF8String, kIORegistryIterateRecursively, &it) != KERN_SUCCESS) continue;
        io_registry_entry_t entry;
        while (entries < 80 && (entry = IOIteratorNext(it))) {
            io_name_t name = {0};
            IORegistryEntryGetNameInPlane(entry, plane.UTF8String, name);
            CFStringRef cls = IOObjectCopyClass(entry);
            NSString *label = [NSString stringWithFormat:@"%s <%@>", name, (__bridge NSString *)cls];
            if (cls) CFRelease(cls);
            if ([interesting firstMatchInString:label options:0 range:NSMakeRange(0, label.length)]) {
                entries++;
                [lines addObject:[NSString stringWithFormat:@"[%@] %@", plane, label]];
                CFMutableDictionaryRef props = NULL;
                if (IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS && props) {
                    NSDictionary *dict = (__bridge_transfer NSDictionary *)props;
                    for (NSString *key in [dict.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                        if (![allowed containsObject:key] || ![dict[key] isKindOfClass:NSNumber.class]) continue;
                        NSString *value = [dict[key] description];
                        if (value) [lines addObject:[NSString stringWithFormat:@"    %@ = %@", key, value]];
                    }
                }
            }
            IOObjectRelease(entry);
        }
        IOObjectRelease(it);
    }
    if (!lines.count) return @"no matching entries";
    if (entries >= 80) [lines addObject:@"(truncated after 80 entries)"];
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)classesSection {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSetWithArray:@[
        @"BrightnessSystemClient", @"CBDisplayHandle", @"DFRBrightnessClient", @"KeyboardBrightnessClient"]];
    for (NSString *image in @[kCoreBrightness, kDFRBrightness]) {
        Class anchor = NSClassFromString([image isEqual:kCoreBrightness] ? @"BrightnessSystemClient" : @"DFRBrightnessClient");
        const char *imageName = anchor ? class_getImageName(anchor) : NULL;
        if (!imageName) continue;
        unsigned count = 0;
        const char **classNames = objc_copyClassNamesForImage(imageName, &count);
        for (unsigned i = 0; i < count; i++) {
            NSString *n = @(classNames[i]);
            if ([n rangeOfString:@"DFR"].location != NSNotFound || [n rangeOfString:@"TouchBar" options:NSCaseInsensitiveSearch].location != NSNotFound)
                [names addObject:n];
        }
        free(classNames);
    }
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) {
            [lines addObject:[NSString stringWithFormat:@"%@: missing", name]];
            continue;
        }
        [lines addObject:[NSString stringWithFormat:@"%@ (%s)", name, class_getImageName(cls) ?: "?"]];
        for (int meta = 0; meta < 2; meta++) {
            unsigned count = 0;
            Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
            NSMutableArray *entries = [NSMutableArray array];
            for (unsigned i = 0; i < count; i++)
                [entries addObject:[NSString stringWithFormat:@"    %c %s  %s", meta ? '+' : '-', sel_getName(method_getName(methods[i])),
                                    method_getTypeEncoding(methods[i]) ?: "?"]];
            free(methods);
            [lines addObjectsFromArray:[entries sortedArrayUsingSelector:@selector(compare:)]];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)coreBrightnessSection {
    BrightnessSystemClient *cb = NewCBClient();
    if (!cb) return @"BrightnessSystemClient missing";
    unsigned displayID = DFRDisplayID(NewDFRClient());
    NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"Touch Bar display id: %u", displayID]];
    if (displayID && HasDisplayAPI(cb)) {
        for (NSString *key in @[@"DisplayBrightnessAuto", @"DisplayBrightness", @"DFRDisplayState", @"DisplayBrightnessFactor",
                                @"DisplayPanelLuminanceMin", @"DisplayPanelLuminanceMax"])
            [lines addObject:[NSString stringWithFormat:@"%@ = %@", key, Flat([cb copyPropertyForKey:key andDisplay:displayID])]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)dfrSection {
    DFRBrightnessClient *dfr = NewDFRClient();
    if (!dfr) return @"DFRBrightnessClient missing";
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"display id: %u", DFRDisplayID(dfr)]];
    if ([dfr respondsToSelector:@selector(getDimmingStep)])
        [lines addObject:[NSString stringWithFormat:@"dimming step: %lld", [dfr getDimmingStep]]];
    if ([dfr respondsToSelector:@selector(copyPropertyForKey:)]) {
        for (NSString *key in @[@"DFRDisplayState", @"DimmingStep", @"DimmingFactorValue", @"DFRBurninCounter"])
            [lines addObject:[NSString stringWithFormat:@"%@ = %@", key, Flat([dfr copyPropertyForKey:key])]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (BOOL)panelTurnOff {
    return Attempt(^{
        DFRBrightnessClient *dfr = NewDFRClient();
        return (BOOL)([dfr respondsToSelector:@selector(turnOff)] && [dfr turnOff]);
    });
}

+ (BOOL)panelTurnOn {
    return Attempt(^{
        DFRBrightnessClient *dfr = NewDFRClient();
        return (BOOL)([dfr respondsToSelector:@selector(turnOn)] && [dfr turnOn]);
    });
}

+ (BOOL)setDimmingCoefficient:(float)coefficient {
    if (!isfinite(coefficient) || coefficient < 0 || coefficient > 1) return NO;
    return Attempt(^{
        DFRBrightnessClient *dfr = NewDFRClient();
        return (BOOL)([dfr respondsToSelector:@selector(dimToStep:withCoefficient:)] && [dfr dimToStep:0 withCoefficient:coefficient]);
    });
}

+ (nullable NSDictionary<NSString *, NSNumber *> *)readBrightness {
    __block NSDictionary *result = nil;
    Attempt(^{
        BrightnessSystemClient *cb = NewCBClient();
        unsigned displayID = DFRDisplayID(NewDFRClient());
        if (!displayID || !HasDisplayAPI(cb)) return NO;
        id autoFlag = [cb copyPropertyForKey:@"DisplayBrightnessAuto" andDisplay:displayID];
        id info = [cb copyPropertyForKey:@"DisplayBrightness" andDisplay:displayID];
        if (![autoFlag isKindOfClass:NSNumber.class] || ![info isKindOfClass:NSDictionary.class] ||
            ![info[@"Brightness"] isKindOfClass:NSNumber.class]) return NO;
        result = @{@"auto": autoFlag, @"level": info[@"Brightness"]};
        return YES;
    });
    return result;
}

+ (BOOL)writeAutoBrightness:(BOOL)enabled level:(nullable NSNumber *)level {
    if (level && (!isfinite(level.floatValue) || level.floatValue < 0 || level.floatValue > 1)) return NO;
    return Attempt(^{
        BrightnessSystemClient *cb = NewCBClient();
        unsigned displayID = DFRDisplayID(NewDFRClient());
        if (!displayID || !HasDisplayAPI(cb)) return NO;
        BOOL ok = [cb setProperty:@(enabled) withKey:@"DisplayBrightnessAuto" andDisplay:displayID];
        if (level && ok) ok = [cb setProperty:level withKey:@"DisplayBrightness" andDisplay:displayID];
        return ok;
    });
}

@end

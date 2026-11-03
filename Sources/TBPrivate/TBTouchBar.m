#import "TBTouchBar.h"
#import "TBPrivateAPI.h"
#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <IOKit/IOKitLib.h>
#import <objc/runtime.h>

static NSArray<NSString *> *Frameworks(void) {
    return @[@"/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
             @"/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness"];
}

/// Everything this file sends to the private classes; "-" instance method, "+" class method.
static NSDictionary<NSString *, NSArray<NSString *> *> *RequiredAPIs(void) {
    return @{
        @"BrightnessSystemClient": @[@"-copyPropertyForKey:andDisplay:", @"-setProperty:withKey:andDisplay:"],
        @"DFRBrightnessClient": @[@"-getDFRDisplayID", @"-getDimmingStep", @"-dimToStep:", @"-turnOn", @"-turnOff",
                                  @"-scheduleWithDispatchQueue:", @"-registerDisplayStateUpdateCallbackWithBlock:"],
    };
}

NSArray<NSString *> *TBLoadPrivateFrameworks(void) {
    NSMutableArray<NSString *> *failed = [NSMutableArray array];
    static NSArray<NSString *> *cachedFailures;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *path in Frameworks()) {
            if (!dlopen(path.fileSystemRepresentation, RTLD_NOW)) {
                const char *err = dlerror();
                [failed addObject:[NSString stringWithFormat:@"%@ (%s)", path.lastPathComponent, err ?: "unknown error"]];
            }
        }
        cachedFailures = [failed copy];
    });
    return cachedFailures;
}

/// Touch Bar hardware, independent of the private frameworks: the device tree marks its backlight node.
static BOOL HasTouchBarHardware(void) {
    io_registry_entry_t root = IORegistryGetRootEntry(kIOMainPortDefault);
    if (!root) return NO;
    CFTypeRef marker = IORegistryEntrySearchCFProperty(root, kIODeviceTreePlane, CFSTR("dfr-brightness-control"),
                                                       kCFAllocatorDefault, kIORegistryIterateRecursively);
    IOObjectRelease(root);
    if (marker) CFRelease(marker);
    return marker != NULL;
}

/// Integer argument expected at `index` (0 = self, 1 = _cmd); calling with the wrong type would misbehave silently.
static BOOL ArgumentIsInteger(Class cls, SEL sel, unsigned index) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m || index >= method_getNumberOfArguments(m)) return NO;
    char type[16] = {0};
    method_getArgumentType(m, index, type, sizeof type);
    return type[0] && strchr("QqIiLl", type[0]) != NULL;
}

static NSString *DescribeBadValue(NSString *key, id value, NSError *error) {
    if (error) return [NSString stringWithFormat:@"%@: %@", key, error.localizedDescription];
    if (!value) return [NSString stringWithFormat:@"%@: no value", key];
    return [NSString stringWithFormat:@"%@: unexpected %@", key, NSStringFromClass([value class])];
}

@implementation TBCheckResult

- (instancetype)initWithName:(NSString *)name passed:(BOOL)passed detail:(NSString *)detail {
    if ((self = [super init])) {
        _name = [name copy];
        _passed = passed;
        _detail = [detail copy];
    }
    return self;
}

@end

@implementation TBTouchBar {
    BrightnessSystemClient *_cb;
    DFRBrightnessClient *_dfr;
    unsigned _displayID;
    float _minNits, _maxNits;
}

+ (NSArray<NSString *> *)missingAPIs {
    TBLoadPrivateFrameworks();
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    NSDictionary<NSString *, NSArray<NSString *> *> *required = RequiredAPIs();
    for (NSString *className in [required.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            [missing addObject:className];
            continue;
        }
        for (NSString *entry in required[className]) {
            SEL sel = NSSelectorFromString([entry substringFromIndex:1]);
            BOOL present = [entry hasPrefix:@"+"] ? [cls respondsToSelector:sel] : [cls instancesRespondToSelector:sel];
            if (!present) [missing addObject:[NSString stringWithFormat:@"%@ %@", className, entry]];
        }
    }
    // The display id is passed as a plain integer; a different type means the API changed shape.
    Class cb = NSClassFromString(@"BrightnessSystemClient");
    if (cb && [cb instancesRespondToSelector:@selector(copyPropertyForKey:andDisplay:)]
           && !ArgumentIsInteger(cb, @selector(copyPropertyForKey:andDisplay:), 3))
        [missing addObject:@"BrightnessSystemClient -copyPropertyForKey:andDisplay: (display is not an integer)"];
    if (cb && [cb instancesRespondToSelector:@selector(setProperty:withKey:andDisplay:)]
           && !ArgumentIsInteger(cb, @selector(setProperty:withKey:andDisplay:), 4))
        [missing addObject:@"BrightnessSystemClient -setProperty:withKey:andDisplay: (display is not an integer)"];
    return missing;
}

+ (NSArray<TBCheckResult *> *)runCompatibilityChecks {
    NSMutableArray<TBCheckResult *> *results = [NSMutableArray array];
    void (^add)(NSString *, BOOL, NSString *) = ^(NSString *name, BOOL passed, NSString *detail) {
        [results addObject:[[TBCheckResult alloc] initWithName:name passed:passed detail:detail]];
    };

    @try {
        // Hardware first, but keep probing the frameworks either way: the report is also how
        // API changes in a new macOS release get spotted.
        BOOL hardware = HasTouchBarHardware();
        add(@"hardware", hardware, hardware ? @"Touch Bar backlight in the device tree" : @"no Touch Bar on this Mac");

        NSArray<NSString *> *failed = TBLoadPrivateFrameworks();
        add(@"frameworks", failed.count == 0,
            failed.count ? [@"cannot load " stringByAppendingString:[failed componentsJoinedByString:@", "]]
                         : @"CoreBrightness and DFRBrightness loaded");
        if (failed.count) return results;

        NSArray<NSString *> *missing = [self missingAPIs];
        add(@"api", missing.count == 0,
            missing.count ? [@"missing " stringByAppendingString:[missing componentsJoinedByString:@", "]]
                          : @"all private classes and selectors present");
        if (missing.count || !hardware) return results;

        DFRBrightnessClient *dfr = [[NSClassFromString(@"DFRBrightnessClient") alloc] init];
        unsigned displayID = [dfr getDFRDisplayID];
        if (!displayID || displayID == UINT32_MAX) {
            add(@"control", NO, @"Touch Bar service returned no valid display id; service access may be unavailable or restricted");
            return results;
        }
        add(@"touchBar", YES, [NSString stringWithFormat:@"Touch Bar display id %u", displayID]);

        TBTouchBar *tb = [[self alloc] initWithDisplayID:displayID client:dfr];
        if (!tb) {
            add(@"corebrightnessd", NO, @"cannot create a corebrightnessd client for the Touch Bar display");
            return results;
        }
        [tb addRuntimeChecks:add];
    } @catch (NSException *e) {
        add(@"exception", NO, [NSString stringWithFormat:@"%@: %@", e.name, e.reason]);
    }
    return results;
}

+ (nullable TBTouchBar *)connect {
    @try {
        if (TBLoadPrivateFrameworks().count || [self missingAPIs].count) return nil;
        DFRBrightnessClient *dfr = [[NSClassFromString(@"DFRBrightnessClient") alloc] init];
        unsigned displayID = [dfr getDFRDisplayID];
        if (!displayID || displayID == UINT32_MAX) return nil;
        return [[self alloc] initWithDisplayID:displayID client:dfr];
    } @catch (NSException *e) {
        NSLog(@"TBTouchBar: connect failed: %@", e);
        return nil;
    }
}

- (nullable instancetype)initWithDisplayID:(unsigned)displayID client:(DFRBrightnessClient *)dfr {
    if (!(self = [super init])) return nil;
    _dfr = dfr;
    _displayID = displayID;
    [_dfr scheduleWithDispatchQueue:dispatch_get_main_queue()];

    _cb = [[NSClassFromString(@"BrightnessSystemClient") alloc] init];
    if (!_cb) return nil;

    _minNits = [[self copyNumber:@"DisplayPanelLuminanceMin"] floatValue];
    _maxNits = [[self copyNumber:@"DisplayPanelLuminanceMax"] floatValue];
    if (!isfinite(_minNits) || !isfinite(_maxNits) || _minNits < 0 || _maxNits <= _minNits) return nil;
    return self;
}

/// Reads every key the app relies on and checks its type, without writing hardware settings.
- (void)addRuntimeChecks:(void (^)(NSString *, BOOL, NSString *))add {
    NSMutableArray<NSString *> *problems = [NSMutableArray array];

    id autoFlag = [self copyKey:@"DisplayBrightnessAuto"];
    if (![autoFlag isKindOfClass:NSNumber.class]) [problems addObject:DescribeBadValue(@"DisplayBrightnessAuto", autoFlag, nil)];

    id info = [self copyKey:@"DisplayBrightness"];
    if (![info isKindOfClass:NSDictionary.class] || ![info[@"Brightness"] isKindOfClass:NSNumber.class]
        || !isfinite([info[@"Brightness"] floatValue]) || [info[@"Brightness"] floatValue] < 0
        || [info[@"Brightness"] floatValue] > 1)
        [problems addObject:DescribeBadValue(@"DisplayBrightness", info, nil)];

    id state = [self copyKey:@"DFRDisplayState"];
    if (![state isKindOfClass:NSNumber.class] || ([state longValue] != TBDisplayStateOn && [state longValue] != TBDisplayStateOff)) [problems addObject:DescribeBadValue(@"DFRDisplayState", state, nil)];

    for (NSString *key in @[@"DisplayPanelLuminanceMin", @"DisplayPanelLuminanceMax"]) {
        id v = [self copyKey:key];
        if (![v isKindOfClass:NSNumber.class] || !isfinite([v floatValue]) || [v floatValue] < 0) [problems addObject:DescribeBadValue(key, v, nil)];
    }

    add(@"corebrightnessd", problems.count == 0,
        problems.count ? [problems componentsJoinedByString:@"; "]
                       : [NSString stringWithFormat:@"auto=%@ brightness=%.3f state=%@ range=%.1f-%.1f nits",
                          autoFlag, [info[@"Brightness"] floatValue], state, _minNits, _maxNits]);
    if (problems.count) return;

    long step = [_dfr getDimmingStep];
    add(@"touchBarServer", step >= 0, [NSString stringWithFormat:@"dimming step %ld", step]);
}

- (nullable id)copyKey:(NSString *)key {
    return [_cb copyPropertyForKey:key andDisplay:_displayID];
}

- (nullable NSNumber *)copyNumber:(NSString *)key {
    id v = [self copyKey:key];
    return [v isKindOfClass:NSNumber.class] ? v : nil;
}

- (nullable NSDictionary *)brightnessInfo {
    id v = [self copyKey:@"DisplayBrightness"];
    return [v isKindOfClass:NSDictionary.class] ? v : nil;
}

- (BOOL)autoBrightness { return [[self copyNumber:@"DisplayBrightnessAuto"] boolValue]; }
- (BOOL)setAutoBrightness:(BOOL)enabled {
    return [_cb setProperty:@(enabled) withKey:@"DisplayBrightnessAuto" andDisplay:_displayID];
}

- (float)brightness { return [[self brightnessInfo][@"Brightness"] floatValue]; }
- (BOOL)setBrightness:(float)value {
    if (!isfinite(value)) return NO;
    value = MAX(0.0f, MIN(1.0f, value));
    return [_cb setProperty:@(value) withKey:@"DisplayBrightness" andDisplay:_displayID];
}

- (float)physicalNits { return [[self brightnessInfo][@"NitsPhysical"] floatValue]; }
- (float)minNits { return _minNits; }
- (float)maxNits { return _maxNits; }

- (TBDisplayState)displayState {
    // DFRBrightnessClient.displayState starts at "on" in a fresh client and only follows callbacks,
    // so ask corebrightnessd, which tracks the real panel state.
    long s = [[self copyNumber:@"DFRDisplayState"] longValue];
    return (s == TBDisplayStateOn || s == TBDisplayStateOff) ? (TBDisplayState)s : TBDisplayStateUnknown;
}
- (NSInteger)dimmingStep { return [_dfr getDimmingStep]; }
- (void)undim { [_dfr dimToStep:0]; }
- (void)turnOn { [_dfr turnOn]; }
- (void)turnOff { [_dfr turnOff]; }

- (void)setDisplayStateHandler:(void (^)(TBDisplayState))handler {
    [_dfr registerDisplayStateUpdateCallbackWithBlock:^(long s) {
        TBDisplayState state = (s == TBDisplayStateOn || s == TBDisplayStateOff) ? (TBDisplayState)s : TBDisplayStateUnknown;
        dispatch_async(dispatch_get_main_queue(), ^{ handler(state); });
    }];
}

@end

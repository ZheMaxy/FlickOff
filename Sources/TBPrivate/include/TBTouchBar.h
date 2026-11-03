// Thin wrapper over the private frameworks that drive the Touch Bar backlight:
//   CoreBrightness - corebrightnessd: auto-brightness flag and brightness level of the Touch Bar display
//   DFRBrightness  - the channel TouchBarServer uses for on/off and idle dimming
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TBDisplayState) {
    TBDisplayStateUnknown = -1,
    TBDisplayStateOff = 1,
    TBDisplayStateOn = 2,
};

/// One step of the launch-time compatibility check.
@interface TBCheckResult : NSObject
@property (nonatomic, readonly, copy) NSString *name;   // stable id: hardware, frameworks, api, touchBar, corebrightnessd, control, touchBarServer, exception
@property (nonatomic, readonly) BOOL passed;
@property (nonatomic, readonly, copy) NSString *detail;
- (instancetype)init NS_UNAVAILABLE;
@end

@interface TBTouchBar : NSObject

/// Private classes/selectors this wrapper calls that are missing on the running macOS
/// (e.g. "DFRBrightnessClient -dimToStep:"). Empty when everything is in place.
+ (NSArray<NSString *> *)missingAPIs;

/// Probes the private APIs step by step and stops at the first failure. Read-only; does not
/// change the auto-brightness flag or panel state. Never throws.
+ (NSArray<TBCheckResult *> *)runCompatibilityChecks;

/// nil when this Mac has no Touch Bar or the private frameworks changed.
+ (nullable TBTouchBar *)connect;
- (instancetype)init NS_UNAVAILABLE;

// corebrightnessd
@property (nonatomic, readonly) BOOL autoBrightness;
- (BOOL)setAutoBrightness:(BOOL)enabled;
@property (nonatomic, readonly) float brightness;   // 0...1
- (BOOL)setBrightness:(float)value;
@property (nonatomic, readonly) float physicalNits; // actual light output, 0 when the panel is off
@property (nonatomic, readonly) float minNits;
@property (nonatomic, readonly) float maxNits;
@property (nonatomic, readonly) TBDisplayState displayState;

// TouchBarServer channel
@property (nonatomic, readonly) NSInteger dimmingStep; // 0 = not dimmed
- (void)undim;
- (void)turnOn;
- (void)turnOff;
/// Called on the main queue whenever the panel turns on or off.
- (void)setDisplayStateHandler:(void (^)(TBDisplayState state))handler;

@end

NS_ASSUME_NONNULL_END

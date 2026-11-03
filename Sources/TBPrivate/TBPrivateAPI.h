// The private classes this target sends messages to. Internal: not part of the public headers.
// TBTouchBar checks the selectors it relies on at runtime; TBDiagnostics checks each one before calling it.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Display-addressed corebrightnessd calls.
@interface BrightnessSystemClient : NSObject
- (nullable id)copyPropertyForKey:(NSString *)key andDisplay:(unsigned long long)displayID;
- (BOOL)setProperty:(id)value withKey:(NSString *)key andDisplay:(unsigned long long)displayID;
@end

// The channel TouchBarServer uses for on/off and idle dimming.
@interface DFRBrightnessClient : NSObject
- (unsigned)getDFRDisplayID;
- (long long)getDimmingStep;
- (BOOL)dimToStep:(long long)step;
- (BOOL)dimToStep:(long long)step withCoefficient:(float)coefficient;
- (BOOL)turnOn;
- (BOOL)turnOff;
- (nullable id)copyPropertyForKey:(id)key;
- (void)scheduleWithDispatchQueue:(dispatch_queue_t)queue;
- (BOOL)registerDisplayStateUpdateCallbackWithBlock:(void (^)(long state))block;
@end

/// Loads CoreBrightness and DFRBrightness once. Returns the frameworks that failed, with the dlerror text.
NSArray<NSString *> *TBLoadPrivateFrameworks(void);

NS_ASSUME_NONNULL_END

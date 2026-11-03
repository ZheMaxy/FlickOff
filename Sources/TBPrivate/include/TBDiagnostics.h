// Remote diagnostics for customers' Macs: read-only snapshots plus small reversible probes
// whose visible effect the user confirms. Nothing here throws.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBDiagnostics : NSObject

/// Ordered (title, text) pairs: Mac, IORegistry entries related to the Touch Bar, private classes with
/// type encodings, corebrightnessd and DFRBrightness state. Serial numbers are left out.
+ (NSArray<NSArray<NSString *> *> *)collectSections;

// Probe building blocks. Each returns NO when the API is missing, refuses, or throws.
+ (BOOL)panelTurnOff;
+ (BOOL)panelTurnOn;
/// TouchBarServer channel: scales the light output (0...1) without touching corebrightnessd.
+ (BOOL)setDimmingCoefficient:(float)coefficient;
/// corebrightnessd: current auto flag and level of the Touch Bar display, nil when unavailable.
+ (nullable NSDictionary<NSString *, NSNumber *> *)readBrightness;
+ (BOOL)writeAutoBrightness:(BOOL)enabled level:(nullable NSNumber *)level;

@end

NS_ASSUME_NONNULL_END

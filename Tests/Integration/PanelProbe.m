// Local integration-test companion. Not linked into the application.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import "TBTouchBar.h"
#include <math.h>

@interface NSObject (TestDimming)
- (BOOL)dimToStep:(long)step;
@end

static BOOL LidClosed(void) {
    io_registry_entry_t root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!root) return YES;
    CFTypeRef value = IORegistryEntryCreateCFProperty(root, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    NSNumber *closed = CFBridgingRelease(value);
    return closed ? closed.boolValue : YES;
}

static BOOL DisplayAsleep(void) {
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(0, NULL, &count) != kCGErrorSuccess || !count) return YES;
    CGDirectDisplayID *ids = calloc(count, sizeof(CGDirectDisplayID));
    if (!ids) return YES;
    BOOL asleep = YES;
    if (CGGetOnlineDisplayList(count, ids, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayIsBuiltin(ids[i])) { asleep = CGDisplayIsAsleep(ids[i]); break; }
        }
    }
    free(ids);
    return asleep;
}

static BOOL ScreenLocked(void) {
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    return !session || [session[@"CGSSessionScreenIsLocked"] boolValue];
}

static NSDictionary *Snapshot(TBTouchBar *tb) {
    return @{@"auto": @(tb.autoBrightness), @"level": @(tb.brightness),
             @"panel": @(tb.displayState), @"step": @(tb.dimmingStep),
             @"nits": @(isfinite(tb.physicalNits) ? tb.physicalNits : 0),
             @"locked": @(ScreenLocked()), @"lidClosed": @(LidClosed()),
             @"displayAsleep": @(DisplayAsleep()),
             @"idle": @(CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType))};
}

static BOOL Dim(long step) {
    id client = [[NSClassFromString(@"DFRBrightnessClient") alloc] init];
    return [client respondsToSelector:@selector(dimToStep:)] && [client dimToStep:step];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *command = argc > 1 ? @(argv[1]) : @"snapshot";
        if ([command isEqual:@"quit"] && argc == 3) {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[2])];
            return app && [app terminate] ? 0 : 1;
        }
        // Counts the ordinary windows a process shows on screen; its menu bar item sits on a higher layer.
        if ([command isEqual:@"windows"] && argc == 3) {
            NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
            int count = 0;
            for (NSDictionary *window in windows) {
                if ([window[(__bridge id)kCGWindowOwnerPID] intValue] == atoi(argv[2])
                    && [window[(__bridge id)kCGWindowLayer] intValue] == 0) count++;
            }
            printf("%d\n", count);
            return 0;
        }
        // Counts as user input without moving the pointer. Needs Accessibility access: exit code 3 without it.
        if ([command isEqual:@"input"]) {
            if (!CGPreflightPostEventAccess()) return 3;
            CGEventRef current = CGEventCreate(NULL);
            if (!current) return 1;
            CGEventRef move = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGEventGetLocation(current), kCGMouseButtonLeft);
            CFRelease(current);
            if (!move) return 1;
            CGEventPost(kCGHIDEventTap, move);
            CFRelease(move);
            return 0;
        }
        TBTouchBar *tb = [TBTouchBar connect];
        if (!tb) { fprintf(stderr, "No Touch Bar connection\n"); return 1; }
        if ([command isEqual:@"level"] && argc == 3) {
            char *end = NULL;
            float level = strtof(argv[2], &end);
            if (!end || *end || !isfinite(level) || level < 0 || level > 1) return 2;
            return [tb setAutoBrightness:NO] && [tb setBrightness:level] ? 0 : 1;
        }
        if ([command isEqual:@"on"]) {
            if (ScreenLocked() || LidClosed() || DisplayAsleep()) return 1;
            [tb turnOn]; return 0;
        }
        if ([command isEqual:@"off"]) { [tb turnOff]; return 0; }
        if ([command isEqual:@"dim"]) return Dim(1) ? 0 : 1;
        if ([command isEqual:@"restore"] && argc == 3) {
            NSData *data = [NSData dataWithContentsOfFile:@(argv[2])];
            NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (![saved isKindOfClass:NSDictionary.class] || ![saved[@"auto"] isKindOfClass:NSNumber.class]
                || ![saved[@"level"] isKindOfClass:NSNumber.class]) return 2;
            float level = [saved[@"level"] floatValue];
            if (!isfinite(level) || level < 0 || level > 1) return 2;
            BOOL automatic = [saved[@"auto"] boolValue];
            BOOL ok = [tb setAutoBrightness:automatic];
            if (ok && !automatic) ok = [tb setBrightness:level];
            if ([saved[@"panel"] integerValue] == TBDisplayStateOn && !ScreenLocked() && !LidClosed() && !DisplayAsleep()) {
                [tb turnOn]; Dim([saved[@"step"] longValue]);
            } else if ([saved[@"panel"] integerValue] == TBDisplayStateOff) { [tb turnOff]; }
            return ok ? 0 : 1;
        }
        if (![command isEqual:@"snapshot"]) return 2;
        NSData *json = [NSJSONSerialization dataWithJSONObject:Snapshot(tb) options:0 error:NULL];
        if (!json) return 1;
        fwrite(json.bytes, 1, json.length, stdout); putchar('\n');
    }
    return 0;
}

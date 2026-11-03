// Exercises Sparkle against temporary test bundles without displaying update UI.
#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface UpdateProbe : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property (copy) NSString *mode;
@property (strong) SPUUpdater *updater;
@end

@implementation UpdateProbe
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); exit(2); }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    acknowledgement();
    [self updater:self.updater didAbortWithError:error];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); puts("INSTALLED"); exit(0); }
- (void)dismissUpdateInstallation {}
- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater { return NO; }
- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item {
    if ([self.mode isEqual:@"probe"]) { printf("FOUND %s\n", item.versionString.UTF8String); exit(0); }
}
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    NSString *detail = error.description.lowercaseString;
    fprintf(stderr, "Sparkle: %s\n", error.description.UTF8String);
    if ([self.mode hasPrefix:@"reject"] && [detail containsString:@"signature"]) { puts("REJECTED_SIGNATURE"); exit(0); }
    exit(1);
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        NSBundle *host = [NSBundle bundleWithPath:@(argv[1])];
        if (!host) return 2;
        UpdateProbe *probe = [UpdateProbe new];
        probe.mode = @(argv[2]);
        probe.updater = [[SPUUpdater alloc] initWithHostBundle:host applicationBundle:host userDriver:probe delegate:probe];
        NSError *error = nil;
        if (![probe.updater startUpdater:&error]) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
        if ([probe.mode isEqual:@"install"] || [probe.mode isEqual:@"reject-archive"]) [probe.updater checkForUpdates];
        else [probe.updater checkForUpdateInformation];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ fputs("Update probe timed out\n", stderr); exit(3); });
        [NSApp run];
    }
    return 0;
}

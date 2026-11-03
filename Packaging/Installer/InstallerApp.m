#import <Cocoa/Cocoa.h>
#import <unistd.h>
#include <stdio.h>
#include <string.h>

@interface FOInstaller : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property (strong) NSWindow *window;
@property (strong) NSButton *installButton;
@property (strong) NSButton *cancelButton;
@property (strong) NSTextField *status;
@property (strong) NSProgressIndicator *progress;
@property (strong) NSTask *task;
@property BOOL installing;
@property BOOL installed;
@end

static NSURL *Resource(NSString *name, NSString *extension) {
    return [NSBundle.mainBundle URLForResource:name withExtension:extension];
}

@implementation FOInstaller
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 650)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Install FlickOff";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    NSView *content = self.window.contentView;
    NSImageView *icon = [[NSImageView alloc] initWithFrame:NSMakeRect(26, 552, 72, 72)];
    icon.image = [NSImage imageNamed:NSImageNameApplicationIcon];
    [content addSubview:icon];
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSTextField *title = [NSTextField labelWithString:[@"FlickOff " stringByAppendingString:version]];
    title.frame = NSMakeRect(112, 590, 460, 34);
    title.font = [NSFont boldSystemFontOfSize:26];
    [content addSubview:title];
    NSTextField *tagline = [NSTextField labelWithString:@"Keep your Mac. Lose the flicker."];
    tagline.frame = NSMakeRect(112, 560, 460, 24);
    tagline.font = [NSFont systemFontOfSize:15];
    tagline.textColor = NSColor.secondaryLabelColor;
    [content addSubview:tagline];
    NSTextField *intro = [NSTextField wrappingLabelWithString:@"Install FlickOff in Applications. An existing installation will be updated and your settings kept."];
    intro.frame = NSMakeRect(28, 506, 544, 40);
    [content addSubview:intro];
    NSTextField *licenseTitle = [NSTextField labelWithString:@"License agreement"];
    licenseTitle.font = [NSFont boldSystemFontOfSize:13];
    licenseTitle.frame = NSMakeRect(28, 474, 544, 22);
    [content addSubview:licenseTitle];
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28, 184, 544, 284)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *license = [[NSTextView alloc] initWithFrame:scroll.contentView.bounds];
    license.editable = NO;
    license.selectable = YES;
    license.font = [NSFont systemFontOfSize:12];
    license.textContainerInset = NSMakeSize(10, 10);
    license.verticallyResizable = YES;
    license.horizontallyResizable = NO;
    license.autoresizingMask = NSViewWidthSizable;
    license.textContainer.widthTracksTextView = YES;
    NSURL *licenseURL = Resource(@"license", @"txt");
    license.string = licenseURL ? ([NSString stringWithContentsOfURL:licenseURL encoding:NSUTF8StringEncoding error:NULL] ?: @"") : @"";
    scroll.documentView = license;
    [content addSubview:scroll];
    NSTextField *terms = [NSTextField wrappingLabelWithString:@"Noncommercial use is free. Commercial use requires a separate paid license. Agree and Install accepts these terms and begins installation."];
    terms.frame = NSMakeRect(28, 128, 544, 44);
    terms.font = [NSFont systemFontOfSize:12];
    [content addSubview:terms];
    NSTextField *defaults = [NSTextField wrappingLabelWithString:@"FlickOff opens after installation. Launch at login and automatic update checks are enabled for new installations; existing choices are preserved."];
    defaults.frame = NSMakeRect(28, 76, 544, 42);
    defaults.font = [NSFont systemFontOfSize:11];
    defaults.textColor = NSColor.secondaryLabelColor;
    [content addSubview:defaults];
    self.status = [NSTextField wrappingLabelWithString:@""];
    self.status.frame = NSMakeRect(48, 18, 286, 45);
    self.status.font = [NSFont systemFontOfSize:11];
    [content addSubview:self.status];
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(28, 34, 16, 16)];
    self.progress.style = NSProgressIndicatorStyleSpinning;
    self.progress.displayedWhenStopped = NO;
    [content addSubview:self.progress];
    self.cancelButton = [NSButton buttonWithTitle:@"Cancel" target:self action:@selector(close:)];
    self.cancelButton.frame = NSMakeRect(340, 24, 82, 34);
    self.cancelButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.cancelButton];
    self.installButton = [NSButton buttonWithTitle:@"Agree and Install" target:self action:@selector(install:)];
    self.installButton.frame = NSMakeRect(428, 24, 150, 34);
    self.installButton.bezelStyle = NSBezelStyleRounded;
    self.installButton.keyEquivalent = @"\r";
    self.installButton.enabled = license.string.length > 0 && Resource(@"FlickOff", @"pkg") && Resource(@"install", @"applescript");
    [content addSubview:self.installButton];
    if (!self.installButton.enabled) self.status.stringValue = @"Installer files are missing. Download it again.";
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)install:(id)sender {
    if (self.installed) { [NSApp terminate:nil]; return; }
    if (self.installing) return;
    self.installing = YES;
    self.installButton.enabled = NO;
    self.cancelButton.enabled = NO;
    self.status.textColor = NSColor.secondaryLabelColor;
    self.status.stringValue = @"Confirm the macOS administrator prompt to install FlickOff.";
    [self.progress startAnimation:nil];
    NSURL *script = Resource(@"install", @"applescript");
    NSURL *package = Resource(@"FlickOff", @"pkg");
    self.task = [NSTask new];
    self.task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    self.task.arguments = @[script.path, package.path];
    self.task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    NSPipe *errors = [NSPipe pipe];
    self.task.standardError = errors;
    __weak FOInstaller *weakSelf = self;
    self.task.terminationHandler = ^(NSTask *task) {
        NSData *data = [errors.fileHandleForReading readDataToEndOfFile];
        NSString *error = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        dispatch_async(dispatch_get_main_queue(), ^{
            FOInstaller *self = weakSelf;
            if (!self) return;
            self.installing = NO;
            [self.progress stopAnimation:nil];
            self.cancelButton.enabled = YES;
            self.installButton.enabled = YES;
            if (task.terminationStatus == 0) {
                self.installed = YES;
                self.status.textColor = NSColor.systemGreenColor;
                self.status.stringValue = @"Installed. Find FlickOff in your menu bar.";
                self.installButton.title = @"Done";
                self.cancelButton.hidden = YES;
            } else {
                self.status.textColor = NSColor.systemRedColor;
                self.status.stringValue = [error containsString:@"-128"]
                    ? @"Installation cancelled. You can try again."
                    : @"Installation failed. Check available disk space and administrator access, then retry.";
                self.installButton.title = @"Try Again";
            }
            self.task = nil;
        });
    };
    NSError *error = nil;
    if (![self.task launchAndReturnError:&error]) {
        self.installing = NO;
        [self.progress stopAnimation:nil];
        self.installButton.enabled = YES;
        self.cancelButton.enabled = YES;
        self.status.stringValue = @"Could not start the macOS installer. Please try again.";
        self.task = nil;
    }
}
- (void)close:(id)sender { if (!self.installing) [NSApp terminate:nil]; }
- (BOOL)windowShouldClose:(NSWindow *)sender { return !self.installing; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return self.installing ? NSTerminateCancel : NSTerminateNow;
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
            BOOL valid = Resource(@"FlickOff", @"pkg") && Resource(@"license", @"txt") && Resource(@"install", @"applescript");
            puts(valid ? "Installer resources: valid" : "Installer resources: missing");
            return valid ? 0 : 1;
        }
        if (argc != 1 || geteuid() == 0) return 2;
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSMenu *menu = [NSMenu new];
        NSMenuItem *applicationItem = [NSMenuItem new];
        NSMenu *applicationMenu = [[NSMenu alloc] initWithTitle:@"FlickOff Installer"];
        [applicationMenu addItemWithTitle:@"Quit FlickOff Installer" action:@selector(terminate:) keyEquivalent:@"q"];
        applicationItem.submenu = applicationMenu;
        [menu addItem:applicationItem];
        app.mainMenu = menu;
        __attribute__((objc_precise_lifetime)) FOInstaller *delegate = [FOInstaller new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}

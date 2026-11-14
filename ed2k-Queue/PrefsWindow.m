//
//  PrefsWindow.m
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "PrefsWindow.h"
#import "AppDelegate.h"
#import "nsextensions.h"

static NSString *const kPwdKey = @"ed2k-pwd";

@implementation PrefsWindow

@synthesize host, port, username, command, password, magnetCommand;

static NSString *str(id v)
{
    return [v isKindOfClass:[NSString class]] ? v : @"";
}

#pragma mark - Layout

static NSTextField *makeLabel(NSString *title)
{
    NSTextField *l = [NSTextField labelWithString:title];
    [l setAlignment:NSTextAlignmentRight];
    return l;
}

static NSTextField *makeHeader(NSString *title)
{
    NSTextField *l = [NSTextField labelWithString:title];
    [l setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
    return l;
}

static NSTextField *makeHint(NSString *title)
{
    NSTextField *l = [NSTextField wrappingLabelWithString:title];
    [l setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [l setTextColor:[NSColor secondaryLabelColor]];
    return l;
}

static NSTextField *makeField(NSString *placeholder)
{
    NSTextField *f = [NSTextField textFieldWithString:@""];
    [f setPlaceholderString:placeholder];
    [[f cell] setScrollable:YES];
    [[f cell] setUsesSingleLineMode:YES];
    return f;
}

// Builds the whole form with auto layout: the window adapts to the control
// metrics of the running macOS version (macOS 26 controls are taller).
- (void)buildForm
{
    NSView *content = [[self window] contentView];

    NSTextField *intro = [NSTextField wrappingLabelWithString:
        @"Insert here the details of the Linux/macOS SSH machine, and the account that will receive your ed2k and magnet links."];

    NSTextField *hostF = makeField(@"my.hostname.it");
    NSTextField *portF = makeField(@"22");
    [portF setStringValue:@"22"];
    [portF setAlignment:NSTextAlignmentCenter];
    NSTextField *userF = makeField(@"myusername");
    NSSecureTextField *pwdF = [[NSSecureTextField alloc] init];
    [pwdF setPlaceholderString:@"mypassword"];
    NSTextField *ed2kF = makeField(@"/Applications/aMule.app/Contents/MacOS/ed2k");
    NSTextField *magnetF = makeField(kDefaultMagnetCommand);

    // Host and port on the same row.
    NSTextField *portLabel = makeLabel(@"Port:");
    NSStackView *hostRow = [NSStackView stackViewWithViews:@[hostF, portLabel, portF]];
    [hostRow setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
    [hostRow setSpacing:8];
    [portF.widthAnchor constraintEqualToConstant:64].active = YES;
    [hostF setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1
                      forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSView *empty = [NSGridCell emptyContentView];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[makeHeader(@"Destination"), empty],
        @[makeLabel(@"Host:"), hostRow],
        @[makeHeader(@"Authentication"), empty],
        @[makeLabel(@"Username:"), userF],
        @[makeLabel(@"Password:"), pwdF],
        @[makeHeader(@"ed2k links"), empty],
        @[makeLabel(@"Command:"), ed2kF],
        @[empty, makeHint(@"Executed on the remote machine with the ed2k link as argument.")],
        @[makeHeader(@"Magnet links"), empty],
        @[makeLabel(@"Command:"), magnetF],
        @[empty, makeHint(@"Executed on the remote machine with the magnet link as argument (default: open).")],
    ]];
    [grid setRowSpacing:8];
    [grid setColumnSpacing:8];
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    [grid setRowAlignment:NSGridRowAlignmentFirstBaseline];

    // Section headers span both columns, with extra space above them.
    for (NSNumber *n in @[@0, @2, @5, @8]) {
        NSInteger r = [n integerValue];
        [grid mergeCellsInHorizontalRange:NSMakeRange(0, 2) verticalRange:NSMakeRange(r, 1)];
        [grid cellAtColumnIndex:0 rowIndex:r].xPlacement = NSGridCellPlacementLeading;
        if (r > 0)
            [grid rowAtIndex:r].topPadding = 10;
    }

    for (NSView *v in @[intro, grid]) {
        [v setTranslatesAutoresizingMaskIntoConstraints:NO];
        [content addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [intro.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [intro.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [intro.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.topAnchor constraintEqualToAnchor:intro.bottomAnchor constant:12],
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [content.widthAnchor constraintEqualToConstant:520],
    ]];

    // Assign the (weak) outlets now that the views are retained by the hierarchy.
    host = hostF;
    port = portF;
    username = userF;
    password = pwdF;
    command = ed2kF;
    magnetCommand = magnetF;

    // Tab order.
    [hostF setNextKeyView:portF];
    [portF setNextKeyView:userF];
    [userF setNextKeyView:pwdF];
    [pwdF setNextKeyView:ed2kF];
    [ed2kF setNextKeyView:magnetF];
    [magnetF setNextKeyView:hostF];
    [[self window] setInitialFirstResponder:hostF];

    [content layoutSubtreeIfNeeded];
    [[self window] setContentSize:[content fittingSize]];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    [self buildForm];
    [self reload];
}

- (void)reload
{
    if (![self isWindowLoaded])
        return;

    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:[AppDelegate configFile]];
    NSString *enc = str([dict objectForKey:@"pwd"]);

    [host setStringValue:str([dict objectForKey:@"host"])];
    // keep the default "22" from the xib when no port is configured
    if ([str([dict objectForKey:@"port"]) length] > 0)
        [port setStringValue:[dict objectForKey:@"port"]];
    [command setStringValue:str([dict objectForKey:@"command"])];
    [username setStringValue:str([dict objectForKey:@"user"])];
    [password setStringValue:[enc length] > 0 ? ([enc decrypt:kPwdKey] ?: @"") : @""];

    NSString *mc = str([dict objectForKey:@"magnet_command"]);
    [magnetCommand setStringValue:[mc length] > 0 ? mc : kDefaultMagnetCommand];
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSLog(@"Closing prefs window");

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *folder = [AppDelegate supportFolder];
    if (![fm fileExistsAtPath:folder])
        [fm createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];

    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *mc = [[magnetCommand stringValue] stringByTrimmingCharactersInSet:ws];

    NSDictionary *config = @{
        @"host": [[host stringValue] stringByTrimmingCharactersInSet:ws],
        @"port": [[port stringValue] stringByTrimmingCharactersInSet:ws],
        @"command": [[command stringValue] stringByTrimmingCharactersInSet:ws],
        @"magnet_command": [mc length] > 0 ? mc : kDefaultMagnetCommand,
        @"user": [[username stringValue] stringByTrimmingCharactersInSet:ws],
        @"pwd": [[password stringValue] encrypt:kPwdKey] ?: @"",
    };
    [config writeToFile:[AppDelegate configFile] atomically:YES];

    [NSApp stopModal];
}

@end

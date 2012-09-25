//
//  PrefsWindow.m
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "PrefsWindow.h"
#import "nsextensions.h"

@interface PrefsWindow ()

@end

@implementation PrefsWindow

@synthesize host, port, username, command, password;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *file = @"~/Library/Application Support/ed2kQueue/config";
    file = [file stringByExpandingTildeInPath];
    if ([fileManager fileExistsAtPath:file] == YES) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];
        [host setStringValue:[dict objectForKey:@"host"]];
        [port setStringValue:[dict objectForKey:@"port"]];
        [command setStringValue:[dict objectForKey:@"command"]];
        [username setStringValue:[dict objectForKey:@"user"]];
        [password setStringValue:[[dict objectForKey:@"pwd"] decrypt:@"ed2k-pwd"]];
    }
}

- (void)windowWillClose:(NSNotification *)notification
{
    NSLog(@"Closing prefs window");
    NSString *file = @"~/Library/Application Support/ed2kQueue/config";
    file = [file stringByExpandingTildeInPath];
    
    NSDictionary *config = [NSDictionary dictionaryWithObjectsAndKeys:
                            [host stringValue],@"host",
                            [port stringValue],@"port",
                            [command stringValue],@"command",
                            [username stringValue],@"user",
                            [[password stringValue] encrypt:@"ed2k-pwd"],@"pwd",
                            nil];
    [config writeToFile:file atomically:NO];

    [NSApp stopModal];
}

@end

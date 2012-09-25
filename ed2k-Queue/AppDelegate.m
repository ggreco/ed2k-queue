//
//  AppDelegate.m
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "AppDelegate.h"
#import "nsextensions.h"
#import "MainWindow.h"

@implementation AppDelegate

@synthesize urls, host, port, command, user, pwd;

-(id)init
{
    self = [super init];

    if (self) {
        // handler registration
        NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
        [appleEventManager setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
        
        // loading db & config
        [self load_cfg];
        [self load_db];
    }
    return self;
}

-(void)applicationDidFinishLaunching:(NSNotification *)notification
{    
    // creo la finestra principale
    
    mainWin = [[MainWindow alloc] initWithWindowNibName:@"MainWindow"];
    [mainWin showWindow:nil];
    [[mainWin window] makeMainWindow];
    mainWin.delegate = self;
    [mainWin refresh];
}

-(BOOL)valid_cfg
{
    if (!host || !user || !port || !pwd || !command ||
        [host length] == 0 || [user length] == 0 ||
        [port length] == 0 || [pwd length] == 0 ||
        [command length] == 0)
        return NO;
    
    return YES;
}
-(void)load_cfg
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *file = @"~/Library/Application Support/ed2kQueue/config";
    file = [file stringByExpandingTildeInPath];
    if ([fileManager fileExistsAtPath:file] == YES) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:file];
        host = [dict objectForKey:@"host"];
        port = [dict objectForKey:@"port"];
        command = [dict objectForKey:@"command"];
        user = [dict objectForKey:@"user"];
        pwd = [[dict objectForKey:@"pwd"] decrypt:@"ed2k-pwd"];
    }
    else {
        host = nil;
        port = nil;
        user = nil;
        command = nil;
        pwd = nil;
    }
}
- (void)load_db
{
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSString *file = @"~/Library/Application Support/ed2kQueue/db";
    file = [file stringByExpandingTildeInPath];
    if ([fileManager fileExistsAtPath:file] == YES) {
        urls = [NSMutableArray arrayWithContentsOfFile:file];
    }
    else
        urls = [[NSMutableArray alloc] init];
}


-(void)add_url:(NSString*)url
{
    NSArray *purl = [[url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] componentsSeparatedByString:@"|"];
    
    if ([purl count] > 2 && [[purl objectAtIndex:1] isEqualToString:@"file"]) {
        NSString *filename = [purl objectAtIndex:2];
        for (NSDictionary *d in urls) {
            if ([filename isEqualToString:[d objectForKey:@"filename"]]) {
                NSLog(@"Ignoring already present entry %@", filename);
                return;
            }
        }
        NSLog(@"Adding item %@", filename);
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              filename, @"filename",
                              [purl objectAtIndex:3], @"size",
                              url, @"url",
                              nil
                              ];
        [urls addObject:dict];
        [mainWin refresh];
    }
    else
        NSLog(@"Ignored unsupported URL string %@", url);
}

- (void)handleURLEvent:(NSAppleEventDescriptor*)event withReplyEvent:(NSAppleEventDescriptor*)replyEvent
{
    NSString* url = [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
    NSLog(@"URL da event: %@", url);

    [self add_url:url];
}

-(void)save_all
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSString *folder = @"~/Library/Application Support/ed2kQueue";
    folder = [folder stringByExpandingTildeInPath];
    if ([fileManager fileExistsAtPath:folder] == NO) {
        [fileManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSLog(@"Quitting app, writing %lu records to db", [urls count]);
    [urls writeToFile:[folder stringByAppendingString:@"/db"] atomically:NO];
    NSDictionary *config = [NSDictionary dictionaryWithObjectsAndKeys:
                            host,@"host",
                            port,@"port",
                            command,@"command",
                            user,@"user",
                            [pwd encrypt:@"ed2k-pwd" ],@"pwd",
                            nil];
    [config writeToFile:[folder stringByAppendingString:@"/config"] atomically:NO];
}

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

-(void)applicationWillResignActive:(NSNotification *)notification
{
    NSLog(@"Will resign");
    [self save_all];
}

-(void)applicationWillTerminate:(NSNotification *)notification
{
    NSLog(@"Will terminate");
    [self save_all];
}

- (IBAction)submit_action:(id)sender {
    NSLog(@"Received action from: %@", sender);
    
    if (([sender respondsToSelector:@selector(identifier)] && [[sender identifier] isEqualToString:@"submit"]) ||
        ([sender respondsToSelector:@selector(itemIdentifier)] && [[sender itemIdentifier] isEqualToString:@"submit"]))
    {
        [mainWin send_urls];
    }
    else
        [mainWin open_prefs];
}

@end

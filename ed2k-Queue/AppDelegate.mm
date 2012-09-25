//
//  AppDelegate.m
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "AppDelegate.h"
#import "ssh_conn.h"
#import "PrefsWindow.h"
#import "ProgressPanel.h"

@implementation AppDelegate

@synthesize urls, tableview, host, port, command, user, pwd, progressSheet, view;

-(id)init
{
    NSLog(@"Delegate init");
    self = [super init];

    if (self) {
        // handler registration
        NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
        [appleEventManager setEventHandler:self andSelector:@selector(handleURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
        
        prefsWin = nil;
        progressSheet = nil;
        
        // loading db & config
        [self load_cfg];
        [self load_db];
        
        [tableview reloadData];
    }
    return self;
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
        pwd = [dict objectForKey:@"pwd"];
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
        [tableview reloadData];
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

-(void)open_prefs
{
    NSLog(@"Opening prefs window");
    if (prefsWin == nil)
        prefsWin = [[PrefsWindow alloc] initWithWindowNibName:@"PrefsWindow"];
    
    NSWindow *w = [prefsWin window];
    [NSApp runModalForWindow:w];
    
    //NSLog(@"Modal dialog ended");
    [NSApp endSheet: w];
    [w orderOut:self.tableview.window];
    
    // bisogna ricaricare da disco le variabili
    [self load_cfg];
}

-(void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)rc contextInfo:(void*)ci
{
    [sheet orderOut:self];
}

-(void)send_url_thread
{
    // creating SSH connection
    SSHConn conn([host UTF8String], [port intValue]);
    
    conn.UserAuth([user UTF8String], [pwd UTF8String]);
    
    BOOL ko = NO;
    double prog = 0.0;
    double total = [urls count] + 2.0;
    
    if(conn.Connect()) {
        prog++;
        [self performSelectorOnMainThread:@selector(set_progress_bar:) withObject:[NSNumber numberWithDouble:(prog/total)] waitUntilDone:NO];
        
        std::string result;
        NSLog(@"Connection with %@ established", host);
        for (NSDictionary *d in urls) {
            NSString *url = [d objectForKey:@"url"];
            [progressSheet.label performSelectorOnMainThread:@selector(setStringValue:) withObject:[NSString stringWithFormat:@"Queuing %@", [d objectForKey:@"filename"]] waitUntilDone:NO];
            NSString *cmd_string = [NSString stringWithFormat:@"%@ \"%@\"", command, url];
            result.clear();
            
            if (!conn.Command([cmd_string UTF8String], result)) {
                NSLog(@"Error executing <%@>: %s", cmd_string, conn.Error().c_str());
                ko = YES;
            }
            else {
                NSLog(@"Queuing file %@, cmdline: %@ answer: %s", [d objectForKey:@"filename"], cmd_string, result.c_str());
            }
            prog++;
            
            [self performSelectorOnMainThread:@selector(set_progress_bar:) withObject:[NSNumber numberWithDouble:(prog/total)] waitUntilDone:NO];
        }
        ::sleep(1);
        NSLog(@"Closing connection.");
        conn.Disconnect();
        prog++;
        [progressSheet.label performSelectorOnMainThread:@selector(setStringValue:) withObject:@"Operation completed." waitUntilDone:NO];
        [self performSelectorOnMainThread:@selector(set_progress_bar:) withObject:[NSNumber numberWithDouble:(prog/total)] waitUntilDone:NO];    }
    else {
        NSLog(@"Unable to connect to %@/%@ error %s", host, port, conn.Error().c_str());
        [progressSheet.label performSelectorOnMainThread:@selector(setStringValue:) withObject:[NSString stringWithFormat:@"Unable to connect to %@", host] waitUntilDone:NO];
        ko = YES;
    }
    ::sleep(1);
    [self performSelectorOnMainThread:@selector(send_url_results:) withObject:[NSNumber numberWithBool:ko] waitUntilDone:YES];
}

-(void)set_progress_bar:(NSNumber *)value
{
    [progressSheet.bar setDoubleValue:[progressSheet.bar maxValue] * [value doubleValue]];
}

-(void)send_urls
{
    if ([urls count] == 0) {
         NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"You have to select at least a link with your browser before submitting it to a remote mule!" ];
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
        return;
    }
    
    if (!host || !user || !port || !pwd || !command ||
        [host length] == 0 || [user length] == 0 ||
        [port length] == 0 || [pwd length] == 0 ||
        [command length] == 0) {
        [self open_prefs];
        [self load_cfg];
        
        if (!host || !user || !port || !pwd || !command ||
            [host length] == 0 || [user length] == 0 ||
            [port length] == 0 || [pwd length] == 0 ||
            [command length] == 0)
            return;
    }
    
    
    NSLog(@"Submit %lu urls with host %@ and port %@", [urls count], host, port);
    if (!progressSheet)
        progressSheet = [[ProgressPanel alloc] initWithWindowNibName:@"ProgressPanel"];
    
    [NSApp beginSheet:[progressSheet window] modalForWindow:[view window] modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
    
    
    [progressSheet.label setStringValue:[NSString stringWithFormat:@"Connecting to %@/%@...", host, port]];
    [progressSheet.bar setDoubleValue:0.0];
    [progressSheet.bar startAnimation:self];
    [NSThread detachNewThreadSelector:@selector(send_url_thread) toTarget:self withObject:nil];
}

-(void)send_url_results:(NSNumber *)ko
{
    [progressSheet.bar stopAnimation:self];
    [NSApp endSheet:[progressSheet window]];
    
    NSAlert *alert = [[NSAlert alloc] init];
    
    if ([ko boolValue] == NO) {
        [alert setAlertStyle:NSInformationalAlertStyle];
        [alert setMessageText:[NSString stringWithFormat:@"%lu links submitted correctly to %@", [urls count], host]];
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
        [urls removeAllObjects];
        [tableview reloadData];
    }
    else {
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"Unable to submit your links, check your connection datas"]
        ;
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
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
                            pwd,@"pwd",
                            nil];
    [config writeToFile:[folder stringByAppendingString:@"/config"] atomically:NO];
}

-(void)applicationWillResignActive:(NSNotification *)notification
{
    [self save_all];
}

-(void)applicationWillTerminate:(NSNotification *)notification
{
    [self save_all];
}

- (IBAction)submit_action:(id)sender {
    NSLog(@"Received action from: %@", sender);
    
    if (([sender respondsToSelector:@selector(identifier)] && [[sender identifier] isEqualToString:@"submit"]) ||
        ([sender respondsToSelector:@selector(itemIdentifier)] && [[sender itemIdentifier] isEqualToString:@"submit"]))
    {
        [self send_urls];
    }
    else
        [self open_prefs];
}

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return [self.urls count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary *dict = [self.urls objectAtIndex:row];
    
    if ([[tableColumn identifier] isEqualToString:@"size"])
        return [dict objectForKey:@"size"];
    else
        return [dict objectForKey:@"filename"];
}

-(void)copy:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSIndexSet *rows = [tableview selectedRowIndexes];
    [pb clearContents];
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSDictionary *d = [urls objectAtIndex:idx];
        [contents addObject:[d objectForKey:@"url"]];
    }];
    [pb writeObjects:contents];
}

-(void)cut:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSIndexSet *rows = [tableview selectedRowIndexes];
    [pb clearContents];
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSDictionary *d = [urls objectAtIndex:idx];
        [contents addObject:[d objectForKey:@"url"]];
    }];
    [urls removeObjectsAtIndexes:rows];
    [tableview reloadData];
    [pb writeObjects:contents];
}

-(void)paste:(id)sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSArray *cl = [NSArray arrayWithObjects:[NSURL class],[NSString class],nil];
    NSArray *objects = [pb readObjectsForClasses:cl options:nil];
    
    for (NSString *s in objects)
        [self add_url:s];
}

-(void)delete:(id)sender {
    NSIndexSet *rows = [tableview selectedRowIndexes];

    [urls removeObjectsAtIndexes:rows];
    [tableview reloadData];
}
- (IBAction)abort_send_urls:(id)sender {
}
@end

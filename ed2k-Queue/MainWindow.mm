//
//  MainWindow.m
//  ed2k-Queue
//
//  Created by gabry on 9/25/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import "MainWindow.h"
#import "AppDelegate.h"
#import "ssh_conn.h"
#import "PrefsWindow.h"
#import "ProgressPanel.h"

@interface MainWindow ()

@end

@implementation MainWindow

@synthesize tableview, delegate;

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

-(void)submit_clicked:(id)sender
{
    [self send_urls];
}

-(void)prefs_clicked:(id)sender
{
    [self open_prefs];
}
-(void)refresh
{
    [tableview reloadData];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    NSLog(@"Main window loaded");
    prefsWin = nil;
    progressSheet = nil;
    delegate = nil;
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    [tableview reloadData];
}

-(void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)rc contextInfo:(void*)ci
{
    [sheet orderOut:self];
}

-(void)send_url_thread
{
    // creating SSH connection
    SSHConn conn([delegate.host UTF8String], [delegate.port intValue]);
    
    conn.UserAuth([delegate.user UTF8String], [delegate.pwd UTF8String]);
    
    BOOL ko = NO;
    double prog = 0.0;
    double total = [delegate.urls count] + 2.0;
    
    if(conn.Connect()) {
        prog++;
        [self performSelectorOnMainThread:@selector(set_progress_bar:) withObject:[NSNumber numberWithDouble:(prog/total)] waitUntilDone:NO];
        
        std::string result;
        NSLog(@"Connection with %@ established", delegate.host);
        for (NSDictionary *d in delegate.urls) {
            NSString *url = [d objectForKey:@"url"];
            [progressSheet.label performSelectorOnMainThread:@selector(setStringValue:) withObject:[NSString stringWithFormat:@"Queuing %@", [d objectForKey:@"filename"]] waitUntilDone:NO];
            NSString *cmd_string = [NSString stringWithFormat:@"%@ \"%@\"", delegate.command, url];
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
        NSLog(@"Unable to connect to %@/%@ error %s",
              delegate.host, delegate.port, conn.Error().c_str());
        [progressSheet.label performSelectorOnMainThread:@selector(setStringValue:) withObject:[NSString stringWithFormat:@"Unable to connect to %@", delegate.host] waitUntilDone:NO];
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
    if ([delegate.urls count] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"You have to select at least a link with your browser before submitting it to a remote mule!" ];
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
        return;
    }
    
    if (![delegate valid_cfg]) {
        [self open_prefs];
        [delegate load_cfg];
        
        if (![delegate valid_cfg])
            return;
    }
    
    
    NSLog(@"Submit %lu urls with host %@ and port %@",
          [delegate.urls count], delegate.host, delegate.port);
    if (!progressSheet)
        progressSheet = [[ProgressPanel alloc] initWithWindowNibName:@"ProgressPanel"];
    
    [NSApp beginSheet:[progressSheet window] modalForWindow:[tableview window] modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
    
    
    [progressSheet.label setStringValue:[NSString stringWithFormat:@"Connecting to %@/%@...", delegate.host, delegate.port]];
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
        [alert setMessageText:[NSString stringWithFormat:@"%lu links submitted correctly to %@", [delegate.urls count], delegate.host]];
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
        [delegate.urls removeAllObjects];
        [tableview reloadData];
    }
    else {
        [alert setAlertStyle:NSWarningAlertStyle];
        [alert setMessageText:@"Unable to submit your links, check your connection datas"]
        ;
        [alert beginSheetModalForWindow:[tableview window] modalDelegate:self didEndSelector:nil contextInfo:nil];
    }
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
    [delegate load_cfg];
}


// operazioni standard
-(void)copy:(id)sender {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    NSIndexSet *rows = [tableview selectedRowIndexes];
    [pb clearContents];
    NSMutableArray *contents = [[NSMutableArray alloc] init];
    
    [rows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        NSDictionary *d = [delegate.urls objectAtIndex:idx];
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
        NSDictionary *d = [delegate.urls objectAtIndex:idx];
        [contents addObject:[d objectForKey:@"url"]];
    }];
    [delegate.urls removeObjectsAtIndexes:rows];
    [tableview reloadData];
    [pb writeObjects:contents];
}

-(void)paste:(id)sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSArray *cl = [NSArray arrayWithObjects:[NSURL class],[NSString class],nil];
    NSArray *objects = [pb readObjectsForClasses:cl options:nil];
    
    for (NSString *s in objects)
        [delegate add_url:s];
}

-(void)delete:(id)sender {
    NSIndexSet *rows = [tableview selectedRowIndexes];
    
    [delegate.urls removeObjectsAtIndexes:rows];
    [tableview reloadData];
}

// Tableview interface

-(NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (!delegate)
        return 0;
    
    return [delegate.urls count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    NSDictionary *dict = [delegate.urls objectAtIndex:row];
    
    if ([[tableColumn identifier] isEqualToString:@"size"])
        return [dict objectForKey:@"size"];
    else
        return [dict objectForKey:@"filename"];
}

@end

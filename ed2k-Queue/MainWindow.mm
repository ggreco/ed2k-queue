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
// Set on the main thread when the user stops the operation, polled by the
// worker thread.
@property (atomic) BOOL abortRequested;
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
    childThread = nil;
    [self setupToolbar];
    [tableview reloadData];
}

// On macOS 11+ the default "unified" style puts title and toolbar items on
// a single row, pushing items into the overflow menu on narrow windows. Use
// the expanded style (title above items) and SF Symbols icons.
- (void)setupToolbar
{
    NSWindow *w = [self window];
    w.toolbarStyle = NSWindowToolbarStyleExpanded;
    w.minSize = NSMakeSize(420, 240);

    NSDictionary *symbols = @{ @"submit": @"paperplane",
                               @"prefs": @"gearshape",
                               @"delete": @"trash" };
    for (NSToolbarItem *item in [[w toolbar] items]) {
        NSString *name = [symbols objectForKey:[item itemIdentifier]];
        NSImage *img = name ? [NSImage imageWithSystemSymbolName:name accessibilityDescription:[item label]] : nil;
        if (img)
            [item setImage:img];
    }
}

#pragma mark - Submission

-(void)set_progress:(double)value label:(NSString *)label
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (label)
            [self->progressSheet.label setStringValue:label];
        [self->progressSheet.bar setDoubleValue:[self->progressSheet.bar maxValue] * value];
    });
}

// Runs on a background thread. `job` is an immutable snapshot of the queue
// and of the connection settings, captured on the main thread.
-(void)send_url_thread:(NSDictionary *)job
{
    NSArray *entries = [job objectForKey:@"entries"];
    NSString *hostName = [job objectForKey:@"host"];
    NSString *portStr = [job objectForKey:@"port"];

    SSHConn conn([hostName UTF8String], [portStr intValue]);
    conn.UserAuth([[job objectForKey:@"user"] UTF8String], [[job objectForKey:@"pwd"] UTF8String]);

    NSMutableArray *sent = [NSMutableArray array];
    NSMutableArray *errors = [NSMutableArray array];
    double prog = 0.0;
    double total = [entries count] + 2.0;

    if (conn.Connect()) {
        prog++;
        [self set_progress:prog / total label:nil];

        NSLog(@"Connection with %@ established", hostName);
        for (NSDictionary *d in entries) {
            if (self.abortRequested)
                return;

            NSString *name = [d objectForKey:kEntryFilenameKey];
            NSString *cmd_string = [NSString stringWithFormat:@"%@ %@",
                                    [d objectForKey:@"command"],
                                    [AppDelegate shellQuote:[d objectForKey:kEntryURLKey]]];
            [self set_progress:prog / total label:[NSString stringWithFormat:@"Queuing %@", name]];

            std::string result;
            if (!conn.Command([cmd_string UTF8String], result)) {
                NSString *err = [NSString stringWithUTF8String:conn.Error().c_str()] ?: @"unknown error";
                NSLog(@"Error executing <%@>: %@", cmd_string, err);
                [errors addObject:[NSString stringWithFormat:@"%@: %@", name, err]];
            }
            else {
                NSLog(@"Queued %@, cmdline: %@ answer: %s", name, cmd_string, result.c_str());
                [sent addObject:d];
            }
            prog++;
            [self set_progress:prog / total label:nil];
        }

        NSLog(@"Closing connection.");
        conn.Disconnect();
        prog++;
        [self set_progress:prog / total label:@"Operation completed."];
    }
    else {
        NSString *err = [NSString stringWithUTF8String:conn.Error().c_str()] ?: @"unknown error";
        NSLog(@"Unable to connect to %@:%@ error %@", hostName, portStr, err);
        [self set_progress:0 label:[NSString stringWithFormat:@"Unable to connect to %@", hostName]];
        [errors addObject:[NSString stringWithFormat:@"Unable to connect to %@:%@ (%@)", hostName, portStr, err]];
    }

    // Leave the final status visible for a moment.
    ::sleep(1);
    if (self.abortRequested)
        return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self send_url_results:sent errors:errors host:hostName];
    });
}

-(void)showAlert:(NSString *)message info:(NSString *)info style:(NSAlertStyle)style
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setAlertStyle:style];
    [alert setMessageText:message];
    if (info)
        [alert setInformativeText:info];
    [alert beginSheetModalForWindow:[tableview window] completionHandler:nil];
}

-(void)send_urls
{
    if (childThread)
        return; // already submitting

    if ([delegate.urls count] == 0) {
        [self showAlert:@"You have to select at least a link with your browser before submitting it to a remote machine!"
                   info:nil
                  style:NSAlertStyleWarning];
        return;
    }

    if (![delegate valid_cfg]) {
        [self open_prefs];

        if (![delegate valid_cfg])
            return;
    }

    // Snapshot everything the worker thread needs, so that it never touches
    // mutable state owned by the main thread.
    NSMutableArray *entries = [NSMutableArray array];
    for (NSDictionary *d in delegate.urls) {
        NSMutableDictionary *m = [d mutableCopy];
        [m setObject:[delegate commandForEntry:d] forKey:@"command"];
        [entries addObject:m];
    }
    NSDictionary *job = @{ @"entries": entries,
                           @"host": delegate.host,
                           @"port": delegate.port,
                           @"user": delegate.user,
                           @"pwd": delegate.pwd };

    NSLog(@"Submit %lu urls with host %@ and port %@",
          (unsigned long)[entries count], delegate.host, delegate.port);
    if (!progressSheet)
        progressSheet = [[ProgressPanel alloc] initWithWindowNibName:@"ProgressPanel"];

    self.abortRequested = NO;
    [[tableview window] beginSheet:[progressSheet window] completionHandler:^(NSModalResponse rc) {
        // Sheet closed while the worker is still running: user pressed Stop.
        if (self->childThread) {
            NSLog(@"Detecting send_url abort");
            self.abortRequested = YES;
            self->childThread = nil;
        }
    }];

    [progressSheet.label setStringValue:[NSString stringWithFormat:@"Connecting to %@:%@...", delegate.host, delegate.port]];
    [progressSheet.bar setDoubleValue:0.0];
    [progressSheet.bar startAnimation:self];
    childThread = [[NSThread alloc] initWithTarget:self selector:@selector(send_url_thread:) object:job];
    [childThread start];
}

-(void)send_url_results:(NSArray *)sent errors:(NSArray *)errors host:(NSString *)hostName
{
    childThread = nil;
    [progressSheet.bar stopAnimation:self];
    NSWindow *sheet = [progressSheet window];
    if ([sheet sheetParent])
        [[sheet sheetParent] endSheet:sheet];

    // Remove only the links actually submitted: links may have been added
    // meanwhile, and failed ones are kept for a retry.
    NSMutableSet *sentIDs = [NSMutableSet set];
    for (NSDictionary *d in sent)
        [sentIDs addObject:[d objectForKey:kEntryURLKey]];
    NSIndexSet *done = [delegate.urls indexesOfObjectsPassingTest:^BOOL(NSDictionary *d, NSUInteger idx, BOOL *stop) {
        return [sentIDs containsObject:[d objectForKey:kEntryURLKey]];
    }];
    [delegate.urls removeObjectsAtIndexes:done];
    [tableview reloadData];
    [delegate save_all];

    if ([errors count] == 0) {
        [self showAlert:[NSString stringWithFormat:@"%lu links submitted correctly to %@", (unsigned long)[sent count], hostName]
                   info:nil
                  style:NSAlertStyleInformational];
    }
    else {
        NSString *msg = [sent count] > 0
            ? [NSString stringWithFormat:@"%lu links submitted, %lu failed", (unsigned long)[sent count], (unsigned long)[errors count]]
            : @"Unable to submit your links, check your connection settings";
        [self showAlert:msg info:[errors componentsJoinedByString:@"\n"] style:NSAlertStyleWarning];
    }
}

-(void)open_prefs
{
    NSLog(@"Opening prefs window");
    if (prefsWin == nil)
        prefsWin = [[PrefsWindow alloc] initWithWindowNibName:@"PrefsWindow"];

    NSWindow *w = [prefsWin window];
    [prefsWin reload];
    [w center];
    // PrefsWindow saves the config and calls -stopModal when it closes.
    [NSApp runModalForWindow:w];
    [w orderOut:self];

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
        [contents addObject:[d objectForKey:kEntryURLKey]];
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
        [contents addObject:[d objectForKey:kEntryURLKey]];
    }];
    [delegate.urls removeObjectsAtIndexes:rows];
    [tableview reloadData];
    [pb writeObjects:contents];
}

-(void)paste:(id)sender {
    NSPasteboard* pb = [NSPasteboard generalPasteboard];
    NSArray *cl = [NSArray arrayWithObjects:[NSURL class],[NSString class],nil];
    NSArray *objects = [pb readObjectsForClasses:cl options:nil];
    
    for (id o in objects)
        [delegate add_url:[o isKindOfClass:[NSURL class]] ? [o absoluteString] : o];
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
    if (row < 0 || row >= (NSInteger)[delegate.urls count])
        return nil;

    NSDictionary *dict = [delegate.urls objectAtIndex:row];
    NSString *col = [tableColumn identifier];

    if ([col isEqualToString:@"size"])
        return [MainWindow formatSize:[dict objectForKey:kEntrySizeKey]];
    else if ([col isEqualToString:@"type"])
        return [[dict objectForKey:kEntryTypeKey] isEqualToString:kEntryTypeMagnet] ? @"magnet" : @"ed2k";
    else
        return [dict objectForKey:kEntryFilenameKey];
}

+ (NSString *)formatSize:(NSString *)size
{
    long long bytes = [size longLongValue];
    if (bytes <= 0)
        return @"-";
    return [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile];
}

@end

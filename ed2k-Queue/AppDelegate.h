//
//  AppDelegate.h
//  ed2k-Queue
//
//  Created by gabry on 9/19/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PrefsWindow;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource> {
    PrefsWindow *prefsWin;
}

@property (unsafe_unretained) IBOutlet NSTableView *tableview;
@property (strong) NSString *host, *user, *pwd, *command, *port;
@property (strong) NSMutableArray *urls;
- (IBAction)submit_action:(id)sender;

@end

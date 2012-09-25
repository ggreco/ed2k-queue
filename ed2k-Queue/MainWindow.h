//
//  MainWindow.h
//  ed2k-Queue
//
//  Created by gabry on 9/25/12.
//  Copyright (c) 2012 Gabriele Greco. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PrefsWindow;
@class ProgressPanel;
@class AppDelegate;

@interface MainWindow : NSWindowController <NSTableViewDataSource> {
    PrefsWindow *prefsWin;
    ProgressPanel *progressSheet;
}

@property AppDelegate *delegate;
@property (unsafe_unretained) IBOutlet NSTableView *tableview;

-(void)refresh;
-(void)send_urls;
-(void)open_prefs;


- (IBAction)submit_clicked:(id)sender;
- (IBAction)prefs_clicked:(id)sender;

@end

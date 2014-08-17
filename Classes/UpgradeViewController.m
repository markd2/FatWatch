//
//  UpgradeViewController.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 1/8/10.
//  Copyright 2010 Benjamin Ragheb. All rights reserved.
//

#import "UpgradeViewController.h"
#import "EWDatabase.h"
#import "EatWatchAppDelegate.h"


@interface UpgradeViewController ()
- (void)doUpgrade:(id)nothing;
- (void)didUpgrade;
@end



@implementation UpgradeViewController
{
	EWDatabase *database;
	UIActivityIndicatorView *activityView;
	UIButton *dismissButton;
	UILabel *titleLabel;
}

@synthesize titleLabel;
@synthesize activityView;
@synthesize dismissButton;


- (id)initWithDatabase:(EWDatabase *)db {
    if ((self = [super initWithNibName:@"UpgradeView" bundle:nil])) {
        database = db;
    }
    return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];
	titleLabel.text = NSLocalizedString(@"Upgrading...", @"Upgrade in progress title");
}


- (void)viewDidAppear:(BOOL)animated {
	[NSThread detachNewThreadSelector:@selector(doUpgrade:) toTarget:self withObject:nil];
	[activityView startAnimating];
}


- (void)doUpgrade:(id)nothing {
	@autoreleasepool {
		[database upgrade];
#if TARGET_IPHONE_SIMULATOR
		[NSThread sleepForTimeInterval:5];
#endif
		[self performSelectorOnMainThread:@selector(didUpgrade) withObject:nil waitUntilDone:NO];
	}
}


- (void)didUpgrade {
	titleLabel.text = NSLocalizedString(@"Upgrade Complete", @"Upgrade complete title");
	[activityView stopAnimating];
	dismissButton.hidden = NO;
}


- (IBAction)dismissView {
	[(id)[[UIApplication sharedApplication] delegate] continueLaunchSequence];
}




@end

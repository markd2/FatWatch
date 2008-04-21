//
//  TrendViewController.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 3/29/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Database;

@interface TrendViewController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
	Database *database;
	NSMutableArray *array;
	NSUInteger dbChangeCount;
	UILabel *warningLabel;
	UITableView *tableView;
}

@end

//
//  BRReachability.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 6/21/09.
//  Copyright 2009 Benjamin Ragheb. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>


@interface BRReachability : NSObject
@property (nonatomic,readonly,getter=isMonitoring) BOOL monitoring;
@property (nonatomic,weak) id delegate;
- (void)startMonitoring;
- (void)stopMonitoring;
@end


@protocol BRReachabilityDelegate
- (void)reachability:(BRReachability *)reachability didUpdateFlags:(SCNetworkReachabilityFlags)flags;
@end

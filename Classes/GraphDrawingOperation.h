//
//  GraphDrawingOperation.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 9/4/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "EWDate.h"


typedef struct {
	float minWeight;
	float maxWeight;
	float scaleX;
	float scaleY;
	float gridMinWeight;
	float gridMaxWeight;
	float gridIncrementWeight;
	CGAffineTransform t;
} GraphViewParameters;


@interface GraphDrawingOperation : NSOperation {
	id delegate;
	int index;
	EWMonth month;
	GraphViewParameters *p;
	CGRect bounds;
	UIImage *image;
}
@property (nonatomic,assign) id delegate;
@property (nonatomic) int index;
@property (nonatomic) EWMonth month;
@property (nonatomic) GraphViewParameters *p;
@property (nonatomic) CGRect bounds;
@property (nonatomic,readonly) UIImage *image;
@end


@interface NSObject (GraphDrawingOperationDelegate)
- (void)drawingOperationComplete:(GraphDrawingOperation *)operation;
@end
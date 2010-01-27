//
//  FlagIconViewController.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 1/16/10.
//  Copyright 2010 Benjamin Ragheb. All rights reserved.
//

#import "FlagIconViewController.h"
#import "FlagTabView.h"
#import "EWFlagButton.h"
#import "NSUserDefaults+EWAdditions.h"


#if TARGET_IPHONE_SIMULATOR
#define BOOK_EXERCISE_URL @"http://fatwatchapp.test/app/book-exercise"
#else
#define BOOK_EXERCISE_URL @"http://www.fatwatchapp.com/app/book-exercise"
#endif


@implementation FlagIconViewController


@synthesize flagTabView;
@synthesize iconArea;
@synthesize enableLadderView;
@synthesize disableLadderView;


- (id)init {
    if (self = [super initWithNibName:@"FlagIconView" bundle:nil]) {
		self.title = NSLocalizedString(@"Marks", nil);
		self.hidesBottomBarWhenPushed = YES;
	}
	return self;
}


- (void)viewDidLoad {
    [super viewDidLoad];
	
	if (iconPaths == nil) {
		iconPaths = [[[NSBundle mainBundle] pathsForResourcesOfType:@"png" inDirectory:@"FlagIcons"] copy];
	}
	
	const CGFloat w = CGRectGetWidth(iconArea.bounds);
	const CGFloat h = 18 + 60 * ceilf([iconPaths count] / 5.0f);
	iconView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
	
	int i = 0;
	for (NSString *path in iconPaths) {
		UIImage *image = [UIImage imageWithContentsOfFile:path];
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		button.tag = i;
		button.frame = CGRectMake(18+60*(i%5), 18+60*(i/5), 42, 42);
		[button addTarget:self action:@selector(iconButtonAction:) forControlEvents:UIControlEventTouchUpInside];
		[button setImage:image forState:UIControlStateNormal];
		i++;
		[iconView addSubview:button];
	}

	[iconArea addSubview:iconView];
	[iconArea setContentSize:iconView.bounds.size];
}


- (void)setLowerView:(UIView *)lowerView otherView:(UIView *)otherView {
	[otherView removeFromSuperview];
	if (otherView == iconArea) [lowerView setFrame:otherView.frame];
	[self.view addSubview:lowerView];
}


- (void)showEnableLadderView:(BOOL)show {
	if (show) {
		[iconArea addSubview:enableLadderView];
		CGRect iconViewFrame = iconView.frame;
		iconViewFrame.origin.y = CGRectGetMaxY(enableLadderView.frame);
		iconView.frame = iconViewFrame;
		CGSize contentSize = iconView.bounds.size;
		contentSize.height += CGRectGetHeight(enableLadderView.frame);
		[iconArea setContentSize:contentSize];
	} else {
		[enableLadderView removeFromSuperview];
		[iconView setFrame:iconView.bounds];
		[iconArea setContentSize:iconView.bounds.size];
	}
}


- (void)updateLowerView {
	BOOL ladderEnabled = [[NSUserDefaults standardUserDefaults] isLadderEnabled];
	
	if (flagIndex == 3 && ladderEnabled) {
		[self setLowerView:disableLadderView otherView:iconArea];
	} else {
		[self setLowerView:iconArea otherView:disableLadderView];
		[self showEnableLadderView:(flagIndex == 3 && !ladderEnabled)];
	}
}


- (IBAction)flagButtonAction:(UIButton *)sender {
	int newFlagIndex = (sender.tag % 10);
	if (flagIndex == newFlagIndex) return;
	[flagTabView selectTabAroundRect:[sender frame]];
	contentOffsets[flagIndex] = [iconArea contentOffset];
	flagIndex = newFlagIndex;
	[self updateLowerView];
	[iconArea setContentOffset:contentOffsets[flagIndex]];
}


- (IBAction)useLastFlagForLadder:(UIButton *)sender {
	[[NSUserDefaults standardUserDefaults] setLadderEnabled:YES];
	[EWFlagButton updateIconName:nil forFlagIndex:flagIndex];
	[self updateLowerView];
}


- (IBAction)useLastFlagForIcon:(UIButton *)sender {
	[[NSUserDefaults standardUserDefaults] setLadderEnabled:NO];
	[EWFlagButton updateIconName:nil forFlagIndex:flagIndex];
	[self updateLowerView];
}


- (IBAction)iconButtonAction:(UIButton *)sender {
	NSString *path = [iconPaths objectAtIndex:sender.tag];
	NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
	[EWFlagButton updateIconName:name forFlagIndex:flagIndex];
}


- (IBAction)explainLadder:(UIButton *)sender {
	NSURL *bookURL = [NSURL URLWithString:BOOK_EXERCISE_URL];
	[[UIApplication sharedApplication] openURL:bookURL];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}


- (void)viewDidUnload {
	self.flagTabView = nil;
	self.iconArea = nil;
	self.enableLadderView = nil;
	self.disableLadderView = nil;
}


- (void)dealloc {
	[flagTabView release];
	[iconArea release];
	[enableLadderView release];
	[disableLadderView release];
	[iconPaths release];
    [super dealloc];
}


@end
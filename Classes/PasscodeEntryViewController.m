//
//  PasscodeEntryViewController.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 7/22/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import "PasscodeEntryViewController.h"
#import "EatWatchAppDelegate.h"


enum {
	ControllerModeAuthorize,
	ControllerModeAuthorizeSuccess,
	ControllerModeAuthorizeFailure,
	ControllerModeSetCode,
	ControllerModeVerifyCode,
	ControllerModeVerifySuccess
};


NSString *kPasscodeKey = @"Passcode";


@interface SettingCodeController : PasscodeEntryViewController
@end


@interface AuthorizationController : PasscodeEntryViewController
@end


@interface PasscodeEntryViewController ()
- (void)messageDelayDidEnd:(NSNumber *)shouldDismiss;
@end


@implementation PasscodeEntryViewController
{
	UIImageView *digitViews[4];
}


@synthesize navBar;
@synthesize digitGroupView;
@synthesize promptLabel;
@synthesize smallLabel;
@synthesize digit0View;
@synthesize digit1View;
@synthesize digit2View;
@synthesize digit3View;
@synthesize codeField;


+ (BOOL)authorizationRequired {
	return [[[NSUserDefaults standardUserDefaults] stringForKey:kPasscodeKey] length] == 4;
}


+ (void)removePasscode {
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:kPasscodeKey];
}


+ (PasscodeEntryViewController *)controllerForSettingCode {
	return [[SettingCodeController alloc] init];
}


+ (PasscodeEntryViewController *)controllerForAuthorization {
	return [[AuthorizationController alloc] init];
}


- (id)init {
	return [super initWithNibName:@"PasscodeView" bundle:nil];
}


- (void)viewDidLoad {
	digitViews[0] = digit0View;
	digitViews[1] = digit1View;
	digitViews[2] = digit2View;
	digitViews[3] = digit3View;
	codeField.hidden = YES;
}


- (void)updateDigitViews {
	UIImage *img0 = [UIImage imageNamed:@"Passcode0.png"];
	UIImage *img1 = [UIImage imageNamed:@"Passcode1.png"];
	
	for (NSUInteger i = 0; i < 4; i++) {
		UIImageView *digitView = digitViews[i];
		digitView.image = ([codeField.text length] > i) ? img1 : img0;
	}
}


- (IBAction)codeFieldEditingChanged:(id)sender {
	NSString *code = codeField.text;
	[self updateDigitViews];
	if ([code length] == 4) {
		BOOL dismissView = [self shouldDismissEnteredCode:code];
		[[UIApplication sharedApplication] beginIgnoringInteractionEvents];
		[self performSelector:@selector(messageDelayDidEnd:) 
				   withObject:@(dismissView)
				   afterDelay:0.8];
	}
}


- (void)messageDelayDidEnd:(NSNumber *)shouldDismiss {
	[[UIApplication sharedApplication] endIgnoringInteractionEvents];
	if ([shouldDismiss boolValue]) {
		[self dismissView];
	} else {
		codeField.text = @"";
		[self updateDigitViews];
	}
}


#pragma mark Abstract Methods


- (BOOL)shouldDismissEnteredCode:(NSString *)userCode {
	[self doesNotRecognizeSelector:_cmd];
	return NO;
}

- (void)dismissView {
	[self doesNotRecognizeSelector:_cmd];
}

- (IBAction)cancelAction {
	[self doesNotRecognizeSelector:_cmd];
}


@end


@implementation SettingCodeController
{
	NSString *_newCode;
}


- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.navBar.hidden = NO;
	self.digitGroupView.frame = CGRectMake(0, 88, 320, 79);
	[self.codeField becomeFirstResponder];
}


- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	[self.codeField becomeFirstResponder];
}


- (BOOL)shouldDismissEnteredCode:(NSString *)userCode {
	if (_newCode == nil) {
		_newCode = userCode;
		self.promptLabel.text = NSLocalizedString(@"Re-enter your passcode", @"Passcode re-entry");
		self.smallLabel.hidden = YES;
		return NO;
	}
	
	if ([_newCode isEqualToString:userCode]) {
		[[NSUserDefaults standardUserDefaults] setObject:_newCode forKey:kPasscodeKey];
		self.promptLabel.text = NSLocalizedString(@"Passcode set", @"Passcode set");
		self.smallLabel.hidden = YES;
		return YES;
	}
	
	self.promptLabel.text = NSLocalizedString(@"Enter a passcode", @"Enter a passcode");
	self.smallLabel.hidden = NO;
	self.smallLabel.text = NSLocalizedString(@"Passcodes did not match. Try again.", @"Passcode mismatch");
	_newCode = nil;
	return NO;
}


- (void)dismissView {
	[self dismissViewControllerAnimated:YES completion:nil];
}


- (IBAction)cancelAction {
	[self dismissView];
}


@end


@implementation AuthorizationController
{
	NSUInteger _remainingAttemptCount;
	BOOL _isAuthorized;
}

- (id)init {
	if ((self = [super init])) {
		_remainingAttemptCount = 4;
	}
	return self;
}


- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	self.navBar.hidden = NO;
	UINavigationItem *item = [self.navBar topItem];
	item.leftBarButtonItem = nil;
	item.title = @"FatWatch";
	self.navBar.tintColor = [UIColor colorWithRed:0.894f green:0 blue:0.02f alpha:1];
	self.digitGroupView.frame = CGRectMake(0, 88, 320, 79);
	[self.codeField becomeFirstResponder];
}


- (BOOL)shouldDismissEnteredCode:(NSString *)userCode {
	NSString *secretCode = [[NSUserDefaults standardUserDefaults] stringForKey:kPasscodeKey];
	if ([secretCode isEqualToString:userCode]) {
		self.promptLabel.text = NSLocalizedString(@"Authorized", @"Passcode authorized");
		self.smallLabel.hidden = YES;
		_isAuthorized = YES;
		return YES;
	} else {
		_remainingAttemptCount -= 1;
		self.smallLabel.hidden = NO;
		NSString *format = NSLocalizedString(@"Incorrect. %d attempts remaining.", @"Passcode wrong, count remaining attempts");
		self.smallLabel.text = [NSString stringWithFormat:format, _remainingAttemptCount];
		return (_remainingAttemptCount == 0);
	}
}


- (void)dismissView {
	if (! _isAuthorized) {
		[self.codeField resignFirstResponder];
		self.promptLabel.text = NSLocalizedString(@"Authorization failed", @"Passcode failed");
		self.smallLabel.hidden = YES;
		return;
	}
	[(id)[[UIApplication sharedApplication] delegate] continueLaunchSequence];
}


@end

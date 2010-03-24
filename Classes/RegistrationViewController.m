//
//  RegistrationViewController.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 1/17/10.
//  Copyright 2010 Benjamin Ragheb. All rights reserved.
//

#import "RegistrationViewController.h"
#import "NSUserDefaults+EWAdditions.h"


#if TARGET_IPHONE_SIMULATOR
#define REGISTRATION_URL @"http://fatwatchapp.test/register/"
#else
#define REGISTRATION_URL @"http://www.fatwatchapp.com/register/"
#endif


static RegistrationViewController *gSharedController = nil;


@implementation RegistrationViewController


+ (RegistrationViewController *)sharedController {
	if (gSharedController == nil) {
		gSharedController = [[[RegistrationViewController alloc] init] autorelease];
	}
	return gSharedController;
}


- (id)init {
    if (self = [super initWithNibName:nil bundle:nil]) {
		self.title = NSLocalizedString(@"Product Registration", nil);
		self.hidesBottomBarWhenPushed = YES;
		
		UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
		UIBarButtonItem *activityItem = [[UIBarButtonItem alloc] initWithCustomView:activityView];
		self.navigationItem.rightBarButtonItem = activityItem;
		[activityItem release];
		[activityView release];
    }
    return self;
}


- (void)loadView {
	CGRect frame = CGRectMake(0, 0, 320, 200);
	
	UIView *view = [[UIView alloc] initWithFrame:frame];
	view.autoresizingMask = (UIViewAutoresizingFlexibleWidth |	
							 UIViewAutoresizingFlexibleHeight);

	webView = [[UIWebView alloc] initWithFrame:frame];
	webView.autoresizingMask = (UIViewAutoresizingFlexibleWidth |	
								UIViewAutoresizingFlexibleHeight);
	webView.delegate = self;

	[view addSubview:webView];
	[self setView:view];
	[view release];
}


- (void)viewWillAppear:(BOOL)animated {
	NSURL *url = [NSURL URLWithString:REGISTRATION_URL];
	NSURLRequest *request = [NSURLRequest requestWithURL:url];
	[webView loadRequest:request];
}


- (void)viewDidDisappear:(BOOL)animated {
	[webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
}


- (UIActivityIndicatorView *)activityView {
	return (id)self.navigationItem.rightBarButtonItem.customView;
}


#pragma mark UIWebViewDelegate


- (void)webViewDidStartLoad:(UIWebView *)aWebView {
	[[self activityView] startAnimating];
}


- (void)webViewDidFinishLoad:(UIWebView *)aWebView {
	[[self activityView] stopAnimating];
	if (errorToDisplay) {
		NSString *script = [NSString stringWithFormat:@"setError(\"%@\");", [[errorToDisplay localizedDescription] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]];
		[webView stringByEvaluatingJavaScriptFromString:script];
		[errorToDisplay release];
		errorToDisplay = nil;
	} else {
		NSString *bodyID = [webView stringByEvaluatingJavaScriptFromString:@"document.body.id"];
		if ([@"registrationForm" isEqualToString:bodyID]) {
			[[NSUserDefaults standardUserDefaults] setShowRegistrationReminder:NO];
		}
		else if ([@"registrationComplete" isEqualToString:bodyID]) {
			NSString *keyString = [webView stringByEvaluatingJavaScriptFromString:
								   @"z = [];"
								   @"for (k in registration) { z.push(k); };"
								   @"z.join(\"\\0\");"
								   ];
			NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
			for (NSString *key in [keyString componentsSeparatedByString:@"\0"]) {
				NSString *keyPath = [@"registration." stringByAppendingString:key];
				NSString *eval = [webView stringByEvaluatingJavaScriptFromString:keyPath];
				[info setObject:eval forKey:key];
			}
			[[NSUserDefaults standardUserDefaults] setRegistration:info];
			[info release];
		}
	}
}


- (void)webView:(UIWebView *)aWebView didFailLoadWithError:(NSError *)error {
	[errorToDisplay release];
	errorToDisplay = [error retain];
	NSString *path = [[NSBundle mainBundle] pathForResource:@"RegistrationError" ofType:@"html"];
	NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
	[webView loadRequest:[NSURLRequest requestWithURL:url]];
	[url release];
}


#pragma mark Cleanup


- (void)releaseWebView {
	webView.delegate = nil;
	[webView release];
	webView = nil;
}


- (void)viewDidUnload {
	[self releaseWebView];
}


- (void)dealloc {
	if (gSharedController == self) gSharedController = nil;
	[self releaseWebView];
    [super dealloc];
}


@end

//
//  WebServerDelegate.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 5/17/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import "WebServerDelegate.h"
#import "MonthData.h"
#import "CSVWriter.h"
#import "CSVReader.h"
#import "MicroWebServer.h"
#import "Database.h"
#import "FormDataParser.h"
#import "WeightFormatters.h"
#import "EWGoal.h"


#define HTTP_STATUS_OK 200
#define HTTP_STATUS_NOT_FOUND 404

@interface WebServerDelegate ()
- (NSDateFormatter *)isoDateFormatter;
- (NSDateFormatter *)localDateFormatter;
- (void)handleExport:(MicroWebConnection *)connection;
- (void)handleImport:(MicroWebConnection *)connection;
- (void)performImport;
- (void)sendNotFoundErrorToConnection:(MicroWebConnection *)connection;
- (void)sendPNGResourceNamed:(NSString *)name toConnection:(MicroWebConnection *)connection;
- (void)sendHTMLResourceNamed:(NSString *)name withSubstitutions:(NSDictionary *)substitutions toConnection:(MicroWebConnection *)connection;
@end



@implementation WebServerDelegate


- (void)handleWebConnection:(MicroWebConnection *)connection {
	NSString *path = [[connection requestURL] path];
	
	printf("%s <%s>\n", [[connection requestMethod] UTF8String], [path UTF8String]);
	
	if ([path isEqualToString:@"/"]) {
		UIDevice *device = [UIDevice currentDevice];
		NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
		NSDictionary *subst = [NSDictionary dictionaryWithObjectsAndKeys:
							   [device name], @"__NAME__",
							   version, @"__VERSION__",
							   nil];
		[self sendHTMLResourceNamed:@"home" withSubstitutions:subst toConnection:connection];
		return;
	}
	
	if ([path hasPrefix:@"/export/"]) {
		[self handleExport:connection];
		return;
	}
	
	if ([path isEqualToString:@"/import"]) {
		[self handleImport:connection];
		return;
	}
	
	if ([path isEqualToString:@"/icon.png"]) {
		[self sendPNGResourceNamed:@"Icon" toConnection:connection];
		return;
	}
	
	// handle robots.txt, favicon.ico
	[self sendNotFoundErrorToConnection:connection];
}



- (void)sendNotFoundErrorToConnection:(MicroWebConnection *)connection {
	[connection setResponseStatus:HTTP_STATUS_NOT_FOUND];
	[connection setValue:@"text/plain" forResponseHeader:@"Content-Type"];
	[connection setResponseBodyString:@"Resource Not Found"];
}


- (void)sendPNGResourceNamed:(NSString *)name toConnection:(MicroWebConnection *)connection {
	NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"_png"];
	
	if (path == nil) {
		[self sendNotFoundErrorToConnection:connection];
		return;
	}
	
	[connection setResponseStatus:HTTP_STATUS_OK];
	[connection setValue:@"image/png" forResponseHeader:@"Content-Type"];
	[connection setResponseBodyData:[NSData dataWithContentsOfFile:path]];
}


- (void)sendHTMLResourceNamed:(NSString *)name withSubstitutions:(NSDictionary *)substitutions toConnection:(MicroWebConnection *)connection {
	NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"html"];

	if (path == nil) {
		[self sendNotFoundErrorToConnection:connection];
		return;
	}
	
	NSMutableString *text = [[NSMutableString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];

	for (NSString *key in [substitutions allKeys]) {
		[text replaceOccurrencesOfString:key
							  withString:[substitutions objectForKey:key]
								 options:0
								   range:NSMakeRange(0, [text length])];
	}
	
	[connection setResponseStatus:HTTP_STATUS_OK];
	[connection setValue:@"text/html; charset=utf-8" forResponseHeader:@"Content-Type"];
	[connection setResponseBodyData:[text dataUsingEncoding:NSUTF8StringEncoding]];
	
	[text release];
}


- (NSDateFormatter *)isoDateFormatter {
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	[formatter setDateFormat:@"y-MM-dd"];
	return [formatter autorelease];
}


- (NSDateFormatter *)localDateFormatter {
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setFormatterBehavior:NSDateFormatterBehavior10_4];
	[formatter setDateStyle:NSDateFormatterShortStyle];
	[formatter setTimeStyle:NSDateFormatterNoStyle];
	return [formatter autorelease];
}


- (void)handleExport:(MicroWebConnection *)connection {
	CSVWriter *writer = [[CSVWriter alloc] init];
	writer.floatFormatter = [WeightFormatters exportWeightFormatter];

	[writer addString:@"Date"];
	[writer addString:@"Weight"];
	[writer addString:@"Checkmark"];
	[writer addString:@"Note"];
	[writer endRow];
	
	NSDateFormatter *formatter = [self isoDateFormatter];
	
	Database *db = [Database sharedDatabase];
	EWMonth month;
	for (month = db.earliestMonth; month <= db.latestMonth; month += 1) {
		MonthData *md = [db dataForMonth:month];
		EWDay day;
		for (day = 1; day <= 31; day++) {
			float scaleWeight = [md scaleWeightOnDay:day];
			NSString *note = [md noteOnDay:day];
			BOOL flag = [md isFlaggedOnDay:day];
			if (scaleWeight > 0 || note != nil || flag) {
				[writer addString:[formatter stringFromDate:[md dateOnDay:day]]];
				[writer addFloat:scaleWeight];
				[writer addBoolean:flag];
				[writer addString:note];
				[writer endRow];
			}
		}
	}
	
	[connection setResponseStatus:HTTP_STATUS_OK];
	// text/csv is technically correct, but the user wants to download, not view, the file
	[connection setValue:@"application/octet-stream" forResponseHeader:@"Content-Type"];
	[connection setResponseBodyData:[writer data]];
	[writer release];
	return;
}


- (void)handleImport:(MicroWebConnection *)connection {
	if (importData != nil) {
		[self sendHTMLResourceNamed:@"importPending" withSubstitutions:nil toConnection:connection];
		return;
	}
	
	FormDataParser *form = [[FormDataParser alloc] initWithConnection:connection];

	importData = [[form dataForKey:@"filedata"] retain];
	importReplace = [[form stringForKey:@"how"] isEqualToString:@"replace"];
	importEncoding = [[form stringForKey:@"encoding"] intValue];
	
	if (importData == nil) {
		[self sendHTMLResourceNamed:@"importNoData" withSubstitutions:nil toConnection:connection];
		return;
	}
		
	NSString *alertTitle = NSLocalizedString(@"PRE_IMPORT_TITLE", nil);
	NSString *alertText = NSLocalizedString(@"PRE_IMPORT_TEXT", nil);
	NSString *cancelTitle = NSLocalizedString(@"CANCEL_BUTTON", nil);
	NSString *replaceTitle = NSLocalizedString(@"REPLACE_BUTTON", nil);
	NSString *mergeTitle = NSLocalizedString(@"MERGE_BUTTON", nil);
	
	NSString *saveButtonTitle = importReplace ? replaceTitle : mergeTitle;

	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:alertTitle message:alertText delegate:self cancelButtonTitle:cancelTitle otherButtonTitles:saveButtonTitle, nil];
	[alert show];
	[alert release];
	
	[self sendHTMLResourceNamed:@"importAccepted" withSubstitutions:nil toConnection:connection];
}


- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 1) {
		[self performImport];
	}
	[importData release];
	importData = nil;
}


- (void)performImport {
	const Database *db = [Database sharedDatabase];

	if (importReplace) {
		[db deleteWeights];
		[EWGoal deleteGoal];
	}
	
	NSUInteger lineCount = 0, importCount = 0;
	CSVReader *reader = [[CSVReader alloc] initWithData:importData encoding:importEncoding];
	reader.floatFormatter = [WeightFormatters exportWeightFormatter];
	
	NSDateFormatter *isoDateFormatter = [self isoDateFormatter];
	NSDateFormatter *localDateFormatter = [self localDateFormatter];
	
	while ([reader nextRow]) {
		lineCount += 1;
		NSString *dateString = [reader readString];
		if (dateString == nil) continue;
		
		NSDate *date = [isoDateFormatter dateFromString:dateString];
		if (date == nil) {
			date = [localDateFormatter dateFromString:dateString];
		}
		if (date == nil) continue;

		float scaleWeight = [reader readFloat];
		BOOL flag = [reader readBoolean];
		NSString *note = [reader readString];
		
		if (scaleWeight > 0 || note != nil || flag) {
			EWMonthDay monthday = EWMonthDayFromDate(date);
			MonthData *md = [db dataForMonth:EWMonthDayGetMonth(monthday)];
			[md setScaleWeight:scaleWeight flag:flag note:note onDay:EWMonthDayGetDay(monthday)];
			importCount += 1;
		}
	}
	
	[reader release];
	[db commitChanges];

	NSString *msg;
	
	if (importCount > 0) {
		NSString *msgFormat = NSLocalizedString(@"POST_IMPORT_TEXT_COUNT", nil);
		msg = [NSString stringWithFormat:msgFormat, importCount, (lineCount - importCount)];
	} else {
		NSString *msgFormat = NSLocalizedString(@"POST_IMPORT_TEXT_NONE", nil);
		msg = [NSString stringWithFormat:msgFormat, lineCount];
	}
	
	NSString *alertTitle = NSLocalizedString(@"POST_IMPORT_TITLE", nil);
	NSString *okTitle = NSLocalizedString(@"OK_BUTTON", nil);
	
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:alertTitle message:msg delegate:nil cancelButtonTitle:nil otherButtonTitles:okTitle, nil];
	[alert show];
	[alert release];
}


@end

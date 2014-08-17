//
//  EWDateFormatter.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 2/10/10.
//  Copyright 2010 Benjamin Ragheb. All rights reserved.
//

#import "EWDateFormatter.h"
#import "EWDate.h"


@implementation EWDateFormatter
{
	NSDateFormatter *realFormatter;
}

+ (NSFormatter *)formatterWithDateFormat:(NSString *)format {
	if ([format isEqualToString:@"y-MM-dd"]) {
		return [[EWISODateFormatter alloc] init];
	} else {
		return [[EWDateFormatter alloc] initWithDateFormat:format];
	}
}

- (id)initWithDateFormat:(NSString *)format {
	if ((self = [super init])) {
		realFormatter = [[NSDateFormatter alloc] init];
		[realFormatter setDateFormat:format];
	}
	return self;
}

- (NSString *)stringForObjectValue:(id)obj {
	NSDate *date = EWDateFromMonthDay([obj intValue]);
	return [realFormatter stringFromDate:date];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error {
	NSDate *date = nil;
	if ([realFormatter getObjectValue:&date forString:string errorDescription:error]) {
		*obj = @(EWMonthDayFromDate(date));
		return YES;
	}
	return NO;
}


@end


@implementation EWISODateFormatter

- (NSString *)stringForObjectValue:(id)obj {
	EWMonthDay md = [obj intValue];
	EWMonth m = EWMonthDayGetMonth(md);
	EWDay d = EWMonthDayGetDay(md);
	int year = (24012 + m) / 12; 	// 0 = 2001-01
	int m0 = (m % 12) + 1;
	if (m0 < 1) m0 += 12;
	return [NSString stringWithFormat:@"%04d-%02d-%02d", year, m0, d];
}

- (BOOL)getObjectValue:(id *)obj forString:(NSString *)string errorDescription:(NSString **)error {
	NSScanner *scanner = [[NSScanner alloc] initWithString:string];
	int year, month, day;
	
	NSCharacterSet *digitSet = [NSCharacterSet decimalDigitCharacterSet];
	
	BOOL success = ([scanner scanInt:&year] &&
					[scanner scanUpToCharactersFromSet:digitSet intoString:nil] &&
					[scanner scanInt:&month] &&
					[scanner scanUpToCharactersFromSet:digitSet intoString:nil] &&
					[scanner scanInt:&day]);

	if (success) {
		EWMonth m = ((year - 2001) * 12) + (month - 1);
		*obj = @(EWMonthDayMake(m, day));
	} else {
		*error = [NSError errorWithDomain:@"EWDate" code:1 userInfo:nil];
	}

	return success;
}

@end

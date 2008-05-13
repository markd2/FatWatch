//
//  WeightMonth.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 4/6/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import "/usr/include/sqlite3.h"
#import "MonthData.h"
#import "Database.h"

#define SetBitValueAtIndex(b, v, i) if (v) { b |= (1 << (i)); } else { b &= ~(1 << (i)); }

static sqlite3_stmt *insert_stmt = nil;
static sqlite3_stmt *data_for_month_stmt = nil;

@implementation MonthData

+ (void)finalizeStatements
{
	if (insert_stmt) sqlite3_finalize(insert_stmt);
	if (data_for_month_stmt) sqlite3_finalize(data_for_month_stmt);
}

- (id)initWithMonth:(EWMonth)m
{
	if ([super init]) {
		month = m;
		
		measuredWeights = calloc(31, sizeof(float));
		trendWeights = calloc(31, sizeof(float));
		flagBits = 0;
		notesArray = [[NSMutableArray alloc] initWithCapacity:31];
		for (int i = 0; i < 31; i++) {
			[notesArray addObject:[NSNull null]];
		}
		dirtyBits = 0;
		
		if (data_for_month_stmt == nil) {
			data_for_month_stmt = [[Database sharedDatabase] statementFromSQL:"SELECT * FROM weight WHERE monthday > ? AND monthday < ?"];
		}
		sqlite3_bind_int(data_for_month_stmt, 1, EWMonthDayMake(m, 0));
		sqlite3_bind_int(data_for_month_stmt, 2, EWMonthDayMake(m+1, 0));
		while (sqlite3_step(data_for_month_stmt) == SQLITE_ROW) {
			EWDay day = EWMonthDayGetDay(sqlite3_column_int(data_for_month_stmt, kMonthDayColumnIndex));
			int i = day - 1;
			
			measuredWeights[i] = sqlite3_column_double(data_for_month_stmt, kMeasuredValueColumnIndex);
			trendWeights[i] = sqlite3_column_double(data_for_month_stmt, kTrendValueColumnIndex);
			SetBitValueAtIndex(flagBits, (sqlite3_column_int(data_for_month_stmt, kFlagColumnIndex) != 0), i);

			char *noteStr = (char *)sqlite3_column_text(data_for_month_stmt, kNoteColumnIndex);
			if (noteStr) {
				[notesArray replaceObjectAtIndex:i withObject:[NSString stringWithUTF8String:noteStr]];
			}
		}
		sqlite3_reset(data_for_month_stmt);
		
	}
	return self;
}

- (void)dealloc {
	free(measuredWeights);
	free(trendWeights);
	[notesArray release];
	[super dealloc];
}

- (NSDate *)dateOnDay:(EWDay)day
{
	return NSDateFromEWMonthAndDay(month, day);
}

- (float)measuredWeightOnDay:(EWDay)day
{
	return measuredWeights[day - 1];
}

- (float)trendWeightOnDay:(EWDay)day
{
	return trendWeights[day - 1];
}

- (BOOL)isFlaggedOnDay:(EWDay)day
{
	int i = day - 1;
	return (flagBits & (1 << i)) != 0;
}

- (NSString *)noteOnDay:(EWDay)day
{
	id note = [notesArray objectAtIndex:(day - 1)];
	return (note == [NSNull null] ? nil : note);
}

// Finds the trend value for the first day with data preceding the given day.
// If there is no earlier data, returns weight on the given day.
- (float)inputTrendOnDay:(EWDay)day
{
	// First, search backwards through this month for a trend value.
	
	int i;
	
	for (i = (day - 1) - 1; i >= 0; i--) {
		float trend = trendWeights[i];
		if (trend != 0) return trend;
	}
	
	// If none is found, find previous month with data.
	
	MonthData *earlierMonthData = [[Database sharedDatabase] dataForMonthBefore:month];
	if (earlierMonthData) {
		return [earlierMonthData inputTrendOnDay:31];
	}
	
	return measuredWeights[day - 1];
}

- (void)updateTrendStartingOnDay:(EWDay)day inputTrend:(float)inputTrend
{
	int i;
	float previousTrend = inputTrend;
	for (i = (day - 1); i <= 31; i++) {
		if (measuredWeights[i] != 0) {
			trendWeights[i] = previousTrend + (0.1f * (measuredWeights[i] - previousTrend));
			SetBitValueAtIndex(dirtyBits, 1, i);
			previousTrend = trendWeights[i];
		}
	}
	// TODO: convert to loop to avoid possible stack overflow
	[[[Database sharedDatabase] dataForMonthAfter:month] updateTrendStartingOnDay:1 inputTrend:previousTrend];
}

- (void)setMeasuredWeight:(float)weight flag:(BOOL)flag note:(NSString *)note onDay:(EWDay)day
{
	int i = day - 1;
	measuredWeights[i] = weight;
	SetBitValueAtIndex(flagBits, flag, i);
	id object = (note != nil) ? (id)note : (id)[NSNull null];
	[notesArray replaceObjectAtIndex:i withObject:object];
	SetBitValueAtIndex(dirtyBits, 1, i);
	
	// find next earliest trend value
	float previousTrend = [self inputTrendOnDay:day];
	
	// update this and future trend values
	[self updateTrendStartingOnDay:day inputTrend:previousTrend];
}

- (BOOL)commitChanges
{
	if (dirtyBits == 0) return NO;
	
	if (insert_stmt == nil) {
		insert_stmt = [[Database sharedDatabase] statementFromSQL:"INSERT OR REPLACE INTO weight VALUES(?,?,?,?,?)"];
	}
	
	int i = 0;
	unsigned int bits = dirtyBits;
	while (bits) {
		if (bits & 1 != 0) {
			EWDay day = i + 1;

			// we have to add 1 to offsets because columns are 0-based and bindings are 1-based
			sqlite3_bind_int(insert_stmt, kMonthDayColumnIndex + 1, EWMonthDayMake(month, day));
			if (measuredWeights[i] == 0) {
				sqlite3_bind_null(insert_stmt, kMeasuredValueColumnIndex + 1);
				sqlite3_bind_null(insert_stmt, kTrendValueColumnIndex + 1);
			} else {
				sqlite3_bind_double(insert_stmt, kMeasuredValueColumnIndex + 1, measuredWeights[i]);
				sqlite3_bind_double(insert_stmt, kTrendValueColumnIndex + 1, trendWeights[i]);
			}
			sqlite3_bind_int(insert_stmt, kFlagColumnIndex + 1, [self isFlaggedOnDay:day]);
			id note = [notesArray objectAtIndex:i];
			if (note != [NSNull null]) {
				sqlite3_bind_text(insert_stmt, kNoteColumnIndex + 1, [note UTF8String], -1, SQLITE_STATIC);
			} else {
				sqlite3_bind_null(insert_stmt, kNoteColumnIndex + 1);
			}
			
			int retcode = sqlite3_step(insert_stmt);
			sqlite3_reset(insert_stmt);
			NSAssert1(retcode == SQLITE_DONE, @"INSERT returned code %d", retcode);
		}
		i++;
		bits >>= 1;
	}
	
	dirtyBits = 0;
	return YES;
}

@end
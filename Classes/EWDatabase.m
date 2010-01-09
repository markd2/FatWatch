//
//  EWDatabase.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 12/9/09.
//  Copyright 2009 Benjamin Ragheb. All rights reserved.
//

#import "EWDatabase.h"
#import "EWDBMonth.h"
#import "SQLiteDatabase.h"
#import "SQLiteStatement.h"
#import "EWEnergyEquivalent.h"


NSString * const EWDatabaseDidChangeNotification = @"EWDatabaseDidChange";


static EWDatabase *gSharedDB = nil;


@interface EWDatabase ()
- (void)didOpen;
- (void)updateTrendValues;
- (void)flushCache;
- (void)executeSQLNamed:(NSString *)name;
- (int)intValueForMetaName:(NSString *)name;
@end


@implementation EWDatabase


@synthesize earliestMonth;
@synthesize latestMonth;


+ (EWDatabase *)sharedDatabase {
	return gSharedDB;
}


+ (void)setSharedDatabase:(EWDatabase *)db {
	NSAssert(gSharedDB == nil, @"Cannot set shared DB twice!");
	gSharedDB = [db retain];
}


- (id)init {
	if ([super init]) {
		monthCacheLock = [[NSLock alloc] init];
		[monthCacheLock setName:@"monthCacheLock"];
		monthCache = [[NSMutableDictionary alloc] init];
	}
	return self;
}


- (id)initWithFile:(NSString *)path {
	if (self = [self init]) {
		db = [[SQLiteDatabase alloc] initWithFile:path];
		[self didOpen];
	}
	return self;
}


- (id)initWithSQL:(const char *)sql {
	if (self = [self init]) {
		db = [[SQLiteDatabase alloc] initInMemory];
		[db executeSQL:sql];
		[self didOpen];
	}
	return self;
}


- (BOOL)needsUpgrade {
	return [self intValueForMetaName:@"dataversion"] < 3;
}


- (void)upgrade {
	int version = [self intValueForMetaName:@"dataversion"];
	if (version < 2) {
		[self executeSQLNamed:@"DBUpgrade2"];
	}
	if (version < 3) {
		[self executeSQLNamed:@"DBUpgrade3"];
	}
	[self didOpen];
}


- (void)didOpen {
	if ([self needsUpgrade]) return;
	
	earliestChangeMonthDay = 0;
	
	EWMonth currentMonth = EWMonthDayGetMonth(EWMonthDayToday());
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT MIN(monthday),MAX(monthday) FROM days"];
	if ([stmt step]) {
		earliestMonth = ([stmt isNullColumn:0]
						 ? currentMonth
						 : EWMonthDayGetMonth([stmt intValueOfColumn:0]));
		latestMonth = ([stmt isNullColumn:1] 
					   ? currentMonth
					   : EWMonthDayGetMonth([stmt intValueOfColumn:1]));
		[stmt reset];
	} else {
		earliestMonth = currentMonth;
		latestMonth = currentMonth;
	}
}


- (void)close {
	[self commitChanges];
	[self flushCache];
	[db release];
	db = nil;
}


#pragma mark Reading


- (NSUInteger)weightCount {
	NSUInteger count;
	
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT COUNT(*) FROM days WHERE scaleWeight IS NOT NULL"];
	if ([stmt step]) {
		count = [stmt intValueOfColumn:0];
		[stmt reset];
	} else {
		count = 0;
	}

	return count;
}


- (float)earliestWeight {
	float weight;
	
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT scaleWeight FROM days WHERE scaleWeight IS NOT NULL ORDER BY monthday LIMIT 1"];
	if ([stmt step]) {
		weight = [stmt doubleValueOfColumn:0];
		[stmt reset];
	} else {
		weight = 0;
	}
	
	return weight;
}


- (float)latestWeight {
	EWMonthDay startMonthDay = EWMonthDayToday();
	EWDBMonth *dbm = [self getDBMonth:EWMonthDayGetMonth(startMonthDay)];
	float w;
	
	w = [dbm getDBDayOnDay:EWMonthDayGetDay(startMonthDay)]->trendWeight;
	if (w > 0) return w;
	
	w = [dbm inputTrendOnDay:EWMonthDayGetDay(startMonthDay)];
	return w;
}


- (EWDBMonth *)getDBMonth:(EWMonth)month {
	id key = [NSNumber numberWithInt:month];
	EWDBMonth *dbm = nil;
	
	[monthCacheLock lock];
	{
		dbm = [monthCache objectForKey:key];
		if (dbm == nil) {
			dbm = [[EWDBMonth alloc] initWithMonth:month database:self];
			[monthCache setObject:dbm forKey:key];
			[dbm release];
#if TARGET_IPHONE_SIMULATOR
			NSLog(@"Month Cache: %d records", [monthCache count]);
#endif
		}
		if (month < earliestMonth) earliestMonth = month;
		if (month > latestMonth) latestMonth = month;
	}
	[monthCacheLock unlock];
	
	return dbm;
}


- (void)getWeightMinimum:(float *)minWeight maximum:(float *)maxWeight from:(EWMonthDay)beginMonthDay to:(EWMonthDay)endMonthDay {
	NSParameterAssert(minWeight);
	NSParameterAssert(maxWeight);
	
	SQLiteStatement *stmt;
	
	if (beginMonthDay == 0 || endMonthDay == 0) {
		stmt = [db statementFromSQL:"SELECT MIN(scaleWeight),MAX(scaleWeight) FROM days"];
	} else {
		// TODO: If time frame is limited, trend will need to be taken into account.
		stmt = [db statementFromSQL:"SELECT MIN(scaleWeight),MAX(scaleWeight) FROM days WHERE monthday BETWEEN ? AND ?"];
		[stmt bindInt:beginMonthDay toParameter:1];
		[stmt bindInt:endMonthDay toParameter:2];
	}
	
	if ([stmt step]) {
		*minWeight = [stmt isNullColumn:0] ? 0 : [stmt intValueOfColumn:0];
		*maxWeight = [stmt isNullColumn:1] ? 0 : [stmt intValueOfColumn:1];
		[stmt reset];
	} else {
		*minWeight = 0;
		*maxWeight = 0;
	}
}


- (void)getEarliestMonthDay:(EWMonthDay *)beginMonthDay latestMonthDay:(EWMonthDay *)endMonthDay {
	NSParameterAssert(beginMonthDay);
	NSParameterAssert(endMonthDay);
	
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT MIN(monthday),MAX(monthday) FROM days"];
	if ([stmt step]) {
		*beginMonthDay = [stmt isNullColumn:0] ? 0 : [stmt intValueOfColumn:0];
		*endMonthDay = [stmt isNullColumn:1] ? 0 : [stmt intValueOfColumn:1];
		[stmt reset];
	} else {
		*beginMonthDay = 0;
		*endMonthDay = 0;
	}
}


- (float)trendWeightOnMonthDay:(EWMonthDay)md {
	EWDBMonth *dbm = [self getDBMonth:EWMonthDayGetMonth(md)];
	const EWDBDay *d = [dbm getDBDayOnDay:EWMonthDayGetDay(md)];
	return d->trendWeight;
}


/* Searches for a monthday before the given monthday where weight was recorded. Will cross at most one month boundary. */
- (EWMonthDay)monthDayOfWeightBefore:(EWMonthDay)mdStart {
	EWMonth monthStop = EWMonthDayGetMonth(mdStart) - 2;
	EWMonthDay md = EWMonthDayPrevious(mdStart);
	EWDBMonth *dbm = [self getDBMonth:EWMonthDayGetMonth(md)];
	while (monthStop < EWMonthDayGetMonth(md)) {
		if (EWMonthDayGetMonth(md) != dbm.month) {
			dbm = [self getDBMonth:EWMonthDayGetMonth(md)];
		}
		const EWDBDay *d = [dbm getDBDayOnDay:EWMonthDayGetDay(md)];
		if (d->scaleWeight > 0) {
			return md;
		}
		md = EWMonthDayPrevious(md);
	}
	return 0;
}


/* Searches for a monthday after the given monthday where weight was recorded. Will cross at most one month boundary. */
- (EWMonthDay)monthDayOfWeightAfter:(EWMonthDay)mdStart {
	EWMonth monthStop = EWMonthDayGetMonth(mdStart) + 2;
	EWMonthDay md = EWMonthDayNext(mdStart);
	EWDBMonth *dbm = [self getDBMonth:EWMonthDayGetMonth(md)];
	while (monthStop < EWMonthDayGetMonth(md)) {
		if (EWMonthDayGetMonth(md) != dbm.month) {
			dbm = [self getDBMonth:EWMonthDayGetMonth(md)];
		}
		const EWDBDay *d = [dbm getDBDayOnDay:EWMonthDayGetDay(md)];
		if (d->scaleWeight > 0) {
			return md;
		}
		md = EWMonthDayNext(md);
	}
	return 0;
}


- (BOOL)hasDataForToday {
	EWMonthDay today = EWMonthDayToday();
	EWDBMonth *dbm = [self getDBMonth:EWMonthDayGetMonth(today)];
	return [dbm hasDataOnDay:EWMonthDayGetDay(today)];
}


#pragma mark Writing


- (void)didChangeWeightOnMonthDay:(EWMonthDay)monthday {
	if ((earliestChangeMonthDay == 0) || (monthday < earliestChangeMonthDay)) {
		earliestChangeMonthDay = monthday;
	}
}


- (void)commitChanges {
	int changeCount = 0;
	
	[self updateTrendValues];
	[monthCacheLock lock];
	[db beginTransaction];
	for (EWDBMonth *dbm in [monthCache allValues]) {
		if ([dbm commitChanges]) changeCount++;
	}
	[db commitTransaction];
	[monthCacheLock unlock];
	
	if (changeCount > 0) {
		[[NSNotificationCenter defaultCenter] postNotificationName:EWDatabaseDidChangeNotification object:self];
	}
}


- (void)deleteAllData {
	[self flushCache];
	[db executeSQL:"DELETE FROM days;DELETE FROM months"];
	earliestMonth = EWMonthDayGetMonth(EWMonthDayToday());
	latestMonth = earliestMonth;
	earliestChangeMonthDay = 0;
}


- (SQLiteStatement *)selectMonthStatement {
	return [db statementFromSQL:"SELECT * FROM months WHERE month < ? ORDER BY month DESC LIMIT 1"];
}


- (SQLiteStatement *)insertMonthStatement {
	return [db statementFromSQL:"INSERT OR REPLACE INTO months VALUES (?,?,?)"];
}


- (SQLiteStatement *)selectDaysStatement {
	return [db statementFromSQL:"SELECT * FROM days WHERE monthday BETWEEN ? AND ?"];
}


- (SQLiteStatement *)insertDayStatement {
	return [db statementFromSQL:"INSERT OR REPLACE INTO days (monthday,scaleWeight,scaleFat,flag0,flag1,flag2,flag3,note) VALUES (?,?,?,?,?,?,?,?)"];
}


- (SQLiteStatement *)deleteDayStatement {
	return [db statementFromSQL:"DELETE FROM days WHERE monthday = ?"];
}


#pragma mark Energy Equivalents


- (NSArray *)loadEnergyEquivalents {
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT * FROM equivalents ORDER BY section,row"];
	NSMutableArray *array0 = [NSMutableArray array];
	NSMutableArray *array1 = [NSMutableArray array];
	
	[EWActivityEquivalent setCurrentWeight:[self latestWeight]];
	
	while ([stmt step]) {
		id <EWEnergyEquivalent> equiv;
		
		if ([stmt intValueOfColumn:1] == 0) {
			equiv = [[EWActivityEquivalent alloc] init];
			[array0 addObject:equiv];
		} else {
			equiv = [[EWFoodEquivalent alloc] init];
			[array1 addObject:equiv];
		}
		
		equiv.dbID = [stmt intValueOfColumn:0];
		equiv.name = [stmt stringValueOfColumn:3];
		equiv.unitName = [stmt stringValueOfColumn:4];
		equiv.value = [stmt doubleValueOfColumn:5];
		
		[equiv release];
	}
	
	if ([array0 count] == 0 && [array1 count] == 0) {
		NSLog(@"Equivalents table empty, loading defaults.");
		[self executeSQLNamed:@"DBEquivDefaults"];
		return [self loadEnergyEquivalents];
	}
	
	return [NSArray arrayWithObjects:array0, array1, nil];
}


- (void)saveEnergyEquivalents:(NSArray *)dataArray deletedItems:(NSArray *)deletedArray {
	SQLiteStatement *updateStmt = [db statementFromSQL:"UPDATE equivalents SET row=? WHERE id=?"];
	SQLiteStatement *insertStmt = [db statementFromSQL:"INSERT INTO equivalents (section,row,name,unit,value) VALUES (?,?,?,?,?)"];
	SQLiteStatement *deleteStmt = [db statementFromSQL:"DELETE FROM equivalents WHERE id=?"];
	
	[db beginTransaction];
	
	for (id <EWEnergyEquivalent> equiv in deletedArray) {
		[deleteStmt bindInt:equiv.dbID toParameter:1];
		[deleteStmt step];
		[deleteStmt reset];
	}
	
	int section;
	for (section = 0; section < [dataArray count]; section++) {
		NSArray *sectionArray = [dataArray objectAtIndex:section];
		int row;
		for (row = 0; row < [sectionArray count]; row++) {
			id <EWEnergyEquivalent> equiv = [sectionArray objectAtIndex:row];
			if (equiv.dbID > 0) {
				[updateStmt bindInt:row toParameter:1];
				[updateStmt bindInt:equiv.dbID toParameter:2];
				[updateStmt step];
				[updateStmt reset];
			} else {
				[insertStmt bindInt:section toParameter:1];
				[insertStmt bindInt:row toParameter:2];
				[insertStmt bindString:equiv.name toParameter:3];
				[insertStmt bindString:equiv.unitName toParameter:4];
				[insertStmt bindDouble:equiv.value toParameter:5];
				[insertStmt step];
				[insertStmt reset];
				equiv.dbID = [db lastInsertRowID];
			}
		}
	}
	
	[db commitTransaction];
}


#pragma mark Private Methods


- (void)updateTrendValues {
	if (earliestChangeMonthDay == 0) return;
	
	EWMonth month = EWMonthDayGetMonth(earliestChangeMonthDay);

	while (month <= latestMonth) {
		[[self getDBMonth:month] updateTrends];
		month += 1;
	}
	
	earliestChangeMonthDay = 0;
}


- (void)flushCache {
	[monthCacheLock lock];
	[monthCache	removeAllObjects];
	[monthCacheLock unlock];
}


- (void)executeSQLNamed:(NSString *)name {
	const char zero = 0;
	
	NSLog(@"Executing SQL %@", name);
	NSBundle *bundle = [NSBundle bundleForClass:[self class]]; // needed for unit testing
	NSString *path = [bundle pathForResource:name ofType:@"sql"];
	NSAssert1(path != nil, @"Cannot find SQL named %@", name);
	NSMutableData *sql = [[NSMutableData alloc] initWithContentsOfFile:path];
	[sql appendBytes:&zero length:1]; // null termination
	[db executeSQL:[sql bytes]];
	[sql release];
}


- (int)intValueForMetaName:(NSString *)name {
	int value;
	
	SQLiteStatement *stmt = [db statementFromSQL:"SELECT value FROM metadata WHERE name = ?"];
	[stmt bindString:name toParameter:1];
	if ([stmt step]) {
		value = [stmt intValueOfColumn:0];
		[stmt reset];
	} else {
		value = 0;
	}
	return value;
}


@end

//
//  EWImporter.h
//  EatWatch
//
//  Created by Benjamin Ragheb on 12/21/09.
//  Copyright 2009 Benjamin Ragheb. All rights reserved.
//

#import <Foundation/Foundation.h>


@class CSVReader;
@class EWImporter;
@class EWDatabase;


NSString * const kEWLastImportKey;
NSString * const kEWLastExportKey;


typedef enum {
	EWImporterFieldDate,
	EWImporterFieldWeight,
	EWImporterFieldFatRatio,
	EWImporterFieldFlag0,
	EWImporterFieldFlag1,
	EWImporterFieldFlag2,
	EWImporterFieldFlag3,
	EWImporterFieldNote,
	EWImporterFieldCount
} EWImporterField;


@protocol EWImporterDelegate
- (void)importer:(EWImporter *)importer importProgress:(float)progress;
- (void)importer:(EWImporter *)importer didImportNumberOfMeasurements:(unsigned int)importedCount outOfNumberOfRows:(unsigned int)rowCount;
@end


@interface EWImporter : NSObject
@property (nonatomic,weak) id <EWImporterDelegate> delegate;
@property (nonatomic) BOOL deleteFirst;
@property (nonatomic,readonly,getter=isImporting) BOOL importing;
@property (nonatomic,readonly) NSArray *columnNames;
@property (nonatomic,readonly) NSDictionary *columnDefaults;
- (id)initWithData:(NSData *)aData encoding:(NSStringEncoding)anEncoding;
- (void)autodetectFields;
- (NSDictionary *)infoForJavaScript;
- (void)setColumn:(NSUInteger)column forField:(EWImporterField)field;
- (void)setFormatter:(NSFormatter *)formatter forField:(EWImporterField)field;
- (BOOL)performImportToDatabase:(EWDatabase *)db;
@end

//
//  FormDataParser.m
//  EatWatch
//
//  Created by Benjamin Ragheb on 5/20/08.
//  Copyright 2008 Benjamin Ragheb. All rights reserved.
//

#import "FormDataParser.h"
#import "MicroWebServer.h"
#import "DataSearch.h"


@interface NSScanner (FormDataParser)
- (BOOL)scanStringOfLength:(NSInteger)length intoString:(NSString **)value;
@end


@implementation NSScanner (FormDataParser)
- (BOOL)scanStringOfLength:(NSInteger)length intoString:(NSString **)value {
	if ([[self string] length] < [self scanLocation] + length) {
		return NO;
	}
	if (value) {
		NSRange range = NSMakeRange([self scanLocation], length);
		*value = [[self string] substringWithRange:range];
	}
	[self setScanLocation:([self scanLocation] + length)];
	return YES;
}
@end


@interface FormDataParser ()
- (NSDictionary *)parseHeadersFromData:(NSData *)headersData;
- (void)parsePartData:(NSData *)partData;
- (NSData *)boundaryData;
- (void)parseMultipartFormData;
- (void)parseURLEncodedFormData:(NSData *)data;
@end


@implementation FormDataParser


- (id)init {
	if (self = [super init]) {
		dictionary = [[NSMutableDictionary alloc] init];
	}
	return self;
}


- (id)initWithData:(NSData *)data {
	if (self = [self init]) {
		[self parseURLEncodedFormData:data];
	}
	return self;
}


- (id)initWithConnection:(MicroWebConnection *)theConnection {
	if (self = [self init]) {
		connection = [theConnection retain];
		if ([[connection requestMethod] isEqualToString:@"POST"]) {
			NSString *contentType = [connection requestHeaderValueForName:@"Content-Type"];
			if ([contentType hasPrefix:@"multipart/form-data"]) {
				[self parseMultipartFormData];
			} else if ([contentType hasPrefix:@"application/x-www-form-urlencoded"]) {
				[self parseURLEncodedFormData:[connection requestBodyData]];
			}
		}
	}
	return self;
}


- (void)dealloc {
	[dictionary release];
	[connection release];
	[super dealloc];
}


- (NSString *)description {
	return [NSString stringWithFormat:@"<FormDataParser:%@>", dictionary];
}


#pragma mark Accessing Parsed Values


- (NSArray *)allKeys {
	return [dictionary allKeys];
}


- (BOOL)hasKey:(NSString *)key {
	return [dictionary objectForKey:key] != nil;
}


- (NSData *)dataForKey:(NSString *)key {
	id object = [dictionary objectForKey:key];
	if ([object isKindOfClass:[NSString class]]) {
		return [object dataUsingEncoding:NSUTF8StringEncoding];
	}
	return object;
}


- (NSString *)stringForKey:(NSString *)key {
	id object = [dictionary objectForKey:key];
	if ([object isKindOfClass:[NSData class]]) {
		return [[[NSString alloc] initWithData:object encoding:NSUTF8StringEncoding] autorelease];
	}
	return object;
}


#pragma mark Singlepart Parsing


- (void)parseURLEncodedFormData:(NSData *)data {
	NSString *bodyString;
	NSScanner *bodyScan;
	
	bodyString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	bodyScan = [[NSScanner alloc] initWithString:bodyString];
	[bodyString release];
	
	NSMutableString *accum = [[NSMutableString alloc] init];
	NSString *key = nil;
	
	NSCharacterSet *cSet = [NSCharacterSet characterSetWithCharactersInString:@"+=&%"];
	while (![bodyScan isAtEnd]) {

		NSString *part;
		if ([bodyScan scanUpToCharactersFromSet:cSet intoString:&part]) {
			[accum appendString:part];
		}
		
		if ([bodyScan scanString:@"%" intoString:nil]) {
			NSString *digits = nil;
			if ([bodyScan scanStringOfLength:2 intoString:&digits]) {
				NSScanner *digitScan = [[NSScanner alloc] initWithString:digits];
				unsigned int charCode;
				if ([digitScan scanHexInt:&charCode]) {
					[accum appendFormat:@"%c", charCode];
				} else {
					NSLog(@"Warning: expected hex number, got '%@'", digits);
				}
				[digitScan release];
			} else {
				NSLog(@"Warning: %% escape without two digits following");
				[accum appendString:@"%"];
			}
		}
		else if ([bodyScan scanString:@"+" intoString:nil]) {
			[accum appendString:@" "];
		}
		else if ([bodyScan scanString:@"=" intoString:nil]) {
			if (key) {
				NSLog(@"Warning: discarding key '%@'", key);
				[key release];
			}
			key = [accum copy];
			[accum setString:@""];
		}
		else if ([bodyScan scanString:@"&" intoString:nil] || [bodyScan isAtEnd]) {
			NSString *value = [accum copy];
			if (key) {
				[dictionary setObject:value forKey:key];
				[key release];
				key	= nil;
			} else {
				[dictionary setObject:@"" forKey:value];
			}
			[value release];
			[accum setString:@""];
		}
	}
	
	[key release];
	[accum release];
	[bodyScan release];
}


#pragma mark Multipart Parsing


- (NSDictionary *)parseHeadersFromData:(NSData *)headersData {
	NSMutableDictionary *headers = [[NSMutableDictionary alloc] initWithCapacity:5];
	NSString *headersString = [[NSString alloc] initWithData:headersData encoding:NSUTF8StringEncoding];
	NSScanner *scanner = [[NSScanner alloc] initWithString:headersString];
	[scanner setCharactersToBeSkipped:nil];
	
	NSString *name, *value;
	
	while ([scanner scanUpToString:@": " intoString:&name] &&
		   [scanner scanString:@": " intoString:nil] &&
		   [scanner scanUpToString:@"\r\n" intoString:&value] &&
		   [scanner scanString:@"\r\n" intoString:nil])
	{
		[headers setObject:value forKey:name];
	}
	
	[scanner release];
	[headersString release];
	return [headers autorelease];
}


- (void)parsePartData:(NSData *)partData {
	DataSearch *crlfcrlf = [[DataSearch alloc] initWithData:partData patternData:[NSData dataWithBytes:"\r\n\r\n" length:4]];
	NSUInteger crlfcrlfIndex = [crlfcrlf nextIndex];
	[crlfcrlf release];
	
	NSData *headersData = [partData subdataWithRange:NSMakeRange(0, crlfcrlfIndex + 2)];
	NSDictionary *headers = [self parseHeadersFromData:headersData];
	
	NSString *contentDisposition = [headers objectForKey:@"Content-Disposition"];
	if (contentDisposition == nil) {
		NSLog(@"Part has no Content-Disposition header!");
		return;
	}

	NSRange bodyRange;
	bodyRange.location = crlfcrlfIndex + 4;
	bodyRange.length = [partData length] - bodyRange.location;
	NSData *bodyData = [partData subdataWithRange:bodyRange];
	
	NSString *name;
	
	NSScanner *scanner = [[NSScanner alloc] initWithString:contentDisposition];
	if ([scanner scanString:@"form-data; name=\"" intoString:nil] &&
		[scanner scanUpToString:@"\"" intoString:&name] && 
		[scanner scanString:@"\"" intoString:nil]) {
		[dictionary setObject:bodyData forKey:name];
	}
	[scanner release];
}


- (NSData *)boundaryData {
	NSString *contentType = [connection requestHeaderValueForName:@"Content-Type"];
	NSString *prefix = @"multipart/form-data; boundary=";
	if (! [contentType hasPrefix:prefix]) return nil;
	NSString *boundaryString = [contentType substringFromIndex:[prefix length]];
	return [boundaryString dataUsingEncoding:NSUTF8StringEncoding];
}


- (void)parseMultipartFormData {
	NSData *boundaryData = [self boundaryData];
	if (boundaryData == nil) return;
	
	NSData *bodyData = [connection requestBodyData];
	
	DataSearch *boundary = [[DataSearch alloc] initWithData:bodyData patternData:boundaryData];
	
	NSUInteger boundaryIndex = [boundary nextIndex];
	NSRange partRange;
	partRange.location = boundaryIndex + [boundaryData length] + 2;
	while (true) {
		NSUInteger partEndIndex = [boundary nextIndex];
		if (partEndIndex == NSNotFound) break;
		partRange.length = partEndIndex - partRange.location - 4; // avoid "\r\n--"
		[self parsePartData:[bodyData subdataWithRange:partRange]];
		partRange.location = partEndIndex + [boundaryData length] + 2;
	}
	
	[boundary release];
}

@end

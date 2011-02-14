//
//  RKNSXMLParser.m
//  RestKit
//
//  Created by bwilliams on 2/11/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import "RKXMLParser.h"
#import "RKNSXMLParserDelegate.h"

@implementation RKXMLParser

- (NSDictionary*)objectFromString:(NSString*)string {
	
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:[string dataUsingEncoding:NSUTF8StringEncoding]];
	RKNSXMLParserDelegate *delegate = [[RKNSXMLParserDelegate alloc] init];
    [parser setDelegate:delegate];
	
    // Turn off all those XML nits
    [parser setShouldProcessNamespaces:NO];
    [parser setShouldReportNamespacePrefixes:NO];
    [parser setShouldResolveExternalEntities:NO];
    
	// Let'er rip
    [parser parse];
    [parser release];
	return [delegate parsedObject];
	
}

- (NSString*)stringFromObject:(id)object {
	return @"";
}

@end

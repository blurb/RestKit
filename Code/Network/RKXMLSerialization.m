//
//  RKXMLSerialization.m
//  RestKit
//
//  Created by bwilliams on 2/11/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import "RKXMLSerialization.h"
#import "NSObject+RKXMLSerialization.h"
#import "RKNSXMLParser.h"

@implementation RKXMLSerialization

+ (id)RKXMLSerializationWithObject:(NSObject*)object {
	return [[[self alloc] initWithObject:object] autorelease];
}

- (id)initWithObject:(NSObject*)object {
	if (self = [self init]) {
		_object = [object retain];
	}
	
	return self;
}

- (void)dealloc {	
	[_object release];
	[super dealloc];
}

- (NSString*)HTTPHeaderValueForContentType {
	return @"application/xml";
}

- (NSString*)XMLRepresentation {
	return [[[[RKNSXMLParser alloc] init] autorelease] stringFromObject:_object];
}

- (NSData*)HTTPBody {	
	return [[self RKNSXMLParser] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)isEqual:(id)object {
	if ([object isKindOfClass:[NSString class]]) {
		return [[self RKNSXMLParser] isEqualToString:object];
	} else {
		NSString* string = [[[[RKNSXMLParser alloc] init] autorelease] stringFromObject:object];
		return [[self RKNSXMLParser] isEqualToString:string];
	}
}

@end

@end

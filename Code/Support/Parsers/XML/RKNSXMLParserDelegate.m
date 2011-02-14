//
//  RKNSXMLParserDelegate.m
//  RestKit
//
//  Created by bwilliams on 2/13/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import "RKNSXMLParserDelegate.h"

@interface RKNSXMLParserDelegate ()
-(void)pushObject:(id)object;
-(id)popObject;
@end

@implementation RKNSXMLParserDelegate

-(id)init
{
	self = [super init];
	if (self) {
		stack = [[NSMutableArray alloc] init];
		state = ParseStateDictionary;
		rootObject = [[NSMutableDictionary alloc] init];
		[self pushObject:rootObject];
	}
	return self;
}

-(NSDictionary*)parsedObject
{
	return (NSDictionary*)rootObject;
}

-(void)dealloc
{
	[rootObject release];
	[stack release];
	[super dealloc];
}

-(void)pushObject:(id)object
{
	[stack addObject:object];
}

-(id)popObject
{
	id result = [stack lastObject];
	[stack removeLastObject];
	return result;
}

-(NSMutableDictionary*)currentDictionary
{
	if ([stack count] > 0)
		return (NSMutableDictionary*)[stack lastObject];
	return nil;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	if (state == ParseStateDictionary) {
		state = ParseStateProperty;
	} else if (state == ParseStateProperty) {
		[self pushObject:[[[NSMutableDictionary alloc] init] autorelease]];
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if (!currentValue) {
		currentValue = [[NSMutableString alloc] initWithString:string];
	} else {
		[currentValue appendString:string];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	NSMutableDictionary* dict = [self currentDictionary];
	if (state == ParseStateProperty) {
		// closed a property without seeing any children - just set the value of the dictionary
		NSObject* value = (currentValue != nil) ? (NSObject*)currentValue : (NSObject*)[NSNull null];
		[dict setObject:value forKey:elementName];
		state = ParseStateDictionary;
	} else if (state == ParseStateDictionary) {
		NSMutableDictionary* child = (NSMutableDictionary*)[self popObject];
		NSMutableDictionary* parent = [self currentDictionary];
		if (parent) {
			[parent setObject:child forKey:elementName];
		}
		state = ParseStateDictionary;
	}
	[currentValue release];
	currentValue = nil;

}

@end

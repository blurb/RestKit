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

-(NSObject*)currentObject
{
	if ([stack count] > 0)
		return [stack lastObject];
	return nil;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	[currentValue release];
	currentValue = nil;
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
	if (state == ParseStateProperty) {
		// closed a property without seeing any children - just set the value of the dictionary
		NSObject* value = (currentValue != nil) ? (NSObject*)currentValue : (NSObject*)[NSNull null];
		NSMutableDictionary* dict = (NSMutableDictionary*)[self currentObject];
		[dict setObject:value forKey:elementName];
		state = ParseStateDictionary;
	} else if (state == ParseStateDictionary) {
		NSMutableDictionary* child = (NSMutableDictionary*)[self popObject];
		NSObject* parent = [self currentObject];
		if (parent) {
			if ([parent isKindOfClass:[NSDictionary class]]) {
				NSMutableDictionary* parentDict = (NSMutableDictionary*)parent;
				NSObject* curValue = [parentDict objectForKey:elementName];
				if (curValue) {
					// we'll convert the parent into an array, but check that it only has one entry
					if ([parentDict count] != 1) {
						// throw exception -
						[NSException raise:nil format:@"Can't mix array and properties"];
					}
					[self popObject];
					[self pushObject:[NSMutableArray arrayWithObjects:parent, [NSDictionary dictionaryWithObject:child forKey:elementName], nil]];
				} else {
					[parentDict setObject:child forKey:elementName];
				}
			} else {
				NSMutableArray* parentArray = (NSMutableArray*)parent;
				[parentArray addObject:[NSDictionary dictionaryWithObjectsAndKeys:child, elementName, nil]];
			}
		}
		state = ParseStateDictionary;
	}
	[currentValue release];
	currentValue = nil;

}

@end

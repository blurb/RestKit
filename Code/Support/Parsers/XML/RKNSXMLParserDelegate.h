//
//  RKNSXMLParserDelegate.h
//  RestKit
//
//  Created by bwilliams on 2/13/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum  {
	ParseStateProperty,
	ParseStateArray,
	ParseStateDictionary
} ParseState;

@interface RKNSXMLParserDelegate : NSObject<NSXMLParserDelegate> {
	NSMutableString* currentValue;
	
	NSObject* rootObject;
	
	NSMutableArray* stack;
	
	ParseState state;
}

-(NSDictionary*)parsedObject;

@end

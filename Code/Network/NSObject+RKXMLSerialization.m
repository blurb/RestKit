//
//  NSObject+RKXMLSerialization.m
//  RestKit
//
//  Created by Brian Williams 02/12/2011
//  Copyright 2011 Blurb. All rights reserved.
//

#import "NSObject+RKXMLSerialization.h"

@implementation NSObject (RKXMLSerialization)

- (RKXMLSerialization*)XMLSerialization {
	return [RKXMLSerialization XMLSerializationWithObject:self];
}

@end

//
//  RKXMLSerialization.h
//  RestKit
//
//  Created by Brian Williams on 2/11/11.
//  Copyright 2011 Blurb. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "RKRequestSerializable.h"

@interface RKXMLSerialization : NSObject <RKRequestSerializable> {
	NSObject* _object;
}

/**
 * Returns a RestKit XML serializable representation of object
 */
+ (id)XMLSerializationWithObject:(NSObject*)object;

/**
 * Initialize a serialization with an object
 */
- (id)initWithObject:(NSObject*)object;


@end

//
//  NSObject+RKXMLSerialization.h
//  RestKit
//
//  Created by Brian Williams on 7/8/10.
//  Copyright 2011 Blurb. All rights reserved.
//

#import "RKXMLSerialization.h"

@interface NSObject (RKXMLSerialization)

/**
 * Returns a XML serialization representation of an object suitable
 * for submission to remote web services. This is provided as a convenience
 */
- (RKXMLSerialization*)XMLSerialization;

@end

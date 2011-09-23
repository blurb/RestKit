//
//  RKObjectMapper.m
//  RestKit
//
//  Created by Blake Watters on 3/4/10.
//  Copyright 2010 Two Toasters. All rights reserved.
//

#import <objc/message.h>

// TODO: Factor out Core Data...
#import "../CoreData/CoreData.h"

#import "RKObjectMapper.h"
#import "NSDictionary+RKAdditions.h"
#import "Errors.h"

// Default format string for date and time objects from Rails
// TODO: Rails specifics should probably move elsewhere...
static const NSString* kRKModelMapperRailsDateTimeFormatString = @"yyyy-MM-dd'T'HH:mm:ss'Z'"; // 2009-08-08T17:23:59Z
static const NSString* kRKModelMapperRailsDateFormatString = @"MM/dd/yyyy";
static const NSString* kRKModelMapperMappingFormatParserKey = @"RKMappingFormatParser";

@interface RKObjectMapper (Private)

- (id)parseString:(NSString*)string;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (Class)typeClassForProperty:(NSString*)property ofClass:(Class)class;
- (NSDictionary*)elementToPropertyMappingsForModel:(id)model;

- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;
- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements;
- (id)createOrUpdateInstanceOfInferredModelClass:(Class)class fromElements:(NSDictionary*)elements;

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName; // Rename!
- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements;
- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements;
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements;

- (NSDate*)parseDateFromString:(NSString*)string;
- (NSDate*)dateInLocalTime:(NSDate*)date;
- (id)getChildArray:object;

@end

#define NIL_CLASS(c) (!c || [c isKindOfClass: [NSNull class]])

@implementation RKObjectMapper

@synthesize format = _format;
@synthesize missingElementMappingPolicy = _missingElementMappingPolicy;
@synthesize dateFormats = _dateFormats;
@synthesize remoteTimeZone = _remoteTimeZone;
@synthesize localTimeZone = _localTimeZone;
@synthesize errorsKeyPath = _errorsKeyPath;
@synthesize errorsConcatenationString = _errorsConcatenationString;

///////////////////////////////////////////////////////////////////////////////
// public

- (id)init {
	if ((self = [super init])) {
		_elementToClassMappings = [[NSMutableDictionary alloc] init];
		_format = RKMappingFormatJSON;
		_missingElementMappingPolicy = RKIgnoreMissingElementMappingPolicy;
		_inspector = [[RKObjectPropertyInspector alloc] init];
		self.dateFormats = [NSArray arrayWithObjects:kRKModelMapperRailsDateTimeFormatString, kRKModelMapperRailsDateFormatString, nil];
		self.remoteTimeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
		self.localTimeZone = [NSTimeZone localTimeZone];
		self.errorsKeyPath = @"errors";
		self.errorsConcatenationString = @", ";
	}
	return self;
}

- (void)dealloc {
	[_elementToClassMappings release];
	[_inspector release];
	[_dateFormats release];
	[_errorsKeyPath release];
	[_errorsConcatenationString release];
    [_remoteTimeZone release];
	[super dealloc];
}

- (void)registerClass:(Class<RKObjectMappable>)aClass forElementNamed:(NSString*)elementName {
	[_elementToClassMappings setObject:aClass forKey:elementName];
}

- (void)setFormat:(RKMappingFormat)format {
	_format = format;
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from a string

- (id)parseString:(NSString*)string {
	NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
    NSString *threadFormat = [NSString stringWithFormat:@"%@_%d", kRKModelMapperMappingFormatParserKey, _format];
	NSObject<RKParser>* parser = [threadDictionary objectForKey:threadFormat];
    
	if (!parser) {
		NSString* parserClassname = nil;
		if (_format == RKMappingFormatJSON) {
			parserClassname = @"RKJSONParser";
		} else if (_format == RKMappingFormatXML) {
			parserClassname = @"RKXMLParser";
		}
		if (parserClassname) {
			Class parserClass = NSClassFromString(parserClassname);
			parser = [[parserClass alloc] init];
			if (!parser) 
				[NSException raise:@"No parser is available" format:@"RestKit does not have %@ support compiled-in", parserClassname ];

			[threadDictionary setObject:parser forKey:threadFormat];
			[parser release];
		}
	}
	
	id result = nil;
	@try {
		result = [parser objectFromString:string];
	}
	@catch (NSException* e) {
		NSLog(@"[RestKit] RKObjectMapper:parseString: Exception (%@) parsing error from string: %@", [e reason], string);
	}
	return result;
}

- (NSError*)parseErrorFromString:(NSString*)string {
	NSDictionary* errorResponse = [self parseString:string];
	// Note: with xml error response, a single error response is not in an array, so we'll wrap it if needed
    NSObject* errors = [errorResponse valueForKeyPath:_errorsKeyPath];
	if (errors) {
		if (![errors isKindOfClass:[NSArray class]])
			errors = [NSArray arrayWithObject:errors];
	} else {
        NSDictionary* unknownError = [NSDictionary dictionaryWithKeysAndObjects:@"error", 
                                        [NSDictionary dictionaryWithKeysAndObjects:@"code", @"global.unknown",
                                                                                  @"message", @"Unknown error", nil], 
                                        nil];
		errors = [NSArray arrayWithObject:unknownError];
	}

	NSString* errorMessage = [(NSArray*)errors componentsJoinedByString:_errorsConcatenationString];
	NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
							  errorMessage, NSLocalizedDescriptionKey,
							  errors, RKRestKitErrorDomain, // include the Raw Errors object
							  nil];
	NSError *error = [NSError errorWithDomain:RKRestKitErrorDomain code:RKObjectLoaderRemoteSystemError userInfo:userInfo];
	
	return error;
}

/*Checks for something that looks like:
 *    <objects>
 *        <object />
 *        <object />
 *    </objects>
 * and returns the child array if the root object conforms to this expectation. 
 * TODO: Could loosen the expectation to allow an array of any child of a recognized
 *       type, instead of enforcing same-type child objects.
 */
- (id)getChildArray:rootObject {
    //check for single wrapper object, like 'objects'
    if ([rootObject count] == 1) {
        //get the single content of 'objects'
        NSArray *objects = [[rootObject allValues] objectAtIndex:0];
        //check if root object contains an array of objects
        if (objects && [objects isKindOfClass:NSArray.class]) {
            NSArray *objectsArr = (NSArray*)objects;
            if (objectsArr.count) {
                
                NSString *childKey = nil;
                //Make sure all the child nodes are of the same type
                for (id child in objectsArr) {
                    if (!child || ![child isKindOfClass:NSDictionary.class]) {
                        return nil;
                    }
                    NSDictionary *childDict = (NSDictionary*)child;
                    if (childDict.count != 1) {
                        return nil;
                    }
                    
                    NSString *childFieldName = [[childDict allKeys] objectAtIndex:0];
                    if (!childKey) {
                        childKey = childFieldName;
                    } else if (![childKey isEqualToString:childFieldName]){
                        return nil;
                    }
                }
                //If the child type is known, return the array.
                if ([_elementToClassMappings objectForKey:childKey])
                    return objectsArr;
            }
        }
    }
    return nil;
}

- (id)mapFromString:(NSString*)string toClass:(Class)class keyPath:(NSString*)keyPath {
	id object = [self parseString:string];
	if (keyPath) {
		object = [object valueForKeyPath:keyPath];
	}
	if ([object isKindOfClass:[NSDictionary class]]) {
        id mapObj = [self mapObjectFromDictionary:(NSDictionary*)object];
        if (!mapObj && !keyPath) {
            id childObject = [self getChildArray:object];
            if (childObject) {
                mapObj = [self mapObjectsFromArrayOfDictionaries:(NSArray*)childObject];
            }
        }
        return mapObj;
	} else if ([object isKindOfClass:[NSArray class]]) {
		if (class) {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object toClass:class];
		} else {
			return [self mapObjectsFromArrayOfDictionaries:(NSArray*)object];
		}
    } else if ([object isKindOfClass:[NSString class]] && [[((NSString*)object) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from an empty payload. Skipping...");
        //an empty set
        return nil;
	} else if (nil == object || [NSNull null] == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return nil;
	} else {
		[NSException raise:@"Unable to map from requested string" 
					format:@"The object was deserialized into a %@. A dictionary or array of dictionaries was expected.", [object class]];
		return nil;
	}
}

- (id)mapFromString:(NSString*)string {
	return [self mapFromString:string toClass:nil keyPath:nil];
}

- (void)mapObject:(id)model fromString:(NSString*)string {
	id object = [self parseString:string];
	if ([object isKindOfClass:[NSDictionary class]]) {
		[self mapObject:model fromDictionary:object];
	} else if (nil == object) {
		NSLog(@"[RestKit] RKModelMapper: mapObject:fromString: attempted to map from a nil payload. Skipping...");
		return;
	} else {
		[NSException raise:@"Unable to map from requested string"
					format:@"The object was serialized into a %@. A dictionary of elements was expected.", [object class]];
	}
}

///////////////////////////////////////////////////////////////////////////////
// Mapping from objects

// TODO: Should accept RKObjectMappable instead of id...
- (void)mapObject:(id)model fromDictionary:(NSDictionary*)dictionary {
	Class class = [model class];
	
	NSArray* elementNames = [_elementToClassMappings allKeysForObject:class];
	if ([elementNames count] == 0) {
		if ([model conformsToProtocol:@protocol(RKObjectMappable)]) {
			[self updateModel:model fromElements:dictionary];
		} else {
			[NSException raise:@"Unable to map from requested dictionary"
						format:@"There was no mappable element found for objects of type %@", class];
		}
	} else {
		for (NSString* elementName in elementNames) {
			if ([[dictionary allKeys] containsObject:elementName]) {
				NSDictionary* elements = [dictionary objectForKey:elementName];
				[self updateModel:model fromElements:elements];
				return;
			}
		}
		// If the dictionary is not namespaced, attempt mapping its properties directly...
		[self updateModel:model fromElements:dictionary];
	}
}

// TODO: Can I make this support keyPath??
- (id)mapObjectFromDictionary:(NSDictionary*)dictionary {
    //Empty server responses can result in empty dictionaries.
    if (![dictionary count]) {
        return nil;
    }
    
	NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
	Class class = [_elementToClassMappings objectForKey:elementName];
	NSDictionary* elements = [dictionary objectForKey:elementName];
	
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			// TODO: Makes assumptions about the structure of the JSON...
			NSString* elementName = [[dictionary allKeys] objectAtIndex:0];
			Class class = [_elementToClassMappings objectForKey:elementName];
			NSAssert(class != nil, @"Unable to perform object mapping without a destination class");
			NSDictionary* elements = [dictionary objectForKey:elementName];
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:elements];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

- (NSArray*)mapObjectsFromArrayOfDictionaries:(NSArray*)array toClass:(Class)class {
	NSMutableArray* objects = [NSMutableArray array];
	for (NSDictionary* dictionary in array) {
		if (![dictionary isKindOfClass:[NSNull class]]) {
			id object = [self createOrUpdateInstanceOfModelClass:class fromElements:dictionary];
			[objects addObject:object];
		}
	}
	
	return (NSArray*)objects;
}

///////////////////////////////////////////////////////////////////////////////
// Utility Methods

- (Class)typeClassForProperty:(NSString*)property ofClass:(Class)class {
	return [[_inspector propertyNamesAndTypesForClass:class] objectForKey:property];
}

- (NSDictionary*)elementToPropertyMappingsForModel:(id)model {
	return [[model class] elementToPropertyMappings];
}

///////////////////////////////////////////////////////////////////////////////
// Persistent Instance Finders

// TODO: This version does not update properties. Should probably be realigned.
- (id)findOrCreateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
	id object = nil;
	if ([class isSubclassOfClass:[RKManagedObject class]]) {
		NSString* primaryKeyElement = [class performSelector:@selector(primaryKeyElement)];
		id primaryKeyValue = [elements objectForKey:primaryKeyElement];
		object = [[[RKObjectManager sharedManager] objectStore] findOrCreateInstanceOfManagedObject:class
                                                                                withPrimaryKeyValue:primaryKeyValue];
	}
	// instantiate if object is nil
	if (object == nil) {
        if ([class conformsToProtocol:@protocol(RKObjectMappable)] && [class respondsToSelector:@selector(object)]) {
            object = [class object];
        } else {
            // Allow non-RKObjectMappable objecs to pass through to alloc/init. Do we need this?
            object = [[[class alloc] init] autorelease];
        }
	}
	
	return object;
}

- (id)createOrUpdateInstanceOfModelClass:(Class)class fromElements:(NSDictionary*)elements {
    if ([elements isKindOfClass:NSNull.class]) {
        return [NSNull null];
    }
    
	id model = [self findOrCreateInstanceOfModelClass:class fromElements:elements];
	[self updateModel:model fromElements:elements];
	return model;
}

///////////////////////////////////////////////////////////////////////////////
// Property & Relationship Manipulation

- (void)updateModel:(id)model ifNewPropertyValue:(id)propertyValue forPropertyNamed:(NSString*)propertyName {	
	id currentValue = [model valueForKey:propertyName];
	if (nil == currentValue && nil == propertyValue) {
		// Don't set the property, both are nil
	} else if (nil == propertyValue || [propertyValue isKindOfClass:[NSNull class]]) {
		// Clear out the value to reset it
		[model setValue:nil forKey:propertyName];
	} else if (currentValue == nil || [currentValue isKindOfClass:[NSNull class]]) {
		// Existing value was nil, just set the property and be happy
		[model setValue:propertyValue forKey:propertyName];
	} else {
		SEL comparisonSelector;
		if ([propertyValue isKindOfClass:[NSString class]]) {
			comparisonSelector = @selector(isEqualToString:);
		} else if ([propertyValue isKindOfClass:[NSNumber class]]) {
			comparisonSelector = @selector(isEqualToNumber:);
		} else if ([propertyValue isKindOfClass:[NSDate class]]) {
			comparisonSelector = @selector(isEqualToDate:);
		} else if ([propertyValue isKindOfClass:[NSArray class]]) {
			comparisonSelector = @selector(isEqualToArray:);
		} else if ([propertyValue isKindOfClass:[NSDictionary class]]) {
			comparisonSelector = @selector(isEqualToDictionary:);
		} else {
			[NSException raise:@"NoComparisonSelectorFound" format:@"You need a comparison selector for %@ (%@)", propertyName, [propertyValue class]];
		}
		
		// Comparison magic using function pointers. See this page for details: http://www.red-sweater.com/blog/320/abusing-objective-c-with-class
		// Original code courtesy of Greg Parker
		// This is necessary because isEqualToNumber will return negative integer values that aren't coercable directly to BOOL's without help [sbw]
		BOOL (*ComparisonSender)(id, SEL, id) = (BOOL (*)(id, SEL, id)) objc_msgSend;		
		BOOL areEqual = ComparisonSender(currentValue, comparisonSelector, propertyValue);
		
		if (NO == areEqual) {
			[model setValue:propertyValue forKey:propertyName];
		}
	}
}

- (void)setPropertiesOfModel:(id)model fromElements:(NSDictionary*)elements {
	NSDictionary* elementToPropertyMappings = [self elementToPropertyMappingsForModel:model];
	for (NSString* elementKeyPath in elementToPropertyMappings) {		
		id elementValue = nil;		
		BOOL setValue = YES;
		
		@try {
			elementValue = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException * e) {
			NSLog(@"[RestKit] RKModelMapper: Unable to find element at keyPath %@ in elements dictionary for %@. Skipping...", elementKeyPath, [model class]);
			setValue = NO;
		}
		
		// TODO: Need a way to differentiate between a keyPath that exists, but contains a nil
		// value and one that is not present in the payload. Causes annoying problems!
		if (nil == elementValue) {
			setValue = (_missingElementMappingPolicy == RKSetNilForMissingElementMappingPolicy);
		}
		
		if (setValue) {
			id propertyValue = elementValue;
			NSString* propertyName = [elementToPropertyMappings objectForKey:elementKeyPath];
			Class class = [self typeClassForProperty:propertyName ofClass:[model class]];
			if (elementValue != (id)kCFNull && nil != elementValue) {
				if ([class isEqual:[NSDate class]]) {
					NSDate* date = [self parseDateFromString:(propertyValue)];
					propertyValue = [self dateInLocalTime:date];
				}
			}
			
			[self updateModel:model ifNewPropertyValue:propertyValue forPropertyNamed:propertyName];
		}
	}
}

//Updated this method to allow arrays containing multiple child types. For this behavior, 
//the class mapping keypath should leave off the last component (the classname).
- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements {
	NSDictionary* elementToRelationshipMappings = [[object class] elementToRelationshipMappings];
	for (NSString* elementKeyPath in elementToRelationshipMappings) {
		NSString* propertyName = [elementToRelationshipMappings objectForKey:elementKeyPath];
		
        // NOTE: The last part of the keyPath MAY contains the elementName for the mapped destination class of our children
        NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
        Class forcedModelClass = nil;
        NSString *forcedClassName = nil;
        
        if (componentsOfKeyPath.count > 1) {
            //The class is specifying a specific relationship clas type
            forcedClassName = [componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1];
        } else {
            //The relationship type is either the full keypath, or it will be inferred
            //down below.
            forcedClassName = elementKeyPath;
        }
        
        forcedModelClass = [_elementToClassMappings valueForKeyPath:forcedClassName];
        if (NIL_CLASS(forcedModelClass) && (componentsOfKeyPath.count > 1)) {
            //For multipart keypaths, the last component must be a valid class type. This
            //is a hack to support the old forced class behavior, as well as inferring the
            //class of each subelement.
            NSLog(@"Warning: could not find a class mapping for relationship '%@':", forcedClassName);
            NSLog(@"   parent class   : %@", [object class]);
            NSLog(@"   elements to map: %@", elements);
            NSLog(@"maybe you want to register your model with the object mapper or you want to pluralize the keypath?");
            break;
        }
        
		id relationshipElements = nil;
		@try {
			relationshipElements = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException* e) {
			NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for elements:%@", e, elementKeyPath, elements);
		}
        
        // Handle missing elements for the relationship
        if (relationshipElements == nil || relationshipElements == NSNull.null) {
            if (self.missingElementMappingPolicy == RKSetNilForMissingElementMappingPolicy) {
                [object setValue:nil forKey:propertyName];
                continue;
            } else if(self.missingElementMappingPolicy == RKIgnoreMissingElementMappingPolicy) {
                continue;
            }
        }
                
        Class collectionClass = [self typeClassForProperty:propertyName ofClass:[object class]];
        if ([collectionClass isSubclassOfClass:[NSSet class]] || [collectionClass isSubclassOfClass:[NSArray class]]) {
            id children = nil;
            if ([collectionClass isSubclassOfClass:[NSSet class]]) {
                children = [NSMutableSet setWithCapacity:[relationshipElements count]];
            } else if ([collectionClass isSubclassOfClass:[NSArray class]]) {
                children = [NSMutableArray arrayWithCapacity:[relationshipElements count]];
            }
            
            for (NSDictionary* childElements in relationshipElements) {	
                id child = [self createOrUpdateInstanceOfInferredModelClass:forcedModelClass fromElements:childElements];		
                if (child) {
                    [(NSMutableArray*)children addObject:child];
                }
            }
            
            [object setValue:children forKey:propertyName];
        } else if ([relationshipElements isKindOfClass:[NSDictionary class]]) {  
            id child = [self createOrUpdateInstanceOfInferredModelClass:forcedModelClass fromElements:relationshipElements];		
            if (child) {
                [object setValue:child forKey:propertyName];
            }
        }
    }
    
    // Connect relationships by primary key
    Class managedObjectClass = NSClassFromString(@"RKManagedObject");
    if (managedObjectClass && [object isKindOfClass:managedObjectClass]) {
        RKManagedObject* managedObject = (RKManagedObject*)object;
        NSDictionary* relationshipToPkPropertyMappings = [[managedObject class] relationshipToPrimaryKeyPropertyMappings];
        for (NSString* relationship in relationshipToPkPropertyMappings) {
            NSString* primaryKeyPropertyString = [relationshipToPkPropertyMappings objectForKey:relationship];
            
            NSNumber* objectPrimaryKeyValue = nil;
            @try {
                objectPrimaryKeyValue = [managedObject valueForKeyPath:primaryKeyPropertyString];
            } @catch (NSException* e) {
                NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for object:%@", e, primaryKeyPropertyString, managedObject);
            }
            
            NSDictionary* relationshipsByName = [[managedObject entity] relationshipsByName];
            NSEntityDescription* relationshipDestinationEntity = [[relationshipsByName objectForKey:relationship] destinationEntity];
            id relationshipDestinationClass = objc_getClass([[relationshipDestinationEntity managedObjectClassName] cStringUsingEncoding:NSUTF8StringEncoding]);
            RKManagedObject* relationshipValue = [[[RKObjectManager sharedManager] objectStore] findOrCreateInstanceOfManagedObject:relationshipDestinationClass
                                                                                                                withPrimaryKeyValue:objectPrimaryKeyValue];
            if (relationshipValue) {
                [managedObject setValue:relationshipValue forKey:relationship];
            }
        }
    }
}

- (id)createOrUpdateInstanceOfInferredModelClass:(Class)forcedModelClass fromElements:(NSDictionary*)childElements {
    Class modelClass = forcedModelClass;
    NSDictionary *modelProperties = childElements;
    if (NIL_CLASS(modelClass)) {
        if (childElements.count == 1) {
            //This is a hack for supporting child elements that are dictionaries
            //keyed by class name.
            NSString *className = [[childElements allKeys] objectAtIndex:0];
            modelClass = [_elementToClassMappings valueForKeyPath:className];
            if (NIL_CLASS(modelClass)) {
                NSLog(@"Warning: could not find a class mapping for nested object '%@':", className);
                
                return nil;
            } else {
                modelProperties = [childElements objectForKey:className];
            }
        }
    } 
    
    return [self createOrUpdateInstanceOfModelClass:modelClass fromElements:modelProperties];	
}

//This method did not support arrays containing children of multiple types, so it was 
//replaced above
/*
- (void)setRelationshipsOfModel:(id)object fromElements:(NSDictionary*)elements {
	NSDictionary* elementToRelationshipMappings = [[object class] elementToRelationshipMappings];
	for (NSString* elementKeyPath in elementToRelationshipMappings) {
		NSString* propertyName = [elementToRelationshipMappings objectForKey:elementKeyPath];
		
		id relationshipElements = nil;
		@try {
			relationshipElements = [elements valueForKeyPath:elementKeyPath];
		}
		@catch (NSException* e) {
			NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for elements:%@", e, elementKeyPath, elements);
		}
        
        // Handle missing elements for the relationship
        if (relationshipElements == nil || relationshipElements == NSNull.null) {
            if (self.missingElementMappingPolicy == RKSetNilForMissingElementMappingPolicy) {
                [object setValue:nil forKey:propertyName];
                continue;
            } else if(self.missingElementMappingPolicy == RKIgnoreMissingElementMappingPolicy) {
                continue;
            }
        }
        
        // NOTE: The last part of the keyPath contains the elementName for the mapped destination class of our children
        NSArray* componentsOfKeyPath = [elementKeyPath componentsSeparatedByString:@"."];
        NSString *className = [componentsOfKeyPath objectAtIndex:[componentsOfKeyPath count] - 1];
        Class modelClass = [_elementToClassMappings valueForKeyPath:className];
        if ([modelClass isKindOfClass: [NSNull class]]) {
            NSLog(@"Warning: could not find a class mapping for relationship '%@':", className);
            NSLog(@"   parent class   : %@", [object class]);
            NSLog(@"   elements to map: %@", elements);
            NSLog(@"maybe you want to register your model with the object mapper or you want to pluralize the keypath?");
            break;
        }
        
        Class collectionClass = [self typeClassForProperty:propertyName ofClass:[object class]];
        if ([collectionClass isSubclassOfClass:[NSSet class]] || [collectionClass isSubclassOfClass:[NSArray class]]) {
            id children = nil;
            if ([collectionClass isSubclassOfClass:[NSSet class]]) {
                children = [NSMutableSet setWithCapacity:[relationshipElements count]];
            } else if ([collectionClass isSubclassOfClass:[NSArray class]]) {
                children = [NSMutableArray arrayWithCapacity:[relationshipElements count]];
            }
            
            for (NSDictionary* childElements in relationshipElements) {				
                id child = [self createOrUpdateInstanceOfModelClass:modelClass fromElements:childElements];		
                if (child) {
                    [(NSMutableArray*)children addObject:child];
                }
            }
            
            [object setValue:children forKey:propertyName];
        } else if ([relationshipElements isKindOfClass:[NSDictionary class]]) {
            id child = [self createOrUpdateInstanceOfModelClass:modelClass fromElements:relationshipElements];		
            [object setValue:child forKey:propertyName];
        }
    }
    
    // Connect relationships by primary key
    Class managedObjectClass = NSClassFromString(@"RKManagedObject");
    if (managedObjectClass && [object isKindOfClass:managedObjectClass]) {
        RKManagedObject* managedObject = (RKManagedObject*)object;
        NSDictionary* relationshipToPkPropertyMappings = [[managedObject class] relationshipToPrimaryKeyPropertyMappings];
        for (NSString* relationship in relationshipToPkPropertyMappings) {
            NSString* primaryKeyPropertyString = [relationshipToPkPropertyMappings objectForKey:relationship];
            
            NSNumber* objectPrimaryKeyValue = nil;
            @try {
                objectPrimaryKeyValue = [managedObject valueForKeyPath:primaryKeyPropertyString];
            } @catch (NSException* e) {
                NSLog(@"Caught exception:%@ when trying valueForKeyPath with path:%@ for object:%@", e, primaryKeyPropertyString, managedObject);
            }
            
            NSDictionary* relationshipsByName = [[managedObject entity] relationshipsByName];
            NSEntityDescription* relationshipDestinationEntity = [[relationshipsByName objectForKey:relationship] destinationEntity];
            id relationshipDestinationClass = objc_getClass([[relationshipDestinationEntity managedObjectClassName] cStringUsingEncoding:NSUTF8StringEncoding]);
            RKManagedObject* relationshipValue = [[[RKObjectManager sharedManager] objectStore] findOrCreateInstanceOfManagedObject:relationshipDestinationClass
                                                                                                                withPrimaryKeyValue:objectPrimaryKeyValue];
            if (relationshipValue) {
                [managedObject setValue:relationshipValue forKey:relationship];
            }
        }
    }
}
*/
- (void)updateModel:(id)model fromElements:(NSDictionary*)elements {
	[self setPropertiesOfModel:model fromElements:elements];
	[self setRelationshipsOfModel:model fromElements:elements];
}

///////////////////////////////////////////////////////////////////////////////
// Date & Time Helpers

- (NSDate*)parseDateFromString:(NSString*)string {
	NSDate* date = nil;
	NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
	// TODO: I changed this to local time and it fixes my date issues. wtf?
	[formatter setTimeZone:self.localTimeZone];
	for (NSString* formatString in self.dateFormats) {
		[formatter setDateFormat:formatString];
		date = [formatter dateFromString:string];
		if (date) {
			break;
		}
	}
	
	[formatter release];
	return date;
}

- (NSDate*)dateInLocalTime:(NSDate*)date {
	NSDate* destinationDate = nil;
	if (date) {
		NSInteger remoteGMTOffset = [self.remoteTimeZone secondsFromGMTForDate:date];
		NSInteger localGMTOffset = [self.localTimeZone secondsFromGMTForDate:date];
		NSTimeInterval interval = localGMTOffset - remoteGMTOffset;		
		destinationDate = [[[NSDate alloc] initWithTimeInterval:interval sinceDate:date] autorelease];
	}	
	return destinationDate;
}

@end

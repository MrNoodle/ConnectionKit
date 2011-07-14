//
//  SVPagelet.m
//  Sandvox
//
//  Created by Mike on 14/07/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "SVPagelet.h"

#import "SVPageletDOMController.h"


@implementation SVPagelet

- (id)initWithGraphic:(SVGraphic *)graphic;
{
    if (self = [self init])
    {
        _graphic = [graphic retain];
    }
    return self;
}

- (void)dealloc;
{
    [_graphic release];
    [super dealloc];
}

- (SVDOMController *)newDOMControllerWithElementIdName:(NSString *)elementID
{
    SVDOMController *result = [[SVPageletDOMController alloc] initWithRepresentedObject:_graphic];
    [result setElementIdName:elementID includeWhenPublishing:NO];
    return result;
}


@end
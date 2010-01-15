// 
//  SVExternalLink.m
//  Sandvox
//
//  Created by Mike on 13/01/2010.
//  Copyright 2010 Karelia Software. All rights reserved.
//

#import "SVExternalLink.h"

#import "SVURLPreviewViewController.h"

#import "NSURL+Karelia.h"


@implementation SVExternalLink 

@dynamic openInNewWindow;
@dynamic linkURLString;

- (NSURL *)URL
{
    NSURL *result = [NSURL URLWithString:[self linkURLString]];
    return result;
}

+ (NSSet *)keyPathsForValuesAffectingURL
{
    return [NSSet setWithObject:@"linkURLString"];
}

- (NSString *)fileName
{
    return [[[self URL] lastPathComponent] stringByDeletingPathExtension];
}

#pragma mark UI

- (Class <SVWebContentViewController>)viewControllerClass;
{
    return [SVURLPreviewViewController class];
}

@end

//
//  SVPageThumbnailHTMLContext.m
//  Sandvox
//
//  Created by Mike on 26/01/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "SVPageThumbnailHTMLContext.h"

#import "SVMedia.h"
#import "SVMediaRequest.h"

#import "KSObjectKeyPathPair.h"


@implementation SVPageThumbnailHTMLContext

@synthesize delegate = _delegate;

- (NSURL *)addMediaWithRequest:(SVMediaRequest *)request;
{
    [[self delegate] pageThumbnailHTMLContext:self didAddMedia:[request media]];
    return [super addMediaWithRequest:request];
}

- (void) addDependencyOnObject:(NSObject *)object keyPath:(NSString *)keyPath;
{
    [super addDependencyOnObject:object keyPath:keyPath];
    
    KSObjectKeyPathPair *pair = [[KSObjectKeyPathPair alloc] initWithObject:object keyPath:keyPath];
    
    [[self delegate] pageThumbnailHTMLContext:self addDependency:pair];
    [pair release];
}

@end

//
//  IMStatusService.m
//  IMStatusPlugIn
//
//  Copyright 2007-2011 Karelia Software. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  *  Redistribution of source code must retain the above copyright notice,
//     this list of conditions and the follow disclaimer.
//
//  *  Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other material provided with the distribution.
//
//  *  Neither the name of Karelia Software nor the names of its contributors
//     may be used to endorse or promote products derived from this software
//     without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS-IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUR OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
//  Community Note: This code is distrubuted under a modified BSD License.
//  We encourage you to share your Sandvox Plugins similarly.
//

#import "IMStatusService.h"


@implementation IMStatusService

+ (NSArray *)services
{
	static NSArray *sServices;
	
	if (!sServices)
	{
		// Build the list of services
		NSMutableArray *services = [NSMutableArray arrayWithCapacity:3];
		
		NSBundle *bundle = [NSBundle bundleForClass:self];
		NSArray *pluginServices = [bundle objectForInfoDictionaryKey:@"IMServices"];
		[services addObjectsFromArray:[IMStatusService servicesWithArrayOfDictionaries:pluginServices
																		  resourcePath:[bundle resourcePath]]];
		
		sServices = [services copy];
	}
	
	return sServices;
}

+ (NSArray *)servicesWithArrayOfDictionaries:(NSArray *)services resourcePath:(NSString *)resourcePath
{
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:1];
	
	NSEnumerator *enumerator = [services objectEnumerator];
	NSDictionary *aServiceDict;
	
	while (aServiceDict = [enumerator nextObject])
	{
		IMStatusService *service = [[IMStatusService alloc] initWithDictionary:aServiceDict
																  resourcePath:resourcePath];
		
		[result addObject:service];
		[service release];
	}
	
	return result;
}


#pragma mark -
#pragma mark Init & Dealloc

- (id)initWithDictionary:(NSDictionary *)dictionary resourcePath:(NSString *)resources
{
	[super init];
	
	myName = [[dictionary objectForKey:@"serviceName"] copy];
	myIdentifier = [[dictionary objectForKey:@"serviceIdentifier"] copy];
	myResourcesPath = [resources copy];
	myOnlineImagePath =[[dictionary objectForKey:@"onlineImage"] copy];
	myOfflineImagePath = [[dictionary objectForKey:@"offlineImage"] copy];
	
	myPublishingHTML = [[dictionary objectForKey:@"publishingHTML"] copy];
	myLivePreviewHTML = [[dictionary objectForKey:@"livePreviewHTML"] copy];
	myNonLivePreviewHTML = [[dictionary objectForKey:@"nonLivePreviewHTML"] copy];
	
	return self;
}

- (void)dealloc
{
	[myName release];
	[myIdentifier release];
    [myResourcesPath release];
    [myOnlineImagePath release];
    [myOfflineImagePath release];
	[myPublishingHTML release];
	[myLivePreviewHTML release];
	[myNonLivePreviewHTML release];
	
	[super dealloc];
}


#pragma mark -
#pragma mark Accessors

- (NSString *)serviceName { return myName; }

- (NSString *)serviceIdentifier { return myIdentifier; }

- (NSString *)onlineImagePath
{
	NSString *result = nil;
	
	if (myOnlineImagePath)
	{
		result = [myResourcesPath stringByAppendingPathComponent:myOnlineImagePath];
	}
	
	return result;
}

- (NSString *)offlineImagePath
{
	NSString *result = nil;
	
	if (myOfflineImagePath)
	{
		result = [myResourcesPath stringByAppendingPathComponent:myOfflineImagePath];
	}
    
    // some services don't have a separate offline image stored in plugin, in which case fallback to online image 
    if ( !result && myOnlineImagePath )
    {
		result = [myResourcesPath stringByAppendingPathComponent:myOnlineImagePath];
    }
	
	return result;
}


#pragma mark -
#pragma mark HTML

- (NSString *)publishingHTMLCode { return myPublishingHTML; }

/*	The live preview HTML if specified. If not, falls back to the publishing HTML
 */
- (NSString *)livePreviewHTMLCode
{
	NSString *result = myLivePreviewHTML;
	
	if (!result || [result isEqualToString:@""])
	{
		result = [self publishingHTMLCode];
	}
	
	return result;
}

- (NSString *)nonLivePreviewHTMLCode
{
	NSString *result = myNonLivePreviewHTML;
	
	if (!result || [result isEqualToString:@""])
	{
		result = [self livePreviewHTMLCode];
	}
	
	return result;
}

@end
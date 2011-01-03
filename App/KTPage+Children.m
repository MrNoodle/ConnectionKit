//
//  KTPage+Collections.m
//  Marvel
//
//  Created by Mike on 30/01/2008.
//  Copyright 2008-2009 Karelia Software. All rights reserved.
//

#import "KTPage.h"

#import "KTSite.h"

#import "NSArray+Karelia.h"
#import "NSError+Karelia.h"
#import "NSManagedObjectContext+KTExtensions.h"
#import "NSObject+Karelia.h"
#import "NSSortDescriptor+Karelia.h"

#import "Debug.h"


@interface KTPage (ChildrenPrivate)

- (void)invalidateSortedChildrenCache;
+ (void)setCollectionIndexForPages:(NSArray *)pages;

+ (NSPredicate *)includeInIndexAndPublishPredicate;
+ (NSSet *)sortedChildrenDependentChildrenKeys;
- (NSArray *)sortDescriptorsForCollectionSortType:(SVCollectionSortOrder)sortType ascending:(BOOL)ascending;

@end


#pragma mark -


@implementation KTPage (Children)

#pragma mark Basic Accessors

/*!	simple wrapper; defined for convenience of calling it.  Not optional property, so this should be OK.
*/
- (BOOL)isCollection	
{
	BOOL result = [[self wrappedValueForKey:@"isCollection"] boolValue];
	return result;		// not an optional property, so it's OK to convert to a non-object
}

- (void)setIsCollection:(BOOL)collection;
{
    [self willChangeValueForKey:@"isCollection"];
    [self setPrimitiveValue:NSBOOL(collection) forKey:@"isCollection"];
    [self didChangeValueForKey:@"isCollection"];
    
    // #93959
    [self setDatePublished:nil];
    [self recursivelyInvalidateURL:YES];
    
    // Regular pages can't take thumbnail from children. #93638
    if (!collection)
    {
        SVThumbnailType thumbType = [[self thumbnailType] intValue];
        if (thumbType == SVThumbnailTypeFirstChildItem ||
            thumbType == SVThumbnailTypeLastChildItem)
        {
            [self setThumbnailType:[NSNumber numberWithInt:SVThumbnailTypeNone]];
        }
    }
}

- (BOOL)willPublishAsCollection; { return [self isCollection]; }
- (void)setWillPublishAsCollection:(BOOL)collection; { }
+ (NSSet *) keyPathsForValuesAffectingWillPublishAsCollection;
{
    return [NSSet setWithObject:@"isCollection"];
}

#pragma mark Children

@dynamic childItems;
- (NSSet *)childItems
{
    [self willAccessValueForKey:@"childItems"];
    NSSet *result = [self primitiveValueForKey:@"childItems"];
    [self didAccessValueForKey:@"childItems"];
    return result;
}

/*	Adds the specified page to the receiver's children relationship.
 *
 *	If the receiver is sorted manually this method behaves like -[NSArray addObject:] and the page is
 *	placed at the end of the list.
 */
- (void)addChildItem:(SVSiteItem *)item
{
	OBPRECONDITION(item);
	OBPRECONDITION([self isCollection]);
	
	
	// If inserting a page into a manually sorted collection, place the page at the end of it
	if ([[self collectionSortOrder] intValue] == SVCollectionSortManually)
	{
		unsigned index = [[[self sortedChildren] lastObject] childIndex] + 1;
		[item setChildIndex:index];
	}
	
	
	// Attach the page to ourself and update the page cache
	[item setValue:self forKey:@"parentPage"];
	[self invalidateSortedChildrenCache];
	
	
	if ([item isKindOfClass:[KTPage class]])
    {
        // As it has a new parent, the page's path must have changed.
        KTPage *page = (KTPage *)item;
        [page recursivelyInvalidateURL:YES];
    }
}


/*	This method is remarkably simple since when you remove a page there is actually no need to update
 *	the childrens' -collectionIndex. They are ultimately still in the right overall order.
 */
- (void)removeChildItem:(SVSiteItem *)item
{
	// Remove the page and update the page cache
	[[self mutableSetValueForKey:@"childItems"] removeObject:item];
	[self invalidateSortedChildrenCache];
}


/*	Batch equivalent of the above method. It's significantly faster because we guarantee that the
 *	-sortedChildren cache will only be invalidated the once.
 */
- (void)removePages:(NSSet *)pages
{
	[[self mutableSetValueForKey:@"childItems"] minusSet:pages];
	[self invalidateSortedChildrenCache];
}

#pragma mark Sorting Properties

@dynamic collectionSortOrder;
- (void)setCollectionSortOrder:(NSNumber *)sorting
{
    [self willChangeValueForKey:@"collectionSortOrder"];
	[self setPrimitiveValue:sorting forKey:@"collectionSortOrder"];
    [self didChangeValueForKey:@"collectionSortOrder"];
	
	// When switching TO manual sorting ensure child indexes are up-to-date
	if ([sorting integerValue] == SVCollectionSortManually)
	{
		[KTPage setCollectionIndexForPages:[self sortedChildren]];
	}
	
	// Since the sort ordering has changed the sortedChildren cache must be invalid
	[self invalidateSortedChildrenCache];
}

- (BOOL)isSortedChronologically;
{
    SVCollectionSortOrder sorting = [[self collectionSortOrder] integerValue];
    BOOL result = (sorting == SVCollectionSortByDateCreated || sorting == SVCollectionSortByDateModified);
    return result;
}

@dynamic collectionSortAscending;
- (void)setCollectionSortAscending:(NSNumber *)sortAscending;
{
    [self willChangeValueForKey:@"collectionSortAscending"];
    [self setPrimitiveValue:sortAscending forKey:@"collectionSortAscending"];
    
    [self invalidateSortedChildrenCache];
    
    [self didChangeValueForKey:@"collectionSortAscending"];
}

#pragma mark Sorted Children

/*	Returns our child pages in the correct ordering.
 *	The result is cached since calculating it is expensive for large collections.
 *	-sortedChildren is KVO-compliant.
 */
- (NSArray *)sortedChildren
{
	NSArray *result = [self wrappedValueForKey:@"sortedChildren"];
	if (!result)
	{
		result = [self childrenWithSorting:SVCollectionSortOrderUnspecified
                                 ascending:[[self collectionSortAscending] boolValue]
                                   inIndex:NO];
        
		[self setPrimitiveValue:result forKey:@"sortedChildren"];
	}
	
	return result;
}

/*	-collectionIndex and -setCollectionIndex are private methods that -sortedChildren uses internally.
 *	The public API for this is the -moveChild:toIndex: method which calls -setCollectionIndex on all affected siblings
 *	and updates the parent's -sortedChildren cache.
 *
 *	Calling this method upon a page with no parent, or within a sorted collection will raise an exception.
 */

- (void)moveChild:(SVSiteItem *)child toIndex:(NSUInteger)index;
{	
	NSAssert1(self, @"-%@ called upon page with not in a collection", NSStringFromSelector(_cmd));
	NSAssert1(([[self collectionSortOrder] integerValue] == SVCollectionSortManually),
              @"-%@ called upon page in a sorted collection", NSStringFromSelector(_cmd));
	
	// Change our index and that of any affected siblings
	NSMutableArray *newSortedChildren = [NSMutableArray arrayWithArray:[self sortedChildren]];
	unsigned whereSelfInParent = [newSortedChildren indexOfObjectIdenticalTo:child];
	
	// Check that we were actually found.  Mystery case 34642.  
	if (whereSelfInParent != NSNotFound && index <= [newSortedChildren count])
	{
		[newSortedChildren moveObjectAtIndex:whereSelfInParent toIndex:index];
		[KTPage setCollectionIndexForPages:newSortedChildren];
		
		// Invalidate our parent's sortedChildren cache
		[self invalidateSortedChildrenCache];
	}
	else
	{
		NSLog(@"%@ trying to move from %d to %d in an array of %d elements",
              NSStringFromSelector(_cmd),
              whereSelfInParent,
              index,
              [newSortedChildren count]);
	}
}


/*	Runs through the pages in the array and makes sure their -collectionIndex property matches
 *	the position in the array.
 *	This is a support method ONLY. It does NOT update any -sortedChildren caches.
 */
+ (void)setCollectionIndexForPages:(NSArray *)pages
{
	unsigned i;
	for (i=0; i<[pages count]; i++)
	{
		KTPage *aPage = [pages objectAtIndex:i];
		[aPage setChildIndex:i];
	}
}

+ (NSSet *)sortedChildrenDependentChildrenKeys
{
	static NSSet *result;
	
	if (!result)
	{
		[NSSet setWithObjects:@"previousPage", @"nextPage", nil];
	}
	
	return result;
}

- (void)invalidateSortedChildrenCache
{
	// Clear the cache
	[self willChangeValueForKey:@"sortedChildren"];
	
	[self setPrimitiveValue:nil forKey:@"sortedChildren"];
	
	[self didChangeValueForKey:@"sortedChildren"];
	
	
	// Also, the site menu may well have been affected
	[[self site] invalidatePagesInSiteMenuCache];
}


#pragma mark Sorting Support

/*	Public support method that will return the receiver's children with the specified sorting.
 *	If ignoreDrafts==YES then UNPUBLISHED drafts are filtered out.
 *	Not cached like -sortedChildren.
*/
- (NSArray *)childrenWithSorting:(SVCollectionSortOrder)sortType
                       ascending:(BOOL)ascending
                         inIndex:(BOOL)ignoreDrafts;
{
	NSArray *result = [[self childItems] allObjects];
	
	
	// Filter out drafts if requested
	if (ignoreDrafts)
	{
		result = [result filteredArrayUsingPredicate:[[self class] includeInIndexAndPublishPredicate]];
	}
	
	
	// Sometimes there's no point in sorting
	if ([result count] > 1)
	{		
		// Do the sort
		NSArray *sortDescriptors = [self sortDescriptorsForCollectionSortType:sortType ascending:ascending];
        
		result = [result sortedArrayUsingDescriptors:sortDescriptors];
	}	
	
	
	return result;
}
		
+ (NSPredicate *)includeInIndexAndPublishPredicate
{
	static NSPredicate *result;
	if (!result)
	{
		result = [[NSPredicate predicateWithFormat:@"shouldIncludeInIndexes == 1"] retain];
	}
	
	return result;
}

- (NSArray *)childItemsSortDescriptors;
{
    return [self
            sortDescriptorsForCollectionSortType:[[self collectionSortOrder] intValue]
            ascending:[[self collectionSortAscending] boolValue]];
}
+ (NSSet *)keyPathsForValuesAffectingChildItemsSortDescriptors;
{
    return [NSSet setWithObjects:@"collectionSortOrder", @"collectionSortAscending", nil];
}

/*	Translates between KTCollectionSortType & the right sort descriptor objects
 */
- (NSArray *)sortDescriptorsForCollectionSortType:(SVCollectionSortOrder)sortType ascending:(BOOL)ascending;
{
	NSArray *result;
	switch (sortType)
	{
		case SVCollectionSortOrderUnspecified:	// Use whatever is currently selected for this collection
			result = [self sortDescriptorsForCollectionSortType:[[self collectionSortOrder] integerValue]
                                                      ascending:ascending];
			break;
		case SVCollectionSortAlphabetically:
			result = [KTPage alphabeticalTitleTextSortDescriptorsAscending:ascending];
			break;
		case SVCollectionSortByDateCreated:
			result = [KTPage dateCreatedSortDescriptorsAscending:ascending];
			break;
		case SVCollectionSortByDateModified:
			result = [KTPage dateCreatedSortDescriptorsAscending:ascending];
			break;
		default:
			result = [KTPage unsortedPagesSortDescriptors];	// use the "childIndex" values
			break;
	}
	
	return result;
}

+ (NSArray *)unsortedPagesSortDescriptors;
{
	static NSArray *result;
	
	if (!result)
	{
		NSSortDescriptor *orderingDescriptor = [[NSSortDescriptor alloc] initWithKey:@"childIndex" ascending:YES];
		result = [[NSArray alloc] initWithObjects:orderingDescriptor, nil];
		[orderingDescriptor release];
	}
	
	return result;
}

+ (NSArray *)alphabeticalTitleTextSortDescriptorsAscending:(BOOL)ascending;
{
    NSSortDescriptor *orderingDescriptor = [[NSSortDescriptor alloc] initWithKey:@"title"
                                                                       ascending:ascending
                                                                        selector:@selector(caseInsensitiveCompare:)];
    
	NSArray *result = [NSArray arrayWithObject:orderingDescriptor];
    [orderingDescriptor release];
	
	return result;
}

+ (NSArray *)dateCreatedSortDescriptorsAscending:(BOOL)ascending;
{
	NSArray *result = nil;
	
	if (!result)
	{
		NSSortDescriptor *orderingDescriptor = [[NSSortDescriptor alloc] initWithKey:@"creationDate"
                                                                           ascending:ascending];
		result = [[[NSArray alloc] initWithObject:orderingDescriptor] autorelease];
		[orderingDescriptor release];
	}
	
	return result;
}

+ (NSArray *)dateModifiedSortDescriptorsAscending:(BOOL)ascending;
{
	NSArray *result = nil;
	
	if (!result)
	{
		NSSortDescriptor *orderingDescriptor = [[NSSortDescriptor alloc] initWithKey:@"modificationDate" 
                                                                           ascending:ascending];
		result = [[[NSArray alloc] initWithObject:orderingDescriptor] autorelease];
		[orderingDescriptor release];
	}
	
	return result;
}

#pragma mark Page Hierarchy Queries

- (BOOL)isRootPage; // like NSTreeNode, the root page is defined to be one with no parent. This is just a convenience around that
{
    BOOL result = ([self parentPage] == nil);
    return result;
}

- (KTPage *)rootPage;   // searches up the tree till it finds a page with no parent
{
    KTPage *result = ([self isRootPage] ? self : [[self parentPage] rootPage]);
    return result;
}

- (KTPage *)parentOrRoot
{
	KTPage *result = [self parentPage];
	if (nil == result)
	{
		result = self;
	}
	return result;
}

/*	Every page bar root should have a parent.
 */
- (BOOL)validateParentPage:(KTPage **)page error:(NSError **)outError;
{
	if ([self isRoot])
    {
        return YES;
    }
    else
    {
        return [super validateParentPage:page error:outError];
    }
}

- (BOOL)hasChildren
{
	NSSet *children = [self childItems];
	BOOL result = ([children count] > 0);
	return result;
}

#pragma mark Navigation Arrows

@dynamic navigationArrowsStyle;

#pragma mark -
#pragma mark Should probably be deprecated

+ (NSArray *)orderingSortDescriptors
{
	static NSArray *result;
	
	if (!result)
	{
		NSSortDescriptor *orderingDescriptor = [[NSSortDescriptor alloc] initWithKey:@"ordering" ascending:YES];
		result = [[NSArray alloc] initWithObjects:orderingDescriptor, nil];
		[orderingDescriptor release];
	}
	
	return result;
}

/*! returns a suggested ordering value for inserting aProposedChild
	based on aSortType -- used for intra-app dragging */
- (int)proposedOrderingForProposedChild:(id)aProposedChild
							   sortType:(SVCollectionSortOrder)aSortType
                              ascending:(BOOL)ascending;
{
    NSSet *values = [self childItems];
	
	if (0 == [values count])
	{
		// if there are no other children, stick aProposedChild at the top
		return 0;
	}
	
	int result = 0;
	// copy the array
	NSMutableArray *childArray = [[values allObjects] mutableCopy];
	// stick aProposedChild in the array
	[childArray addObject:aProposedChild];
	// sort it
	NSArray *descriptors = nil;
	switch ( aSortType )
	{
		case SVCollectionSortAlphabetically:
			descriptors = [KTPage alphabeticalTitleTextSortDescriptorsAscending:ascending];
			break;
		case SVCollectionSortByDateCreated:
			descriptors = [KTPage dateCreatedSortDescriptorsAscending:ascending];
			break;
		case SVCollectionSortByDateModified:
			descriptors = [KTPage dateModifiedSortDescriptorsAscending:ascending];
			break;
		default:
			descriptors = [KTPage orderingSortDescriptors];	// use the "ordering" values
			break;
	}
	[childArray sortUsingDescriptors:descriptors];
	// return the index of aProposedChild in the sorted array
	result = [childArray indexOfObject:aProposedChild];
	[childArray release];
	
	//LOG((@"return proposed child drop index: %i", result));
	return result;
}

- (int)proposedOrderingForProposedChildWithTitle:(NSString *)aTitle
{
	// we'll add _zzz to the end of the title so that it's hopefully different
	// just in case the list already has seven things called "Untitled Page"
	NSString *sortableTitle = [aTitle stringByAppendingString:@"_zzz"];
	
	NSMutableArray *titlesArray = [NSMutableArray array];
	[titlesArray addObject:sortableTitle];
	
    NSSet *children = [self childItems];
	
	KTPage *child;
	for ( child in children )
	{
		[titlesArray addObject:[child title]];
	}
	[titlesArray sortUsingSelector:@selector(caseInsensitiveCompare:)];
	int result = [titlesArray indexOfObject:sortableTitle];
	
	//LOG((@"return proposed child drop index: %i sortedArray: %@", result, sortedArray));
	return result;
}

@end

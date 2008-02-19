//
//  KTInlineImageElement.m
//  KTComponents
//
//  Created by Terrence Talbot on 8/14/05.
//  Copyright 2005 Biophony LLC. All rights reserved.
//

#import "KTInlineImageElement.h"

#import "KTDesign.h"
#import "KTImageView.h"
#import "KTMaster.h"
#import "KTPathInfoField.h"

#import "NSImage+Karelia.h"

#import <WebKit/WebKit.h>


@interface KTInlineImageElement ( Private )
@end


@implementation KTInlineImageElement

#pragma mark Class Methods

+ (KTInlineImageElement *)inlineImageElementWithID:(NSString *)uniqueID
										   DOMNode:(DOMHTMLImageElement *)aDOMNode 
										 container:(KTAbstractPlugin *)aContainer
{
	KTInlineImageElement *element = [[self alloc] initWithDOMNode:aDOMNode container:aContainer];
	element->myUID = [uniqueID copy];
	
	
	// Figure out our position
	NSString *className = [aDOMNode className];
	int position = kInlineImage;
	if (NSNotFound != [className rangeOfString:@"wide"].location)
	{
		position = kBlockImage;
	}
	else if (NSNotFound != [className rangeOfString:@"narrow"].location)
	{
		position = kFloatImage;
	}
	[element setPrimitiveValue:[NSNumber numberWithInt:position] forKey:@"position"];
	
	
	// Load other accessors
	[element setPrimitiveValue:[aDOMNode alt] forKey:@"altText"];
	
	NSURL *mediaURI = [NSURL URLWithString:[aDOMNode src]];
	KTMediaContainer *media = [KTMediaContainer mediaContainerForURI:mediaURI];
	[element setPrimitiveValue:media forKey:@"image"];
	
	// Enable undo
	//[element setAutomaticUndoIsEnabled:YES];
	
	return [element autorelease];
}

#pragma mark -
#pragma mark Init & Dealloc

- (void)dealloc
{
	[myUID release];
	[super dealloc];
}

#pragma mark Accessors

- (KTMediaContainer *)image { return [self primitiveValueForKey:@"image"]; }

- (void)setImage:(KTMediaContainer *)image
{
	// Register the undo op
	NSUndoManager *undoManager = [[[[[self DOMNode] ownerDocument] webFrame] webView] undoManager];
	[undoManager registerUndoWithTarget:self selector:@selector(setImage:) object:[self image]];
	
	
	// Make the change
	[self willChangeValueForKey:@"image"];
	[self setPrimitiveValue:image forKey:@"image"];
	[self didChangeValueForKey:@"image"];
	
	
	// Figure out the maximum image size
	KTAbstractPlugin *container = [self container];
	NSString *imageScalingSettings = nil;
	if ([container isKindOfClass:[KTPagelet class]])
	{
		imageScalingSettings = @"sidebarImage";
	}
	else
	{
		// TODO: could we vary the size based on whether the page is showing a sidebar?
		imageScalingSettings = @"inTextMediumImage";
	}
	
	
	// Scale the image
	KTMediaContainer *scaledImage = [image imageWithScalingSettingsNamed:imageScalingSettings forPlugin:[self container]];
	
		
	// Adjust the DOM to the new image
	[(DOMHTMLImageElement *)[self DOMNode] setSrc:[[scaledImage URIRepresentation] absoluteString]];
}

- (NSString *)altText {	return [self primitiveValueForKey:@"altText"]; }

- (void)setAltText:(NSString *)aString
{
	// Register the undo op
	NSUndoManager *undoManager = [[[[[self DOMNode] ownerDocument] webFrame] webView] undoManager];
	[undoManager registerUndoWithTarget:self selector:@selector(setAltText:) object:[self altText]];
	
	
	[self willChangeValueForKey:@"altText"];
	[self setPrimitiveValue:aString forKey:@"altText"];
	[self didChangeValueForKey:@"altText"];
	
	// Modify DOM
	if (nil == aString) aString = @"";	// don't let it be nil
	[(DOMHTMLImageElement *)[self DOMNode] setAlt:aString];
}

- (int)position { return [[self primitiveValueForKey:@"position"] intValue]; }

- (void)setPosition:(int)aPosition
{
	// Register the undo op
	NSUndoManager *undoManager = [[[[[self DOMNode] ownerDocument] webFrame] webView] undoManager];
	[(KTInlineImageElement *)[undoManager prepareWithInvocationTarget:self] setPosition:[self position]];
	
	
	[self willChangeValueForKey:@"position"];
	[self setPrimitiveValue:[NSNumber numberWithInt:aPosition] forKey:@"position"];
	[self didChangeValueForKey:@"position"];
	
	// modify DOM
	switch (aPosition)
	{
		case kBlockImage:
			[(DOMHTMLImageElement *)[self DOMNode] setClassName:@"wide"];
			break;
		case kFloatImage:
			[(DOMHTMLImageElement *)[self DOMNode] setClassName:@"narrow"];
			break;
		case kInlineImage:
			[(DOMHTMLImageElement *)[self DOMNode] removeAttribute:@"class"];
			break;
	}
}

#pragma mark -
#pragma mark Inspector

- (NSString *)uniqueID { return myUID; }

- (NSString *)inspectorNibName { return @"InlineImageElement"; }

- (KTDocument *)document { return [[self container] document]; }

// this code is almost entirely lifted from ImageElementDelegate

- (IBAction)chooseImage:(id)sender
{
	NSOpenPanel *imageChooser = [NSOpenPanel openPanel];
	[imageChooser setCanChooseDirectories:NO];
	[imageChooser setAllowsMultipleSelection:NO];
	[imageChooser setPrompt:NSLocalizedString(@"Choose", "choose - open panel")];
	
	// TODO: Open the panel at a reasonable location
	[imageChooser runModalForDirectory:nil
								  file:nil
								 types:[NSImage imageFileTypes]];
	
	NSArray *selectedPaths = [imageChooser filenames];
	if (!selectedPaths || [selectedPaths count] == 0) 
	{
		return;
	}
	
	KTMediaContainer *image = [[[self container] mediaManager] mediaContainerWithPath:[selectedPaths firstObject]];
	[self setImage:image];
}

- (BOOL)pathInfoField:(KTPathInfoField *)field
 performDragOperation:(id <NSDraggingInfo>)sender
	 expectedDropType:(NSDragOperation)dragOp
{
	BOOL fileShouldBeExternal = NO;
	if (dragOp & NSDragOperationLink)
	{
		fileShouldBeExternal = YES;
	}
	
	KTMediaContainer *image = [[[self container] mediaManager] mediaContainerWithDraggingInfo:sender
																		   preferExternalFile:fileShouldBeExternal];
	[self setImage:image];
	
	return YES;
}

- (NSArray *)supportedDragTypesForPathInfoField:(KTPathInfoField *)pathInfoField
{
	return [NSImage imagePasteboardTypes];
}

- (BOOL)pathInfoField:(KTPathInfoField *)filed shouldAllowFileDrop:(NSString *)path
{
	BOOL result = NO;
	
	if ([NSString UTI:[NSString UTIForFileAtPath:path] conformsToUTI:(NSString *)kUTTypeImage])
	{
		result = YES;
	} 
	
	return result;
}

@end

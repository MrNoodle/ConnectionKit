//
//  KTPublishingWindowController.m
//  Marvel
//
//  Created by Mike on 08/12/2008.
//  Copyright 2008 Karelia Software. All rights reserved.
//

#import "KTPublishingWindowController.h"

#import "KTDocumentInfo.h"
#import "KTDocWindowController.h"
#import "KTHostProperties.h"

#import "NSApplication+Karelia.h"
#import "NSWorkspace+Karelia.h"

#import <Connection/Connection.h>
#import <Growl/Growl.h>


@implementation KTPublishingWindowController

#pragma mark -
#pragma mark Growl Support

+ (void)initialize
{
    // Bit of a hack until we have a proper growl controller
    [GrowlApplicationBridge setGrowlDelegate:(id)[KTPublishingWindowController class]];
}

+ (NSDictionary *)registrationDictionaryForGrowl
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	NSArray *strings = [NSArray arrayWithObjects:
                        NSLocalizedString(@"Publishing Complete", @"Growl notification"), 
                        NSLocalizedString(@"Export Complete", @"Growl notification"), nil];
	[dict setObject:strings
			 forKey:GROWL_NOTIFICATIONS_ALL];
	[dict setObject:strings
			 forKey:GROWL_NOTIFICATIONS_DEFAULT];
	return dict;
}

+ (NSString *)applicationNameForGrowl
{
	return [NSApplication applicationName];
}

/*  If the user clicks a notification with a URL, open it.
 */
+ (void)growlNotificationWasClicked:(id)clickContext
{
	if (clickContext && [clickContext isKindOfClass:[NSString class]])
	{
		NSURL *URL = [[NSURL alloc] initWithString:clickContext];
        if (URL)
		{
			[[NSWorkspace sharedWorkspace] attemptToOpenWebURL:URL];
			[URL release];
		}
	}
}

#pragma mark -
#pragma mark Init & Dealloc

- (id)initWithPublishingEngine:(KTPublishingEngine *)engine
{
    if (self = [self initWithWindowNibName:@"Publishing"])
    {
        _publishingEngine = [engine retain];
        [engine setDelegate:self];
        
        // Get notified when transfers start or end
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transferDidBegin:)
                                                     name:CKTransferRecordTransferDidBeginNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(transferDidFinish:)
                                                     name:CKTransferRecordTransferDidFinishNotification
                                                   object:nil];
    }
    
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [_currentTransfer release];
    [_publishingEngine setDelegate:nil];
    [_publishingEngine release];
    
    [super dealloc];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // There's a minimum of localized text in this nib, so we're handling it in entirely in code
    if ([self isExporting])
    {
        [oMessageLabel setStringValue:NSLocalizedString(@"Exporting…", @"Publishing sheet title")];
        [oInformativeTextLabel setStringValue:NSLocalizedString(@"Preparing to export…", @"Uploading progress info")];
    }
    else
    {
        [oMessageLabel setStringValue:NSLocalizedString(@"Publishing…", @"Publishing sheet title")];
        [oInformativeTextLabel setStringValue:NSLocalizedString(@"Preparing to upload…", @"Uploading progress info")];
    }
    
    // TODO: Ensure the button is wide enough for e.g. German
    [oFirstButton setTitle:NSLocalizedString(@"Stop", @"Stop publishing button title")];
    
    // Outline view uses special cell class
    NSCell *cell = [[CKTransferProgressCell alloc] initTextCell:@""];
    [oTransferDetailsTableColumn setDataCell:cell];
    [cell release];
    
    // Start progress indicator
    [oProgressIndicator startAnimation:self];
}

#pragma mark -
#pragma mark Actions

- (IBAction)firstButtonAction:(NSButton *)sender
{
    [self endSheet];
}

#pragma mark -
#pragma mark Publishing Engine

- (KTPublishingEngine *)publishingEngine;
{
    return _publishingEngine;
}

- (BOOL)isExporting
{
    BOOL result = ![[self publishingEngine] isKindOfClass:[KTRemotePublishingEngine class]];
    return result;
}

/*  Once we know how much to upload, the progress bar can become determinate
 */
- (void)publishingEngineDidFinishGeneratingContent:(KTPublishingEngine *)engine
{
    [oProgressIndicator setIndeterminate:NO];
}

- (void)publishingEngineDidUpdateProgress:(KTPublishingEngine *)engine
{
    
    [oProgressIndicator setDoubleValue:[[engine rootTransferRecord] progress]];
}

/*  We're done publishing, close the window.
 */
- (void)publishingEngineDidFinish:(KTPublishingEngine *)engine
{
    // Post Growl notification
    if ([self isExporting])
    {
        [GrowlApplicationBridge notifyWithTitle:NSLocalizedString(@"Export Complete", "Growl notification")
                                    description:NSLocalizedString(@"Your site has been exported", "Growl notification")
                               notificationName:NSLocalizedString(@"Export Complete", "Growl notification")
                                       iconData:nil
                                       priority:1
                                       isSticky:NO
                                   clickContext:nil];
    }
    else
    {
        NSURL *siteURL = [[[engine site] hostProperties] siteURL];
        
        NSString *descriptionText;
        if ([[[engine connection] URL] isFileURL])
        {
            descriptionText = NSLocalizedString(@"The site has been published to this computer.", "Transfer Controller");
        }
        else
        {
            descriptionText = [NSString stringWithFormat:
                               NSLocalizedString(@"The site has been published to %@.", "Transfer Controller"),
                               [siteURL absoluteString]];
        }
        
        [GrowlApplicationBridge notifyWithTitle:NSLocalizedString(@"Publishing Complete", @"Growl notification")
                                    description:descriptionText
                               notificationName:NSLocalizedString(@"Publishing Complete", @"Growl notification")
                                       iconData:nil
                                       priority:1
                                       isSticky:NO
                                   clickContext:[siteURL absoluteString]];
    }
    
    
    
    [self endSheet];
}

- (void)publishingEngine:(KTPublishingEngine *)engine didFailWithError:(NSError *)error
{
    _didFail = YES;
    
    // If publishing changes and there are none, it fails with a fake error message
    if ([[error domain] isEqualToString:@"NothingToPublish fake error domain"])
    {
        KTDocWindowController *windowController = [_modalWindow windowController];
        OBASSERT(windowController); // This is a slightly hacky way to get to the controller, but it works
        
        [self endSheet];  // Act like the user cancelled
        
        // Put up an alert explaining why and let the window controller deal with it
        NSAlert *alert = [[NSAlert alloc] init];    // The window controller will release it
        [alert setMessageText:NSLocalizedString(@"No changes need publishing.", @"message for progress window")];
        [alert setInformativeText:NSLocalizedString(@"Sandvox has detected that no content has changed since the site was last published. Publish All will upload all content, regardless of whether it has changed or not.", "alert info text")];
        [alert addButtonWithTitle:NSLocalizedString(@"OK", @"change cancel button to ok")];
        [alert addButtonWithTitle:NSLocalizedString(@"Publish All", @"")];
        
        [alert beginSheetModalForWindow:[windowController window]
                          modalDelegate:windowController
                         didEndSelector:@selector(noChangesToPublishAlertDidEnd:returnCode:contextInfo:)
                            contextInfo:NULL];
    }
    else
    {
        [oMessageLabel setStringValue:NSLocalizedString(@"Publishing failed.", @"Upload message text")];
        
        [oInformativeTextLabel setTextColor:[NSColor redColor]];
        NSString *errorDescription = [error localizedDescription];
        if (errorDescription) [oInformativeTextLabel setStringValue:errorDescription];
        
        [oProgressIndicator stopAnimation:self];
        
        [oFirstButton setTitle:NSLocalizedString(@"Close", @"Button title")];
    }
}

#pragma mark -
#pragma mark Current Transfer

- (CKTransferRecord *)currentTransfer { return _currentTransfer; }

- (void)setCurrentTransfer:(CKTransferRecord *)transferRecord
{
    [transferRecord retain];
    [_currentTransfer release];
    _currentTransfer = transferRecord;
    
    if (transferRecord && [transferRecord name])
    {
        NSString *text = [[NSString alloc] initWithFormat:
                          NSLocalizedString(@"Uploading “%@”", @"Upload information"),
                          [transferRecord name]];
        [oInformativeTextLabel setStringValue:text];
        [text release];
    }
}

// FIXME: These 2 methods are getting called for ALL transfers. You'll see weird things if there are 2 documents publishing at the same time

- (void)transferDidBegin:(NSNotification *)notification
{
    [self setCurrentTransfer:[notification object]];
}

- (void)transferDidFinish:(NSNotification *)notification
{
    CKTransferRecord *transferRecord = [notification object];
    if (transferRecord == [self currentTransfer])
    {
        [self setCurrentTransfer:nil];
    }
}

#pragma mark -
#pragma mark Outline View

/*  There's no point allowing the user to select items in the publishing sheet.
 */
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item
{
    return NO;
}

#pragma mark -
#pragma mark Presentation

- (void)beginSheetModalForWindow:(NSWindow *)window
{
    OBASSERT(!_modalWindow);    // You shouldn't be able to make the window modal twice
    
    [self retain];  // Ensures we're not accidentally deallocated during presentation. Will release later
    _modalWindow = window;  // Weak ref
    
    [NSApp beginSheet:[self window]
       modalForWindow:window
        modalDelegate:nil
       didEndSelector:nil
          contextInfo:NULL];
    
    // Ready to start
    [[self publishingEngine] start];
}

/*  Outside code shouldn't need to call this, we should handle it ourselves from clicking
 *  the Close or Stop button.
 */
- (void)endSheet;
{
    if (![[self publishingEngine] hasFinished])
    {
        [[self publishingEngine] cancel];
    }
    
    OBASSERT(_modalWindow);
    _modalWindow = nil;
    
    [NSApp endSheet:[self window]];
    [[self window] orderOut:self];
    
    [self release]; // To balance the -retain when beginning the sheet.
}

@end

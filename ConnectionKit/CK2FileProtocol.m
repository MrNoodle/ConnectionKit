//
//  CK2FileProtocol.m
//  Connection
//
//  Created by Mike on 18/10/2012.
//
//

#import "CK2FileProtocol.h"

#import "CK2CURLBasedProtocol.h"

// alternate implementations for initForCreatingFileWithRequest
// whilst we're developing, I'm keeping around the code for all of them
typedef enum
{
    kCreateWithCURL,
    kCreateWithStreams,
    kCreateWithPOSIXAndGCD
} CreateMode;

static const CreateMode kCreateMode = kCreateWithPOSIXAndGCD;

static size_t kCopyBufferSize = 4096;

@interface CK2FileProtocol()

@property (assign, nonatomic) dispatch_queue_t queue;

@end

@implementation CK2FileProtocol

+ (BOOL)canHandleURL:(NSURL *)url;
{
    return [url isFileURL];
}

- (id)initWithBlock:(void (^)(void))block;
{
    if (self = [self init])
    {
        NSAssert(block != nil, @"should have a valid block");
        _block = [block copy];
    }
    
    return self;
}

- (void)dealloc
{
    if (_queue)
    {
        dispatch_release(_queue);
    }

    [_block release];
    [super dealloc];
}

- (id)initForEnumeratingDirectoryWithRequest:(NSURLRequest *)request includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        // Enumerate contents
        NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[request URL]
                                                                 includingPropertiesForKeys:keys
                                                                                    options:mask
                                                                               errorHandler:^BOOL(NSURL *url, NSError *error) {
            
                                                                                   NSLog(@"enumeration error: %@", error);
                                                                                   return YES;
                                                                               }];
                
        BOOL reportedDirectory = NO;
        
        NSURL *aURL;
        while (aURL = [enumerator nextObject])
        {
            // Report the main directory first
            if (!reportedDirectory)
            {
                [client protocol:self didDiscoverItemAtURL:[request URL]];
                reportedDirectory = YES;
            }
            
            [client protocol:self didDiscoverItemAtURL:aURL];
        }
                
        [client protocolDidFinish:self];
    }];
}

- (id)initForCreatingDirectoryWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] createDirectoryAtURL:[request URL] withIntermediateDirectories:createIntermediates attributes:attributes error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}


- (id)initForCreatingFileWithRequest:(NSURLRequest *)request withIntermediateDirectories:(BOOL)createIntermediates openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock;
{
    return [self initWithBlock:^{
        
        // Sadly libcurl doesn't support creating intermediate directories for local files, so do it ourself
        if (createIntermediates)
        {
            NSError *error;
            NSURL* intermediates = [[request URL] URLByDeletingLastPathComponent];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:intermediates withIntermediateDirectories:YES attributes:nil error:&error])
            {
                [client protocol:self didFailWithError:error];
                return;
            }
        }

        // whilst testing, support all three creation methods
        switch (kCreateMode)
        {
            case kCreateWithCURL:
            {
                [self createFileWithCURLForRequest:request openingAttributes:attributes client:client progressBlock:progressBlock];
                break;
            }

            case kCreateWithStreams:
            {
                [self createFileSyncForRequest:request openingAttributes:attributes client:client progressBlock:progressBlock];
                break;
            }

            default:
                [self createFileAsyncForRequest:request openingAttributes:attributes client:client progressBlock:progressBlock];
        }
    }];
}

- (id)initForRemovingFileWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
                
        NSError *error;
        if ([[NSFileManager defaultManager] removeItemAtURL:[request URL] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (id)initForSettingAttributes:(NSDictionary *)keyedValues ofItemWithRequest:(NSURLRequest *)request client:(id<CK2ProtocolClient>)client;
{
    return [self initWithBlock:^{
        
        NSError *error;
        if ([[NSFileManager defaultManager] setAttributes:keyedValues ofItemAtPath:[[request URL] path] error:&error])
        {
            [client protocolDidFinish:self];
        }
        else
        {
            [client protocol:self didFailWithError:error];
        }
    }];
}

- (void)start;
{
    _block();
}

#pragma mark - File Copying

- (NSError*)modifiedErrorForFileError:(NSError*)error
{
    if ([error.domain isEqualToString:NSPOSIXErrorDomain])
    {
        if (error.code == ENOENT)
        {
            error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
        }
        else if (error.code == EACCES)
        {
            error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:[NSDictionary dictionaryWithObject:error forKey:NSUnderlyingErrorKey]];
        }
    }

    return error;
}

- (NSError*)noInputStreamError
{
    NSError* error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:nil];

    return error;
}

- (NSError*)currentPOSIXError
{
    return [self modifiedErrorForFileError:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
}

- (NSInputStream*)inputStreamForRequest:(NSURLRequest*)request
{
    NSInputStream *inputStream = nil;
    NSData* inputData = [request HTTPBody];
    if (inputData)
    {
        inputStream = [[[NSInputStream alloc] initWithData:inputData] autorelease];
    }
    else
    {
        inputStream = [request HTTPBodyStream];
    }

    return inputStream;
}

/**
 File creation implementation that uses CURLHandle.
 The main problem with this is that CURLHandle doesn't return very good error information.
 */

- (void)createFileWithCURLForRequest:(NSURLRequest*)request openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock
{
    // Hand off to CURLHandle to create the file
    __block CK2CURLBasedProtocol *curlProtocol = [[CK2CURLBasedProtocol alloc] initWithRequest:request client:nil progressBlock:progressBlock completionHandler:^(NSError *error) {

        if (error)
        {
            [client protocol:self didFailWithError:error];
        }
        else
        {
            [client protocolDidFinish:self];
        }

        [curlProtocol autorelease];
    }];

    [curlProtocol start];
}

/**
 Simple file creation implementation which just works synchronously, copying between two streams.
 */

- (void)createFileSyncForRequest:(NSURLRequest*)request openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock
{
    NSInputStream *inputStream = [self inputStreamForRequest:request];
    [inputStream open];

    NSOutputStream *outputStream = [[NSOutputStream alloc] initWithURL:[request URL] append:NO];
    [outputStream open];

    NSError* error = nil;
    if (inputStream && outputStream)
    {
        uint8_t buffer[kCopyBufferSize];
        while ([inputStream hasBytesAvailable])
        {
            NSInteger length = [inputStream read:buffer maxLength:kCopyBufferSize];
            if (length < 0)
            {
                error = [inputStream streamError];
                break;
            }

            NSUInteger written = [outputStream write:buffer maxLength:length];
            if (written != length)
            {
                error = [outputStream streamError];
                break;
            }

            if (progressBlock)
            {
                progressBlock(length);
            }
        }
        
        [inputStream close];
        [outputStream close];
        [outputStream release];
    }
    else
    {
        error = [self noInputStreamError];
    }

    if (error)
    {
        [client protocol:self didFailWithError:[self modifiedErrorForFileError:error]];
    }
    else
    {
        [client protocolDidFinish:self];
    }
}

/**
 File creation implementation which works asynchronously.
 We open an input stream for the input.
 We open an output file for writing using POSIX open/write calls.
 We then attach a gcd dispatch source to it, and use that to pull input from the stream and write it to the file.
 
 We make a dedicated queue to attach the source to, and release it in the cancel handler of the source, so
 it only lives for the duration of the operation.
 */

- (void)createFileAsyncForRequest:(NSURLRequest*)request openingAttributes:(NSDictionary *)attributes client:(id<CK2ProtocolClient>)client progressBlock:(void (^)(NSUInteger))progressBlock
{
    NSInputStream *inputStream = [self inputStreamForRequest:request];
    NSError* error = nil;

    if (inputStream != nil)
    {
        [inputStream open];

        NSURL* url = [request URL];
        NSAssert([url isFileURL], @"wrong URL scheme: %@", url);
        NSString* path = [url path];
        int perms = [[attributes objectForKey:NSFilePosixPermissions] int32Value];
        if (perms == 0)
        {
            perms = 0744;
        }
        int outfile = open([path UTF8String], O_CREAT | O_TRUNC | O_WRONLY, perms);
        if (outfile != -1)
        {
            dispatch_queue_t queue = dispatch_queue_create("CK2FileProtocol", NULL);
            dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, outfile, 0, queue);

            dispatch_source_set_event_handler(source, ^{
                uint8_t buffer[kCopyBufferSize];
                NSInteger length = [inputStream read:buffer maxLength:kCopyBufferSize];
                if (length < 0)
                {
                    dispatch_source_cancel(source);
                    [client protocol:self didFailWithError:[self modifiedErrorForFileError:[inputStream streamError]]];
                }
                else if (length == 0)
                {
                    dispatch_source_cancel(source);
                    [client protocolDidFinish:self];
                }
                else
                {
                    ssize_t written = write(outfile, buffer, length);
                    if (written != length)
                    {
                        [client protocol:self didFailWithError:[self currentPOSIXError]];
                    }
                }
            });

            dispatch_source_set_cancel_handler(source, ^{
                close(outfile);
                dispatch_release(source);
                dispatch_release(queue);
            });
            
            dispatch_resume(source);
        }
        else
        {
            error = [self currentPOSIXError];
        }
    }
    else
    {
        error = [self noInputStreamError];
    }

    if (error)
    {
        [client protocol:self didFailWithError:error];
    }
}

@end

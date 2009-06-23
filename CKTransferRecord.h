/*
 Copyright (c) 2006, Greg Hulands <ghulands@mac.com>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Greg Hulands nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

@protocol CKConnection;

extern NSString *CKTransferRecordProgressChangedNotification;
extern NSString *CKTransferRecordTransferDidBeginNotification;
extern NSString *CKTransferRecordTransferDidFinishNotification;

@interface CKTransferRecord : NSObject <NSCopying>
{
	BOOL _isUpload;
	BOOL _isDirectory;
	BOOL _isDiscoveringFilesToDownload;
	NSString *_localPath;
	NSString *_remotePath;
	
	unsigned long long _sizeInBytes;
	unsigned long long _sizeInBytesWithChildren;
	unsigned long long _bytesTransferred;
	unsigned long long _bytesTransferredSinceLastSpeedUpdate;

	NSTimeInterval _lastSpeedUpdateTime;
	NSTimeInterval _transferStartTime;
	NSTimeInterval _lastDirectorySpeedUpdateTime;
	
	float _speed;
	NSUInteger _progress;
	NSMutableArray *_children;
	CKTransferRecord *_parent; //not retained
	NSMutableDictionary *_properties;
	
	id <CKConnection> _connection; //not retained
	NSError *_error;
}

/**
	@method uploadRecordForConnection:sourceLocalPath:destinationRemotePath:size:isDirectory:
	@abstract The designed initializer for upload records.
	@result A transfer-record representing the transfer.
 */
+ (CKTransferRecord *)uploadRecordForConnection:(id <CKConnection>)connection
								sourceLocalPath:(NSString *)sourceLocalPath 
						  destinationRemotePath:(NSString *)destinationRemotePath
										   size:(unsigned long long)size 
									isDirectory:(BOOL)isDirectoryFlag;

/**
	@method downloadRecordForConnection:sourceRemotePath:destinationLocalPath:size:
	@abstract The designed initializer for download records.
	@result A transfer-record representing the transfer.
 */
+ (CKTransferRecord *)downloadRecordForConnection:(id <CKConnection>)connection
								 sourceRemotePath:(NSString *)sourceRemotePath
							 destinationLocalPath:(NSString *)destinationLocalPath
											 size:(unsigned long long)size
									  isDirectory:(BOOL)isDirectoryFlag;

- (CKTransferRecord *)root;
- (void)setParent:(CKTransferRecord *)parent;
- (CKTransferRecord *)parent;

- (NSString *)name;
- (void)setLocalPath:(NSString *)newLocalPath;
- (NSString *)localPath;
- (void)setRemotePath:(NSString *)newRemotePath;
- (NSString *)remotePath;

- (void)setIsDiscoveringFilesToDownload:(BOOL)flag;
/**
	@method isDiscoveringFilesToDownload
	@abstract An indicator of whether or not the receiver is in the process of discovering files (recursively) to download.
 */
- (BOOL)isDiscoveringFilesToDownload;

- (BOOL)isUpload;
- (BOOL)isDirectory;

- (void)setConnection:(id <CKConnection>)connection;
- (id <CKConnection>)connection;
- (void)cancel:(id)sender;

- (void)addChild:(CKTransferRecord *)record;
- (NSArray *)children;
/**
	@method childTransferRecordForRemotePath:
	@abstract Fetches the child transfer record that corresponds to the provided path.
	@param remotePath The remote path of a transfer record.
	@result The transfer record corresponding to remotePath
 */
- (CKTransferRecord *)childTransferRecordForRemotePath:(NSString *)remotePath;

- (void)setProperty:(id)property forKey:(id)key;
- (id)propertyForKey:(id)key;
- (void)removePropertyForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (id)objectForKey:(id)key;
- (void)removeObjectForKey:(id)key;

- (unsigned long long)size;
- (void)setSize:(unsigned long long)size;

- (unsigned long long)transferred;
- (float)speed;
- (void)setSpeed:(float)speed;
- (void)forceAnimationUpdate;
- (void)setProgress:(NSInteger)progress;
- (NSInteger)progress;
- (NSTimeInterval)elapsedTransferTime;

- (NSError *)error;
- (BOOL)problemsTransferringCountingErrors:(NSInteger *)outErrors successes:(NSInteger *)outSuccesses;
- (BOOL)hasError;
- (void)setError:(NSError *)error;

@end
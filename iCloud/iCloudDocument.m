//
//  iCloudDocument.m
//  iCloud Document Sync
//
//  Created by iRare Media. Last updated January 2014.
//  Available on GitHub. Licensed under MIT with Attribution.
//

#import "iCloudDocument.h"

#define OBJECT_KEY @"data"

@interface iCloudDocument ()

@property (strong) NSMutableDictionary *complexContentsStorage;
@property (strong) NSFileWrapper *fileWrapper;

@end

NSFileVersion *laterVersion (NSFileVersion *first, NSFileVersion *second) {
    NSDate *firstDate = first.modificationDate;
    NSDate *secondDate = second.modificationDate;
    return ([firstDate compare:secondDate] != NSOrderedDescending) ? second : first;
}

@implementation iCloudDocument
@synthesize delegate;
@synthesize contents = _contents;
@synthesize complexContentsStorage = _complexContentsStorage;
@synthesize fileWrapper = _fileWrapper;
@synthesize complexity = _complexity;
@dynamic complexContents;

//----------------------------------------------------------------------------------------------------------------//
//------------  Document Life Cycle ------------------------------------------------------------------------------//
//----------------------------------------------------------------------------------------------------------------//
#pragma mark - Document Life Cycle

- (id)init {
    self = [super init];
    if (self) {
        _contents = nil;
        _complexContentsStorage = nil;
        _complexity = Undefined;
    }
    return self;
}
- (id)initWithFileURL:(NSURL *)url {
	self = [super initWithFileURL:url];
	if (self) {
        _contents = nil;
        _complexContentsStorage = nil;
        _complexity = Undefined;
	}
	return self;
}

- (NSString *)localizedName {
	return [self.fileURL lastPathComponent];
}

- (NSString *)stateDescription {
    if (!self.documentState) return @"Document state is normal";
    
    NSMutableString *string = [NSMutableString string];
    if ((self.documentState & UIDocumentStateNormal) != 0) [string appendString:@"Document state is normal"];
    if ((self.documentState & UIDocumentStateClosed) != 0) [string appendString:@"Document is closed"];
    if ((self.documentState & UIDocumentStateInConflict) != 0) [string appendString:@"Document is in conflict"];
    if ((self.documentState & UIDocumentStateSavingError) != 0) [string appendString:@"Document is experiencing saving error"];
    if ((self.documentState & UIDocumentStateEditingDisabled) != 0) [string appendString:@"Document editing is disbled"];
    
    return string;
}

//----------------------------------------------------------------------------------------------------------------//
//------------  Loading and Saving -------------------------------------------------------------------------------//
//----------------------------------------------------------------------------------------------------------------//
#pragma mark - Loading and Saving

- (id)contentsForType:(NSString *)typeName error:(NSError **)outError {
    if (_complexity == Complex) {
        NSMutableDictionary* wrappers = [NSMutableDictionary dictionary];
        for (id key in [_complexContentsStorage allKeys]) {
            [self writeSubFile:[_complexContentsStorage objectForKey:key] toWrappers:wrappers preferredFilename:key];
        }
        return [[NSFileWrapper alloc] initDirectoryWithFileWrappers:wrappers];
    }
    else {
        if (!self.contents) {
            self.contents = [[NSData alloc] init];
        }
        
        NSData *data = self.contents;
        return data;
    }
}

- (BOOL)loadFromContents:(id)fileContents ofType:(NSString *)typeName error:(NSError **)outError {
    if ([fileContents isKindOfClass:[NSFileWrapper class]]) {
        self.fileWrapper = (NSFileWrapper*)fileContents;
        _complexity = Complex;
        // Lazy load the sub-files
        return YES;
    }
    else if ([fileContents isKindOfClass:[NSData class]]) {
        _complexity = Simple;
        if ([fileContents length] > 0) {
            self.contents = [[NSData alloc] initWithData:fileContents];
        } else {
            self.contents = [[NSData alloc] init];
        }
        return YES;
    }
    return NO;
}

- (void)writeSubFile:(id<NSCoding>)object toWrappers:(NSMutableDictionary*)wrappers preferredFilename:(NSString*)filename {
    @autoreleasepool {
        NSMutableData* tmpData = [NSMutableData data];
        NSKeyedArchiver* archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:tmpData];
        [archiver encodeObject:object forKey:OBJECT_KEY];
        [archiver finishEncoding];
        [wrappers setObject:[[NSFileWrapper alloc] initRegularFileWithContents:tmpData] forKey:filename];
    }
}

// Read subfile
- (id)loadSubFile:(NSString*)filename {
    NSFileWrapper* subFileWrapper = [self.fileWrapper.fileWrappers objectForKey:filename];
    if (subFileWrapper == nil) {
        NSLog(@"Unexpected error: Couldn't find sub-file %@ in file wrapper!", filename);
        return nil;
    }
    return [[[NSKeyedUnarchiver alloc] initForReadingWithData:[subFileWrapper regularFileContents]] decodeObjectForKey:OBJECT_KEY];
}

- (NSData *)contents:(NSData *)newData {
    if (_complexity == Complex) {
        return nil;
    }
    return _contents;
}

- (void)setContents:(NSData *)newData {
    if (_complexity == Complex) {
        return;
    }
    _complexity = Simple;
    NSData *oldData = _contents;
    _contents = [newData copy];
        
    // Register the undo operation
    [self.undoManager setActionName:@"Data Change"];
    [self.undoManager registerUndoWithTarget:self selector:@selector(setContents:) object:oldData];
}

/** The complex data to read from a UIDocument */
- (id<NSCoding>)getComplexContentsForKey:(NSString*)key {
    if (_complexity == Simple) {
        return nil;
    }
    id<NSCoding> object = [_complexContentsStorage objectForKey:key];
    if (object == nil) {
        // Lazy load file
        object = [self loadSubFile:key];
        [_complexContentsStorage setObject:object forKey:key];
    }
    return object;
}

- (void)setComplexContents:(id<NSCoding>)object forKey:(NSString*)key {
    if (_complexity == Simple) {
        return;
    }
    _complexity = Complex;
    id<NSCoding> oldData = [_complexContentsStorage objectForKey:key];
    [_complexContentsStorage setObject:object forKey:key];

    // Register the undo operation
    [self.undoManager setActionName:@"Data Change"];
    [[self.undoManager prepareWithInvocationTarget:self] setComplexContents:oldData forKey:key];
}

- (NSDictionary *)complexContents {
    if (_complexity == Simple) {
        return nil;
    }
    return _complexContentsStorage;
}

//----------------------------------------------------------------------------------------------------------------//
//------------  Error Handling ----------------------------------------------------------------------------------//
//----------------------------------------------------------------------------------------------------------------//
#pragma mark - Loading and Saving

- (void)handleError:(NSError *)error userInteractionPermitted:(BOOL)userInteractionPermitted {
    [super handleError:error userInteractionPermitted:userInteractionPermitted];
	NSLog(@"[iCloudDocument] %@", error);
    
    if ([delegate respondsToSelector:@selector(iCloudDocumentErrorOccured:)]) [delegate iCloudDocumentErrorOccured:error];
}

@end


//
//  PhotoExporter.m
//  ReSourcer
//
//  导出 PHAsset 原始资源：优先 HEIC/原片 UTType，实况照片附带 PairedVideo。
//  禁止走 UIImage / 兼容 JPEG 转码路径。
//

#import "PhotoExporter.h"
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation PhotoExportResult
@end

@implementation PhotoExporter

+ (void)exportAssetWithIdentifier:(NSString *)identifier
                       completion:(void (^)(PhotoExportResult *_Nullable, NSError *_Nullable))completion {
    [self exportUploadResourcesWithIdentifier:identifier completion:^(NSArray<PhotoExportResult *> *results, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        completion(results.firstObject, nil);
    }];
}

+ (void)exportUploadResourcesWithIdentifier:(NSString *)identifier
                                 completion:(void (^)(NSArray<PhotoExportResult *> *_Nullable, NSError *_Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        PHFetchResult<PHAsset *> *fetchResult =
            [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil];

        if (fetchResult.count == 0) {
            NSError *error = [NSError errorWithDomain:@"PhotoExporter" code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"无法找到照片"}];
            completion(nil, error);
            return;
        }

        PHAsset *asset = fetchResult.firstObject;
        NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];

        PHAssetResource *photoResource = [self pickOriginalStillResource:resources];
        PHAssetResource *pairedVideo = nil;

        BOOL isLive = (asset.mediaSubtypes & PHAssetMediaSubtypePhotoLive) != 0;
        if (isLive) {
            for (PHAssetResource *r in resources) {
                if (r.type == PHAssetResourceTypePairedVideo) {
                    pairedVideo = r;
                    break;
                }
            }
        }

        // 视频 asset：取原始视频资源
        if (!photoResource && asset.mediaType == PHAssetMediaTypeVideo) {
            photoResource = [self pickOriginalVideoResource:resources];
        }

        if (!photoResource) {
            NSError *error = [NSError errorWithDomain:@"PhotoExporter" code:-2
                                            userInfo:@{NSLocalizedDescriptionKey: @"无法找到原始资源文件"}];
            completion(nil, error);
            return;
        }

        NSMutableArray<PHAssetResource *> *toExport = [NSMutableArray arrayWithObject:photoResource];
        if (pairedVideo) {
            [toExport addObject:pairedVideo];
        }

        [self writeResources:toExport completion:completion];
    });
}

/// 静帧：优先 UTI 为 HEIC/HEIF 的 Photo 资源，避免 FullSize/调整后 JPEG
+ (PHAssetResource *_Nullable)pickOriginalStillResource:(NSArray<PHAssetResource *> *)resources {
    PHAssetResource *heicPhoto = nil;
    PHAssetResource *anyPhoto = nil;
    PHAssetResource *fullSize = nil;

    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypePhoto) {
            if ([self resourceLooksHEIF:r]) {
                heicPhoto = r;
                break;
            }
            if (!anyPhoto) {
                anyPhoto = r;
            }
        } else if (r.type == PHAssetResourceTypeFullSizePhoto && !fullSize) {
            fullSize = r;
        }
    }

    if (heicPhoto) { return heicPhoto; }
    if (anyPhoto) { return anyPhoto; }

    // FullSize 可能是编辑渲染图；仅当没有 Photo 时回退
    if (fullSize && [self resourceLooksHEIF:fullSize]) {
        return fullSize;
    }
    return fullSize ?: resources.firstObject;
}

+ (PHAssetResource *_Nullable)pickOriginalVideoResource:(NSArray<PHAssetResource *> *)resources {
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypeVideo) {
            return r;
        }
    }
    for (PHAssetResource *r in resources) {
        if (r.type == PHAssetResourceTypeFullSizeVideo) {
            return r;
        }
    }
    return nil;
}

+ (BOOL)resourceLooksHEIF:(PHAssetResource *)resource {
    NSString *uti = resource.uniformTypeIdentifier.lowercaseString ?: @"";
    NSString *name = resource.originalFilename.lowercaseString ?: @"";
    if ([uti containsString:@"heic"] || [uti containsString:@"heif"]) {
        return YES;
    }
    if ([name hasSuffix:@".heic"] || [name hasSuffix:@".heif"]) {
        return YES;
    }
    return NO;
}

+ (void)writeResources:(NSArray<PHAssetResource *> *)resources
            completion:(void (^)(NSArray<PhotoExportResult *> *_Nullable, NSError *_Nullable))completion {
    if (resources.count == 0) {
        completion(@[], nil);
        return;
    }

    NSMutableArray<PhotoExportResult *> *collected = [NSMutableArray array];
    dispatch_group_t group = dispatch_group_create();
    __block NSError *firstError = nil;
    NSObject *lock = [[NSObject alloc] init];

    for (PHAssetResource *resource in resources) {
        dispatch_group_enter(group);

        NSString *fileName = resource.originalFilename.length > 0
            ? resource.originalFilename
            : [NSString stringWithFormat:@"IMG_%@.bin", NSUUID.UUID.UUIDString];
        NSURL *tempDir = NSFileManager.defaultManager.temporaryDirectory;
        NSString *tempName = [NSString stringWithFormat:@"%@_%@", NSUUID.UUID.UUIDString, fileName];
        NSURL *tempURL = [tempDir URLByAppendingPathComponent:tempName];

        PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
        options.networkAccessAllowed = YES;

        [[PHAssetResourceManager defaultManager] writeDataForAssetResource:resource
                                                                    toFile:tempURL
                                                                   options:options
                                                         completionHandler:^(NSError *_Nullable writeError) {
            if (writeError) {
                @synchronized (lock) {
                    if (!firstError) { firstError = writeError; }
                }
                dispatch_group_leave(group);
                return;
            }

            NSData *data = [NSData dataWithContentsOfURL:tempURL];
            [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];

            if (!data) {
                @synchronized (lock) {
                    if (!firstError) {
                        firstError = [NSError errorWithDomain:@"PhotoExporter" code:-3
                                                    userInfo:@{NSLocalizedDescriptionKey: @"无法读取文件数据"}];
                    }
                }
                dispatch_group_leave(group);
                return;
            }

            PhotoExportResult *result = [[PhotoExportResult alloc] init];
            result.fileName = fileName;
            result.data = data;
            result.mimeType = [self mimeTypeForFileName:fileName uti:resource.uniformTypeIdentifier];

            @synchronized (lock) {
                [collected addObject:result];
            }
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_notify(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        if (firstError) {
            completion(nil, firstError);
            return;
        }
        // 保持传入顺序：静帧 → 配对视频
        NSMutableArray<PhotoExportResult *> *ordered = [NSMutableArray array];
        for (PHAssetResource *resource in resources) {
            NSString *want = resource.originalFilename;
            for (PhotoExportResult *r in collected) {
                if ([r.fileName isEqualToString:want] && ![ordered containsObject:r]) {
                    [ordered addObject:r];
                    break;
                }
            }
        }
        if (ordered.count == 0) {
            ordered = collected;
        }
        completion(ordered, nil);
    });
}

+ (NSString *)mimeTypeForFileName:(NSString *)fileName uti:(NSString *_Nullable)uti {
    NSString *ext = fileName.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
        return @"image/jpeg";
    }
    if ([ext isEqualToString:@"png"]) { return @"image/png"; }
    if ([ext isEqualToString:@"gif"]) { return @"image/gif"; }
    if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) {
        return @"image/heic";
    }
    if ([ext isEqualToString:@"webp"]) { return @"image/webp"; }
    if ([ext isEqualToString:@"mov"]) { return @"video/quicktime"; }
    if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"m4v"]) {
        return @"video/mp4";
    }
    if (uti.length > 0) {
        if (@available(iOS 14.0, *)) {
            UTType *type = [UTType typeWithIdentifier:uti];
            if (type.preferredMIMEType.length > 0) {
                return type.preferredMIMEType;
            }
        }
    }
    return @"application/octet-stream";
}

+ (void)deleteAssetsWithIdentifiers:(NSArray<NSString *> *)identifiers
                         completion:(void (^)(BOOL, NSError *_Nullable))completion {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHFetchOptions *options = [PHFetchOptions new];
        PHFetchResult<PHAsset *> *result =
            [PHAsset fetchAssetsWithLocalIdentifiers:identifiers options:options];
        [PHAssetChangeRequest deleteAssets:result];
    } completionHandler:^(BOOL success, NSError *_Nullable error) {
        completion(success, error);
    }];
}

+ (void)saveFileToPhotos:(NSData *)data
                fileName:(NSString *)fileName
              completion:(void (^)(BOOL, NSError *_Nullable))completion {
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@_%@", NSUUID.UUID.UUIDString, fileName]];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

    NSError *writeError = nil;
    [data writeToURL:tempURL options:NSDataWritingAtomic error:&writeError];
    if (writeError) {
        completion(NO, writeError);
        return;
    }

    NSString *ext = fileName.pathExtension.lowercaseString;
    NSArray *videoExts = @[@"mp4", @"mov", @"avi", @"mkv", @"m4v", @"webm", @"flv", @"wmv"];
    BOOL isVideo = [videoExts containsObject:ext];

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceType resourceType = isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
        [request addResourceWithType:resourceType fileURL:tempURL options:nil];
    } completionHandler:^(BOOL success, NSError *_Nullable error) {
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
        completion(success, error);
    }];
}

@end

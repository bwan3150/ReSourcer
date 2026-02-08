//
//  PhotoExporter.m
//  ReSourcer
//
//  Objective-C 帮助类：导出 PHAsset 到临时文件
//  参考 Flutter photo_manager (PMManager.m) 的实现方式
//

#import "PhotoExporter.h"
#import <Photos/Photos.h>

// MARK: - PhotoExportResult

@implementation PhotoExportResult
@end

// MARK: - PhotoExporter

@implementation PhotoExporter

+ (void)exportAssetWithIdentifier:(NSString *)identifier
                       completion:(void (^)(PhotoExportResult *_Nullable, NSError *_Nullable))completion {

    // 在后台线程执行所有操作（与 Flutter photo_manager PMManager.m 一致）
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{

        // 1. 获取 PHAsset
        PHFetchResult<PHAsset *> *fetchResult =
            [PHAsset fetchAssetsWithLocalIdentifiers:@[identifier] options:nil];

        if (fetchResult.count == 0) {
            NSError *error = [NSError errorWithDomain:@"PhotoExporter" code:-1
                                            userInfo:@{NSLocalizedDescriptionKey: @"无法找到照片"}];
            completion(nil, error);
            return;
        }

        PHAsset *asset = fetchResult.firstObject;

        // 2. 获取 PHAssetResource
        NSArray<PHAssetResource *> *resources = [PHAssetResource assetResourcesForAsset:asset];

        PHAssetResource *resource = nil;

        // 优先找原始资源
        for (PHAssetResource *r in resources) {
            if (r.type == PHAssetResourceTypePhoto || r.type == PHAssetResourceTypeVideo) {
                resource = r;
                break;
            }
        }

        // 其次找全尺寸资源
        if (!resource) {
            for (PHAssetResource *r in resources) {
                if (r.type == PHAssetResourceTypeFullSizePhoto ||
                    r.type == PHAssetResourceTypeFullSizeVideo) {
                    resource = r;
                    break;
                }
            }
        }

        // 最后用第一个可用的
        if (!resource && resources.count > 0) {
            resource = resources.firstObject;
        }

        if (!resource) {
            NSError *error = [NSError errorWithDomain:@"PhotoExporter" code:-2
                                            userInfo:@{NSLocalizedDescriptionKey: @"无法找到资源文件"}];
            completion(nil, error);
            return;
        }

        // 3. 写入临时文件
        NSString *fileName = resource.originalFilename;
        NSURL *tempDir = [NSFileManager.defaultManager temporaryDirectory];
        NSString *tempName = [NSString stringWithFormat:@"%@_%@",
                              [[NSUUID UUID] UUIDString], fileName];
        NSURL *tempURL = [tempDir URLByAppendingPathComponent:tempName];

        PHAssetResourceRequestOptions *options = [[PHAssetResourceRequestOptions alloc] init];
        options.networkAccessAllowed = YES;

        [[PHAssetResourceManager defaultManager] writeDataForAssetResource:resource
                                                                   toFile:tempURL
                                                                  options:options
                                                        completionHandler:^(NSError *_Nullable writeError) {
            if (writeError) {
                completion(nil, writeError);
                return;
            }

            // 4. 读取文件数据
            NSData *data = [NSData dataWithContentsOfURL:tempURL];

            // 5. 清理临时文件
            [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];

            if (!data) {
                NSError *error = [NSError errorWithDomain:@"PhotoExporter" code:-3
                                                userInfo:@{NSLocalizedDescriptionKey: @"无法读取文件数据"}];
                completion(nil, error);
                return;
            }

            // 6. 推断 MIME 类型
            NSString *ext = fileName.pathExtension.lowercaseString;
            NSString *mimeType = @"application/octet-stream";

            if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
                mimeType = @"image/jpeg";
            } else if ([ext isEqualToString:@"png"]) {
                mimeType = @"image/png";
            } else if ([ext isEqualToString:@"gif"]) {
                mimeType = @"image/gif";
            } else if ([ext isEqualToString:@"heic"] || [ext isEqualToString:@"heif"]) {
                mimeType = @"image/heic";
            } else if ([ext isEqualToString:@"webp"]) {
                mimeType = @"image/webp";
            } else if ([ext isEqualToString:@"mov"]) {
                mimeType = @"video/quicktime";
            } else if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"m4v"]) {
                mimeType = @"video/mp4";
            }

            // 7. 构建结果
            PhotoExportResult *result = [[PhotoExportResult alloc] init];
            result.fileName = fileName;
            result.data = data;
            result.mimeType = mimeType;

            completion(result, nil);
        }];
    });
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

    // 写入临时文件
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@_%@", [[NSUUID UUID] UUIDString], fileName]];
    NSURL *tempURL = [NSURL fileURLWithPath:tempPath];

    NSError *writeError = nil;
    [data writeToURL:tempURL options:NSDataWritingAtomic error:&writeError];
    if (writeError) {
        completion(NO, writeError);
        return;
    }

    // 根据扩展名判断资源类型
    NSString *ext = fileName.pathExtension.lowercaseString;
    NSArray *videoExts = @[@"mp4", @"mov", @"avi", @"mkv", @"m4v", @"webm", @"flv", @"wmv"];
    BOOL isVideo = [videoExts containsObject:ext];

    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        PHAssetResourceType resourceType = isVideo ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto;
        [request addResourceWithType:resourceType fileURL:tempURL options:nil];
    } completionHandler:^(BOOL success, NSError *_Nullable error) {
        // 清理临时文件
        [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
        completion(success, error);
    }];
}

@end

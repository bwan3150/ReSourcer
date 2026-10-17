//
//  PhotoExporter.h
//  ReSourcer
//
//  Objective-C 帮助类：导出 PHAsset 原始字节（含实况配对视频）
//  参考 Flutter photo_manager (PMManager.m) 的方式，
//  避免 Swift 6 严格并发模式下 PHAssetResourceManager 的线程断言崩溃
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Asset 导出结果（单文件）
@interface PhotoExportResult : NSObject

@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, copy) NSString *mimeType;

@end

/// PHAsset 导出器（使用 PHAssetResourceManager，取原始资源，不经系统「兼容格式」转码）
@interface PhotoExporter : NSObject

/// 通过 asset identifier 导出主资源（兼容旧调用；实况照片仅返回静帧）
/// @param identifier PHAsset 的 localIdentifier
/// @param completion 完成回调（在后台线程调用）
+ (void)exportAssetWithIdentifier:(NSString *)identifier
                       completion:(void (^)(PhotoExportResult *_Nullable result,
                                            NSError *_Nullable error))completion;

/// 导出上传所需的全部原始资源：静帧（优先 HEIC）+ 实况配对 MOV（若有）
/// @param identifier PHAsset 的 localIdentifier
/// @param completion 完成后台回调；数组顺序：静帧在前，配对视频在后
+ (void)exportUploadResourcesWithIdentifier:(NSString *)identifier
                                 completion:(void (^)(NSArray<PhotoExportResult *> *_Nullable results,
                                                      NSError *_Nullable error))completion;

/// 删除指定的本地照片（会弹出系统确认框）
+ (void)deleteAssetsWithIdentifiers:(NSArray<NSString *> *)identifiers
                         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/// 将文件数据保存到系统相册
+ (void)saveFileToPhotos:(NSData *)data
                fileName:(NSString *)fileName
              completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

//
//  PhotoExporter.h
//  ReSourcer
//
//  Objective-C 帮助类：导出 PHAsset 到临时文件
//  参考 Flutter photo_manager (PMManager.m) 的方式，
//  避免 Swift 6 严格并发模式下 PHAssetResourceManager 的线程断言崩溃
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Asset 导出结果
@interface PhotoExportResult : NSObject

@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, strong) NSData *data;
@property (nonatomic, copy) NSString *mimeType;

@end

/// PHAsset 导出器（使用 PHAssetResourceManager，与 Flutter photo_manager 一致）
@interface PhotoExporter : NSObject

/// 通过 asset identifier 导出文件数据
/// @param identifier PHAsset 的 localIdentifier
/// @param completion 完成回调（在后台线程调用）
+ (void)exportAssetWithIdentifier:(NSString *)identifier
                       completion:(void (^)(PhotoExportResult *_Nullable result,
                                            NSError *_Nullable error))completion;

/// 删除指定的本地照片（会弹出系统确认框）
/// @param identifiers PHAsset 的 localIdentifier 数组
/// @param completion 完成回调
+ (void)deleteAssetsWithIdentifiers:(NSArray<NSString *> *)identifiers
                         completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

/// 将文件数据保存到系统相册
/// @param data 文件数据
/// @param fileName 文件名（用于判断资源类型和临时文件命名）
/// @param completion 完成回调
+ (void)saveFileToPhotos:(NSData *)data
                fileName:(NSString *)fileName
              completion:(void (^)(BOOL success, NSError *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

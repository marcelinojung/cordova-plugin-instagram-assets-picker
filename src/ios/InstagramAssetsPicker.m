//
//  InstagramAssetsPicker.m
//
//  Created by Ross Martin on 2/25/16.
//
//

#import "InstagramAssetsPicker.h"
#import "IGAssetsPicker.h"
#import "IGCropView.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
@import Photos;

@interface InstagramAssetsPicker ()<IGAssetsPickerDelegate>

@end

@implementation InstagramAssetsPicker

@synthesize callbackId;

/**
 * getMedia
 *
 * Show a UI media picker similar to Instagram
 *
 * ARGUMENTS
 * =========
 * type               - (NSString) type of media to choose (video, photo, or all)
 * cropAfterSelect    - (BOOL) determine whether to perfrom crop right away
 *
 * RESPONSE
 * ========
 *
 * filePath           - (NSString) path to the chosen media file
 * rect               - (CGRect) rect object with data needed for cropping at a later time
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) getMedia:(CDVInvokedUrlCommand*)command
{
    NSLog(@"getMedia");
    self.callbackId = command.callbackId;

    NSDictionary* options = [command.arguments objectAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSString *mediaType = ([options objectForKey:@"type"]) ? [options objectForKey:@"type"] : @"all";
    BOOL cropAfterSelect = ([options objectForKey:@"cropAfterSelect"]) ? [[options objectForKey:@"cropAfterSelect"] boolValue] : NO;

    PHFetchOptions *fetchOptions = [PHFetchOptions new];
    fetchOptions.sortDescriptors = @[
       [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]
    ];

    if ([mediaType isEqualToString:@"photo"]) {
        fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %i", PHAssetMediaTypeImage];
    } else if ([mediaType isEqualToString:@"video"]) {
        fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %i", PHAssetMediaTypeVideo];
    } else {
        fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %i || mediaType == %i", PHAssetMediaTypeImage, PHAssetMediaTypeVideo];
    }

    IGAssetsPickerViewController *picker = [[IGAssetsPickerViewController alloc] init];
    picker.delegate = self;
    picker.fetchOptions = fetchOptions;
    picker.cropAfterSelect = cropAfterSelect;
    [self.viewController presentViewController:picker animated:YES completion:NULL];

}

/**
 * cropAsset
 *
 * Crop a media asset (photo or video)
 *
 * ARGUMENTS
 * =========
 * filePath           - (NSString) path to the ALAsset
 * rect               - (CGRect) rect object with data needed for cropping
 *
 * RESPONSE
 * ========
 *
 * filePath           - (NSString) path to the chosen media file
 *
 * @param CDVInvokedUrlCommand command
 * @return void
 */
- (void) cropAsset:(CDVInvokedUrlCommand*)command
{
    NSLog(@"cropAsset");

    NSDictionary* options = [command.arguments objectAtIndex:0];

    if ([options isKindOfClass:[NSNull class]]) {
        options = [NSDictionary dictionary];
    }

    NSString *phAssetId = [options objectForKey:@"phAssetId"];
    NSDictionary *rectData = [options objectForKey:@"rect"];
    CGRect rect;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)(rectData), &rect);

    NSString *outputName = [InstagramAssetsPicker getUUID];
    __block NSString *outputPath;
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    [self.commandDelegate runInBackground:^{
        PHFetchResult *fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:[NSArray arrayWithObjects:phAssetId, nil] options:nil];
        PHAsset *phAsset = [fetchResult objectAtIndex:0];
        if (!phAsset) {
            NSLog(@"no asset found with phAssetId");
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"No asset was found with the provided phAssetId"] callbackId:command.callbackId];
            return;
        }

        [IGCropView cropPhAsset:phAsset withRegion:rect onComplete:^(id croppedAsset) {
            if ([croppedAsset isKindOfClass:[UIImage class]]) {
                NSLog(@"cropped a photo");
                UIImage *photo = (UIImage *)croppedAsset;
                outputPath = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", outputName, @"jpg"]];
                [UIImageJPEGRepresentation(photo, 1.0) writeToFile:outputPath atomically:YES];
            } else if ([croppedAsset isKindOfClass:[NSURL class]]) {
                NSLog(@"cropped a video");
                outputPath = [(NSURL *)croppedAsset absoluteString];
            }

            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:outputPath] callbackId:command.callbackId];
        }];
    }];
}

#pragma mark - IGAssetsPickerDelegate

- (void)IGAssetsPickerFinishCroppingToAsset:(id)asset
{
    NSString *outputName = [InstagramAssetsPicker getUUID];
    NSString *outputPath;
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

    if ([asset isKindOfClass:[UIImage class]]) { // photo
        NSLog(@"chose a photo");
        UIImage *photo = (UIImage *)asset;
        outputPath = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", outputName, @"jpg"]];
        [UIImageJPEGRepresentation(photo, 1.0) writeToFile:outputPath atomically:YES];
    } else if ([asset isKindOfClass:[NSURL class]]) { // video
        NSLog(@"chose a video");
        outputPath = [(NSURL*)asset absoluteString];
    }

    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    [dict setObject:outputPath forKey:@"filePath"];

    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict] callbackId:self.callbackId];
}

- (void)IGAssetsPickerGetCropRegion:(CGRect)rect withPhAsset:(PHAsset *)asset
{
    NSLog(@"IGAssetsPickerGetCropRegion");

    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary: @{
       @"rect" : CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect)),
       @"phAssetId" : asset.localIdentifier
    }];

    if(asset.mediaType == PHAssetMediaTypeImage) // photo
    {
        PHImageManager *manager = [PHImageManager defaultManager];

        PHImageRequestOptions *requestOptions = [[PHImageRequestOptions alloc] init];
        requestOptions.synchronous = true;
        requestOptions.networkAccessAllowed = true;
        requestOptions.resizeMode = PHImageRequestOptionsResizeModeExact;
        requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

        [manager requestImageForAsset:asset
                 targetSize:PHImageManagerMaximumSize
                 contentMode:PHImageContentModeDefault
                 options:requestOptions
                 resultHandler:^void(UIImage *image, NSDictionary *info) {

                    NSString *outputName = [InstagramAssetsPicker getUUID];
                    NSString *outputPath;
                    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];

                    outputPath = [cacheDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", outputName, @"jpg"]];
                    dict[@"filePath"] = outputPath;
                    [UIImageJPEGRepresentation(image, 1.0) writeToFile:outputPath atomically:YES];

                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict] callbackId:self.callbackId];
        }];



    }
    else if(asset.mediaType == PHAssetMediaTypeVideo) // video
    {
        PHImageManager *manager = [PHImageManager defaultManager];
        PHVideoRequestOptions *requestOptions = [[PHVideoRequestOptions alloc] init];
        requestOptions.networkAccessAllowed = true;

        [manager requestAVAssetForVideo:asset options:requestOptions resultHandler:^(AVAsset *avAsset, AVAudioMix *audioMix, NSDictionary *info) {
            AVURLAsset *urlAsset = (AVURLAsset *)avAsset;
            dict[@"filePath"] = urlAsset.URL.absoluteString;
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dict] callbackId:self.callbackId];
        }];
    }
}

+ (NSString *)getUUID
{
    CFUUIDRef newUniqueId = CFUUIDCreate(kCFAllocatorDefault);
    NSString * uuidString = (__bridge_transfer NSString*)CFUUIDCreateString(kCFAllocatorDefault, newUniqueId);
    CFRelease(newUniqueId);

    return uuidString;
}

@end

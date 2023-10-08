//
//  RNBluetoothTscPrinter.m
//  RNBluetoothEscposPrinter
//
 

#import <Foundation/Foundation.h>
#import "ImageUtils.h"
#import "RNBluetoothTscPrinter.h"
#import "RNTscCommand.h"
#import "RNBluetoothManager.h"

@interface ESCPosPrinterConnection : NSObject <NSStreamDelegate>

@property (nonatomic, strong) NSInputStream *inputStream;
@property (nonatomic, strong) NSOutputStream *outputStream;
@property (nonatomic) NSString *check;
- (void)connectToPrinterAtIPAddress:(NSString *)ipAddress port:(NSInteger)port;
- (void)disconnect;
- (void)sendArrayCommands:(NSArray<NSDictionary *> *)arrayData;

@end

@implementation ESCPosPrinterConnection

- (void)sendArrayCommands:(NSArray<NSDictionary *> *)arrayData {
    self.check = @"sending";
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            for (NSDictionary *data in arrayData) {
                NSInteger sleep = [[data valueForKey:@"sleep"] integerValue];
                NSString *base64Command = [data valueForKey:@"rawData"];

                NSData *commandData = [[NSData alloc] initWithBase64EncodedString:base64Command options:NSDataBase64DecodingIgnoreUnknownCharacters];

//                 NSInteger bytesWritten = [self.outputStream write:commandData.bytes maxLength:commandData.length];
//                 if (bytesWritten == -1) {
//                    self.check = @"error-send";
//                    return;
//                 }

                NSInteger totalBytesWritten = 0;
                NSInteger bufferSize = 64 * 1024; // Set the desired buffer size

                while (totalBytesWritten < commandData.length) {
                    NSInteger bytesRemaining = commandData.length - totalBytesWritten;
                    NSInteger bytesToWrite = MIN(bufferSize, bytesRemaining);
                    NSData *chunkData = [commandData subdataWithRange:NSMakeRange(totalBytesWritten, bytesToWrite)];
                    NSInteger bytesWritten = [self.outputStream write:chunkData.bytes maxLength:bytesToWrite];

                    if (bytesWritten == -1) {
                        // Handle error
                        self.check = @"error-send";
                        return;
                    }

                    totalBytesWritten += bytesWritten;
                }

                // You can check if all data has been sent here
                if (totalBytesWritten == commandData.length) {
                    // All data has been sent successfully
                } else {
                    // Handle partial send or error
                    self.check = @"error-send";
                    return;
                }

                [NSThread sleepForTimeInterval:(float)sleep/1000];
            }
            self.check = @"success";
        }
    });

    while ([self.check isEqualToString:@"sending"]) {
        // Sleep for a short time to avoid busy-waiting
        [NSThread sleepForTimeInterval:.01];
    }
}
- (void)connectToPrinterAtIPAddress:(NSString *)ipAddress port:(NSInteger)port {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            CFReadStreamRef readStream;
            CFWriteStreamRef writeStream;
            CFStreamCreatePairWithSocketToHost(NULL, (__bridge CFStringRef)ipAddress, (UInt32)port, &readStream, &writeStream);


            self.inputStream = (__bridge NSInputStream *)readStream;
            self.outputStream = (__bridge NSOutputStream *)writeStream;

            self.inputStream.delegate = self;
            self.outputStream.delegate = self;

            [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
            [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

            [self.inputStream open];
            [self.outputStream open];
        }
    });
    NSInteger count = 0;
    while(count < 50){
        [NSThread sleepForTimeInterval:.05];//Chờ để kết nối duoc thiet lap
        if (self.inputStream.streamStatus == NSStreamStatusOpen && self.outputStream.streamStatus == NSStreamStatusOpen) {
            self.check = @"success";
            return;
        }
        count += 1;
    }
    self.check = @"error-connection";

    [self.inputStream close];
    [self.outputStream close];

    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    [self.inputStream setDelegate:nil];
    [self.outputStream setDelegate:nil];

    self.inputStream = nil;
    self.outputStream = nil;
}

- (void)disconnect {
    [self.inputStream close];
    [self.outputStream close];

    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

    [self.inputStream setDelegate:nil];
    [self.outputStream setDelegate:nil];

    self.inputStream = nil;
    self.outputStream = nil;
}


@end

@implementation RNBluetoothTscPrinter

NSData *toPrint;
RCTPromiseRejectBlock _pendingReject;
RCTPromiseResolveBlock _pendingResolve;
NSInteger now;

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}
+ (BOOL)requiresMainQueueSetup
{
    return YES;
}

RCT_EXPORT_MODULE(BluetoothTscPrinter);
//printLabel(final ReadableMap options, final Promise promise)
RCT_EXPORT_METHOD(printLabel:(NSDictionary *) options withResolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    NSInteger width = [[options valueForKey:@"width"] integerValue];
    NSInteger height = [[options valueForKey:@"height"] integerValue];
    NSInteger gap = [[options valueForKey:@"gap"] integerValue];
    NSInteger home = [[options valueForKey:@"home"] integerValue];
    NSString *tear = [options valueForKey:@"tear"];
    if(!tear || ![@"ON" isEqualToString:tear]) tear = @"OFF";
    NSArray *texts = [options objectForKey:@"text"];
    NSArray *qrCodes = [options objectForKey:@"qrcode"];
    NSArray *barCodes = [options objectForKey:@"barcode"];
    NSArray *images = [options objectForKey:@"image"];
    NSArray *reverses = [options objectForKey:@"revers"];
    NSInteger direction = [[options valueForKey:@"direction"] integerValue];
    NSInteger density = [[options valueForKey:@"density"] integerValue];
    NSArray* reference = [options objectForKey:@"reference"];
    NSInteger sound = [[options valueForKey:@"sound"] integerValue];
    NSInteger speed = [[options valueForKey:@"speed"] integerValue];
    RNTscCommand *tsc = [[RNTscCommand alloc] init];
    if(speed){
        [tsc addSpeed:[tsc findSpeedValue:speed]];
    }
    if(density){
        [tsc addDensity:density];
    }
    [tsc addSize:width height:height];
    [tsc addGap:gap];
    [tsc addDirection:direction];
    if(reference && [reference count] ==2){
        NSInteger x = [[reference objectAtIndex:0] integerValue];
        NSInteger y = [[reference objectAtIndex:1] integerValue];
        NSLog(@"refernce  %ld y:%ld ",x,y);
        [tsc addReference:x y:y];
    }else{
        [tsc addReference:0 y:0];
    }
    [tsc addTear:tear];
    if(home && home == 1){
      [tsc addBackFeed:16];
      [tsc addHome];
    }
    [tsc addCls];

    //Add Texts
    for(int i=0; texts && i<[texts count];i++){
        NSDictionary * text = [texts objectAtIndex:i];
        NSString *t = [text valueForKey:@"text"];
        NSInteger x = [[text valueForKey:@"x"] integerValue];
        NSInteger y = [[text valueForKey:@"y"] integerValue];
        NSString *fontType = [text valueForKey:@"fonttype"];
        NSInteger rotation = [[text valueForKey:@"rotation"] integerValue];
        NSInteger xscal = [[text valueForKey:@"xscal"] integerValue];
        NSInteger yscal = [[text valueForKey:@"yscal"] integerValue];
        Boolean bold = [[text valueForKey:@"bold"] boolValue];

        [tsc addText:x y:y fontType:fontType rotation:rotation xscal:xscal yscal:yscal text:t];
        if(bold){
            [tsc addText:x+1 y:y fontType:fontType
                rotation:rotation xscal:xscal yscal:yscal  text:t];
            [tsc addText:x y:y+1 fontType:fontType
                rotation:rotation xscal:xscal yscal:yscal  text:t];
        }
    }

  //images
        for (int i = 0; images && i < [images count]; i++) {
            NSDictionary *img = [images objectAtIndex:i];
            NSInteger x = [[img valueForKey:@"x"] integerValue];
            NSInteger y = [[img valueForKey:@"y"] integerValue];
            NSInteger imgWidth = [[img valueForKey:@"width"] integerValue];
            NSInteger mode = [[img valueForKey:@"mode"] integerValue];
            NSString *image  = [img valueForKey:@"image"];
            NSData *imageData = [[NSData alloc] initWithBase64EncodedString:image options:0];
            UIImage *uiImage = [[UIImage alloc] initWithData:imageData];
            [tsc addBitmap:x y:y bitmapMode:mode width:imgWidth bitmap:uiImage];
        }

    //QRCode
    for (int i = 0; qrCodes && i < [qrCodes count]; i++) {
        NSDictionary *qr = [qrCodes objectAtIndex:i];
        NSInteger x = [[qr valueForKey:@"x"] integerValue];
        NSInteger y = [[qr valueForKey:@"y"] integerValue];
        NSInteger qrWidth = [[qr valueForKey:@"width"] integerValue];
        NSString *level = [qr valueForKey:@"level"];
        if(!level)level = @"M";
        NSInteger rotation = [[qr valueForKey:@"rotation"] integerValue];
        NSString *code = [qr valueForKey:@"code"];
        [tsc addQRCode:x y:y errorCorrectionLevel:level width:qrWidth rotation:rotation code:code];
    }

    //BarCode
   for (int i = 0; barCodes && i < [barCodes count]; i++) {
       NSDictionary *bar = [barCodes objectAtIndex:i];
       NSInteger x = [[bar valueForKey:@"x"] integerValue];
       NSInteger y = [[bar valueForKey:@"y"] integerValue];
       NSInteger barWide =[[bar valueForKey:@"wide"] integerValue];
       if(!barWide) barWide = 2;
       NSInteger barHeight = [[bar valueForKey:@"height"] integerValue];
       NSInteger narrow = [[bar valueForKey:@"narrow"] integerValue];
       if(!narrow) narrow = 2;
       NSInteger rotation = [[bar valueForKey:@"rotation"] integerValue];
       NSString *code = [bar valueForKey:@"code"];
       NSString *type = [bar valueForKey:@"type"];
       NSInteger readable = [[bar valueForKey:@"readable"] integerValue];
       [tsc add1DBarcode:x y:y barcodeType:type height:barHeight wide:barWide narrow:narrow readable:readable rotation:rotation content:code];
    }
    for(int i=0; reverses&& i < [reverses count]; i++){
        NSDictionary *area = [reverses objectAtIndex:i];
        NSInteger ax = [[area valueForKey:@"x"] integerValue];
        NSInteger ay = [[area valueForKey:@"y"] integerValue];
        NSInteger aWidth = [[area valueForKey:@"width"] integerValue];
        NSInteger aHeight = [[area valueForKey:@"height"] integerValue];
        [tsc addReverse:ax y:ay xwidth:aWidth yheigth:aHeight];
    }
    [tsc addPrint:1 n:1];
    if (sound) {
        [tsc addSound:2 interval:100];
    }
    _pendingReject = reject;
    _pendingResolve = resolve;
    toPrint = tsc.command;
    now = 0;
    [RNBluetoothManager writeValue:toPrint withDelegate:self];
}

RCT_EXPORT_METHOD(encodeImage:(NSString *) base64Image withResolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{

        // Kiểm tra xem base64Image có giá trị không
        if (!base64Image || [base64Image isEqualToString:@""]) {
            reject(@"INVALID_IMAGE", @"Invalid base64 image", nil);
            return;
        }

        // Chuyển đổi base64 string thành dữ liệu
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64Image options:1];

        // Kiểm tra xem việc chuyển đổi thành công không
        if (!imageData) {
            reject(@"INVALID_IMAGE", @"Invalid base64 image data", nil);
            return;
        }

        UIImage *uiImage = [[UIImage alloc] initWithData:imageData];

        // Tiến hành xử lý ảnh ở đây nếu cần
        uint8_t * graybits = [ImageUtils imageToGreyImage:uiImage];
        CGFloat srcLen = (float)uiImage.size.width*(float)uiImage.size.height;
        NSData *codecontent = [ImageUtils pixToTscCmd:graybits width:(int)srcLen];


        // Chuyển đổi ảnh đã xử lý thành base64 string
        NSString *encodedImage = [codecontent base64EncodedStringWithOptions:0];

        // Trả về kết quả qua resolve
        resolve(encodedImage);
}

RCT_EXPORT_METHOD(encodeImageV2:(NSDictionary *) options withResolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{

        
        NSString *base64Image  = [options valueForKey:@"image"];
        NSInteger threshold = [[options valueForKey:@"threshold"] integerValue];
        
        // Kiểm tra xem base64Image có giá trị không
        if (!base64Image || [base64Image isEqualToString:@""]) {
            reject(@"INVALID_IMAGE", @"Invalid base64 image", nil);
            return;
        }

        // Chuyển đổi base64 string thành dữ liệu
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64Image options:1];

        // Kiểm tra xem việc chuyển đổi thành công không
        if (!imageData) {
            reject(@"INVALID_IMAGE", @"Invalid base64 image data", nil);
            return;
        }

        UIImage *b = [[UIImage alloc] initWithData:imageData];

        //[tsc addBitmap:x y:y bitmapMode:mode width:imgWidth bitmap:uiImage];
        
        uint8_t * graybits = [ImageUtils imageToGreyImageWithThresholdTsc:b threshold:threshold];
        CGFloat srcLen = (float)b.size.width*(float)b.size.height;
        NSData *codecontent = [ImageUtils pixToTscCmd:graybits width:(int)srcLen];


        // Chuyển đổi ảnh đã xử lý thành base64 string
        NSString *encodedImage = [codecontent base64EncodedStringWithOptions:0];

        // Trả về kết quả qua resolve
        resolve(encodedImage);
}

RCT_EXPORT_METHOD(autoReleaseNetPrintRawData:(NSArray<NSDictionary *> *)base64Commands ip:(NSString *)ip withResolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
        ESCPosPrinterConnection *printerConnection = [[ESCPosPrinterConnection alloc] init];
        [printerConnection connectToPrinterAtIPAddress:ip port:9100];
        if(![printerConnection.check isEqualToString: @"success"]){
            NSLog(@"Loi ket noi");
            resolve(printerConnection.check);
            return;
         }
         // Send the feed paper command
         [printerConnection sendArrayCommands:base64Commands];
         // When done, disconnect from the printer
         [printerConnection disconnect];

         // Trả về kết quả qua resolve
         resolve(printerConnection.check);
}

RCT_EXPORT_METHOD(autoReleaseNetPrintRawDataAsync:(NSArray<NSDictionary *> *)arrayData ip:(NSString *)ip withResolve:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
          dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                ESCPosPrinterConnection *printerConnection = [[ESCPosPrinterConnection alloc] init];
                [printerConnection connectToPrinterAtIPAddress:ip port:9100];
                if(![printerConnection.check isEqualToString: @"success"]){
                    NSLog(@"Loi ket noi");
                    resolve(printerConnection.check);
                    return;
                 }
                 // Send the feed paper command
                 [printerConnection sendArrayCommands:arrayData];
                 // When done, disconnect from the printer
                 [printerConnection disconnect];

                 // Trả về kết quả qua resolve
                 resolve(printerConnection.check);
           });
}

- (void) didWriteDataToBle: (BOOL)success{
    if(success){
        if(_pendingResolve){
            _pendingResolve(nil);
        }
    }else if(_pendingReject){
        _pendingReject(@"PRINT_ERROR",@"PRINT_ERROR",nil);
    }
}

@end

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

- (void)connectToPrinterAtIPAddress:(NSString *)ipAddress port:(NSInteger)port;
- (void)sendFeedPaperCommand;
- (void)disconnect;

@end

@implementation ESCPosPrinterConnection

- (void)connectToPrinterAtIPAddress:(NSString *)ipAddress port:(NSInteger)port {
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

- (void)sendDataToPrinter:(NSData *)data {
    if (self.outputStream) {
        NSInteger bytesWritten = [self.outputStream write:data.bytes maxLength:data.length];
        if (bytesWritten == -1) {
            NSLog(@"Error writing to printer");
        }
    }
}

- (void)sendFeedPaperCommand {
    // ESC/POS command to feed paper (partial cut)
    unsigned char feedPaperCommand[] = {0x1B, 0x64, 0x02};
    NSData *data = [NSData dataWithBytes:feedPaperCommand length:sizeof(feedPaperCommand)];
    [self sendDataToPrinter:data];
    [self sendDataToPrinter:data];
    [self sendDataToPrinter:data];
    [self sendDataToPrinter:data];
    [self sendDataToPrinter:data];

    unsigned char cutPaperCommand[] = {0x1D, 0x56, 0x00};
    NSData *dataCut = [NSData dataWithBytes:cutPaperCommand length:sizeof(cutPaperCommand)];
    [self sendDataToPrinter:dataCut];
}

- (void)disconnect {
    [self.inputStream close];
    [self.outputStream close];
    self.inputStream = nil;
    self.outputStream = nil;
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    if (eventCode == NSStreamEventErrorOccurred) {
        NSLog(@"Stream error occurred");
    } else if (eventCode == NSStreamEventEndEncountered) {
        NSLog(@"Stream end encountered");
        [self disconnect];
    }
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
        
        uint8_t * graybits = [ImageUtils imageToGreyImageWithThreshold:b threshold:threshold];
        CGFloat srcLen = (float)b.size.width*(float)b.size.height;
        NSData *codecontent = [ImageUtils pixToTscCmd:graybits width:(int)srcLen];


        // Chuyển đổi ảnh đã xử lý thành base64 string
        NSString *encodedImage = [codecontent base64EncodedStringWithOptions:0];


         ESCPosPrinterConnection *printerConnection = [[ESCPosPrinterConnection alloc] init];
         [printerConnection connectToPrinterAtIPAddress:@"192.168.2.199" port:9100];

         // Send the feed paper command
         [printerConnection sendFeedPaperCommand];

         // When done, disconnect from the printer
         [printerConnection disconnect];




        // Trả về kết quả qua resolve
        resolve(encodedImage);
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

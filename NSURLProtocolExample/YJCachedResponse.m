//
//  YJCachedResponse.m
//  NSURLProtocolExample
//
//  Created by leihuan on 18/5/18.
//  Copyright © 2018年 Rocir Santiago. All rights reserved.
//

#import "YJCachedResponse.h"
#import "objc/runtime.h"
#import <CommonCrypto/CommonDigest.h>

@interface YJCachedResponse()<NSCoding>
@property (nonatomic, assign) NSTimeInterval timeInterval;
@property (nonatomic, strong) NSDate *cachedTime;
@property (nonatomic, strong) NSString *cachedFilePath;

@property (nonatomic, strong, readwrite) NSURLResponse *response;
@end


// 转化函数。对当前加载的url或者字符串进行md5加密
NSString * md5(NSString *);


@implementation YJCachedResponse

- (instancetype)initWithData:(NSData *)data response:(NSURLResponse *)response limiteTime:(NSTimeInterval)timeInterval{
    self = [super init];
    if (self) {
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        self.cachedFilePath = [docPath stringByAppendingPathComponent: md5(response.URL.absoluteString)];
        
        self.data = [data copy];
        self.url = [response.URL.absoluteString copy];
        self.cachedTime = [NSDate date];
        self.mimeType = [response.MIMEType copy];
        self.encoding = [response.textEncodingName copy];
        self.timeInterval = timeInterval;
        
        // 把本地缓存数据转化为这个自定义类落地持久化。然后这个类被用来转换成URL Loading System可以接受的NSURLResponse类(设置类型、长度、编码)，发送给client，也即: 有缓存的情况下,直接使用缓存的数据和MIME类型，然后构建一个新的response
        self.response = [[NSURLResponse alloc] initWithURL:[NSURL URLWithString:self.url] MIMEType:self.mimeType expectedContentLength:self.data.length textEncodingName:self.encoding];
    }
    return self;
}


- (CacheStatus)isCacheEffective {
    
    //检查是否过期,已失效则删除缓存
    if ( [[NSDate date]timeIntervalSinceDate:self.cachedTime] > self.timeInterval) {//超出过期时间
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.cachedFilePath]) {
            NSLog(@"缓存不存在？！！！, %@", md5(self.url));
            return OutOfDate;
        }
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.cachedFilePath error:&error];
        if (!error) {
            NSLog(@"缓存过期，已删除, %@", md5(self.url));
        } else {
            NSLog(@"缓存删除失败, %@", md5(self.url));
        }
        return OutOfDate;
    } else if ([[NSDate date]timeIntervalSinceDate:self.cachedTime] <= 60) {//距离上一次加载没到一分钟，无需更新缓存
        return UpdateNeedLess;
    } else {//距离上一次加载超过一分钟，先加载缓存，后台再更新缓存
        return UpdateNeeded;
    }
}

#pragma mark - 归档解档

- (void)encodeWithCoder:(NSCoder *)aCoder {
    unsigned int count ;
    objc_property_t *propertyList = class_copyPropertyList([self class], &count);
    for (unsigned int i = 0; i<count ; i++) {
        objc_property_t property = propertyList[i];
        const char *name = property_getName(property);
        NSString *properName = [NSString stringWithUTF8String:name];
        [aCoder encodeObject:[self valueForKey:properName] forKey:properName];
    }
    free(propertyList);
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        unsigned int count ;
        objc_property_t *propertyList = class_copyPropertyList([self class], &count);
        for (unsigned int i = 0; i<count ; i++) {
            objc_property_t property = propertyList[i];
            const char *name = property_getName(property);
            NSString *properName = [NSString stringWithUTF8String:name];
            [self setValue:[aDecoder decodeObjectForKey:properName] forKey:properName];
        }
        free(propertyList);
    }
    return self;
}

@end

// 注意这个全局函数的写法比较特殊:先在文件@implementation的前面进行声明，接着可以在 @implementation{......}@end 里进行调用，在 @implementation{......}@end 的后面定义
NSString * md5(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), digest );
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return output;
}


//
//  JakeyURLProtocol.m
//  NSURLProtocolExample
//
//  Created by Jake on 2017/7/10.
//  Copyright © 2017年 Rocir Santiago. All rights reserved.
//

#import "JakeyURLProtocol.h"
#import "objc/runtime.h"
#import <CommonCrypto/CommonDigest.h>

static NSString * const kHandledKey = @"HandledKey";

// 缓存有效时间(秒)
static NSInteger const kLimiteTime = 3600*24*2;

// 转化函数。对当前加载的url或者字符串进行md5加密
NSString * md5(NSString *);

@interface JakeyURLProtocol ()<NSURLConnectionDelegate>
@property (nonatomic, strong) NSURLConnection *connection;

@property (nonatomic, strong) NSURLResponse *response;
@property (nonatomic, strong) NSMutableData *mutableData;

@property (nonatomic, strong) NSString *cachedFilePath;
@end



@implementation JakeyURLProtocol

// 每次有一个请求的时候都会调用这个方法，在这个方法里面判断这个请求是否需要被处理拦截
// return YES :  代表这个request需要被控制，需要经过这个NSURLProtocol"协议" 的处理 (包括获取请求数据并返回给 URL Loading System)
// return NO :  这个request不需要经过这个NSURLProtocol"协议" 的处理，URL Loading System会使用系统默认的行为去处理
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    
    NSString *scheme = request.URL.scheme;
    //只处理http和https请求
    if ([scheme caseInsensitiveCompare:@"http"]==NSOrderedSame||[scheme caseInsensitiveCompare:@"https"]==NSOrderedSame) {
        
        //看看是否已经处理过了，防止无限循环
        if ([NSURLProtocol propertyForKey:kHandledKey inRequest:request]) {
            return NO;
        }
        
        return YES;
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}

// 开始请求
- (void)startLoading {
    
    // 设置缓存路径
    NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    self.cachedFilePath = [docPath stringByAppendingPathComponent:md5(self.request.URL.absoluteString)];
    
    // 在缓存表中获取当前request是否有缓存
    YJCachedResponse *cachedResponse = [self cachedResponseForCurrentRequest];
    if (cachedResponse) {
        switch ([cachedResponse isCacheEffective]) {
            case OutOfDate:{
                [self useNetData];
            }
                break;
            case UpdateNeedLess: {
                [self useCacheData:cachedResponse];
            }
                break;
            case UpdateNeeded: {
                [self useCacheData:cachedResponse];
                // 1秒钟之后重新请求，更新缓存
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self useNetData];
                });
            }
                break;
            default:
                break;
        }
    } else {
        [self useNetData];
    }
}

// 使用缓存，通过协议client调用其代理方法进行处理，直接把数据返回给上层网络数据请求者
// 主要在didReceiveResponse和didReceiveData这两个代理方法中对从网络端传来的数据做缓存处理。等下次同样的请求再次进入到 startLoading 函数中时，就可以直接从缓存中获取数据，直接返回给上层网络数据请求者
- (void)useCacheData:(YJCachedResponse *)cachedResponse {
    
    NSLog(@"走缓存, %@", md5(self.request.URL.absoluteString));
    
    // 告知 URL Loading System: 已经为真正的网络请求创建了响应对象，也即: 此时将真正的网络请求后的响应数据设置为这个新的response
    [self.client URLProtocol:self didReceiveResponse:cachedResponse.response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    
    // 告知 URL Loading System: 已经为真正的网络请求加载完数据
    [self.client URLProtocol:self didLoadData:cachedResponse.data];
    
    // 告知 URL Loading System: 真正的网络数据请求已经完成
    [self.client URLProtocolDidFinishLoading:self];
}

// 使用网络请求数据
- (void)useNetData {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    
    // 将此请求标记为已处理
    [NSURLProtocol setProperty:@YES forKey:kHandledKey inRequest:newRequest];
    
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
}

// 请求结束
- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}

#pragma mark - NSURLConnectionDataDelegate

// 在 NSURLConnectionDataDelegate 中进行 Response 的保存和赋值

//当接收到服务器的响应(也即: 连通了服务器)时会调用
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    
    self.response = response;
    self.mutableData = [[NSMutableData alloc] init];
}

//当接收到服务器的数据时会调用(可能会被调用多次,每次只传递部分数据)
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
    [self.mutableData appendData:data];
}

//当服务器的数据加载完毕时就会调用
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
    [self saveCachedResponse];
}

//请求错误(失败)的时候调用(请求超时/断网/没有网,一般指客户端错误)
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
    
}

#pragma mark - Custom Actions

// 保存 Response
- (void)saveCachedResponse {
    YJCachedResponse *response = [[YJCachedResponse alloc] initWithData:self.mutableData response:self.response limiteTime:kLimiteTime];
    NSMutableData *muData = [NSMutableData dataWithData:[NSKeyedArchiver archivedDataWithRootObject:response]];
    BOOL isSuccess = [muData writeToFile:self.cachedFilePath atomically:YES];
    // BOOL isSuccess = [NSKeyedArchiver archiveRootObject:response toFile:self.cachedFilePath];
    NSLog(@"%@  archive success %d", md5(response.url),  isSuccess);
}

- (YJCachedResponse *)cachedResponseForCurrentRequest {
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.cachedFilePath]) {
        return nil;
    }
    YJCachedResponse *response = [NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:self.cachedFilePath]];
//    YJCachedResponse *response = [NSKeyedUnarchiver unarchiveObjectWithFile:self.cachedFilePath];
    return response;
}

@end


// 注意这个全局函数的写法比较特殊:先在文件@implementation的前面进行声明，接着可以在 @implementation{......}@end 里进行调用，在 @implementation{......}@end 的后面定义
//NSString * md5(NSString *input) {
//    const char *cStr = [input UTF8String];
//    unsigned char digest[CC_MD5_DIGEST_LENGTH];
//    CC_MD5( cStr, (CC_LONG)strlen(cStr), digest );
//    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
//    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
//        [output appendFormat:@"%02x", digest[i]];
//    return output;
//}



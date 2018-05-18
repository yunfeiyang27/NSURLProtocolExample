//
//  md5.h
//  NSURLProtocolExample
//
//  Created by leihuan on 18/5/18.
//  Copyright © 2018年 leihuan. All rights reserved.
//

#ifndef md5_h
#define md5_h

NSString * md5(NSString *input) {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), digest );
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++)
        [output appendFormat:@"%02x", digest[i]];
    return output;
}

#endif /* md5_h */

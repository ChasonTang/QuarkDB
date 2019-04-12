//
//  QuarkORM.m
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/10.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import "QuarkORM.h"
#import <objc/runtime.h>

id convertDictionaryToObject(NSDictionary<NSString *, id> *dictionary, Class objectClass) {
    if (dictionary.count == 0) {
        return nil;
    }
    
    __block id object = nil;
    
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        objc_property_t property = class_getProperty(objectClass, key.UTF8String);
        // property 存在
        if (property) {
            const char *attributeCString = property_getAttributes(property);
            if (attributeCString) {
                NSString *attribute = [NSString stringWithUTF8String:attributeCString];
                NSString *objType = nil;
                if ([obj isKindOfClass:NSNumber.class]) {
                    objType = @"T@\"NSNumber\"";
                } else if ([obj isKindOfClass:NSString.class]) {
                    objType = @"T@\"NSString\"";
                } else if ([obj isKindOfClass:NSArray.class]) {
                    objType = @"T@\"NSArray\"";
                } else if ([obj isKindOfClass:NSDictionary.class]) {
                    objType = @"T@\"NSDictionary\"";
                }
                // 并且类型一致，并且不是 readonly
                if (objType && [attribute hasPrefix:objType] && (![attribute containsString:@",R,"] && ![attribute hasSuffix:@",R"])) {
                    // 如果 obj 是 NSNumber 或者 NSString
                    if ([obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSNumber.class]) {
                        // 直接设置
                        
                    }
                    // 如果 obj 是 NSArray
                    if ([obj isKindOfClass:NSArray.class]) {
                        NSArray *valueArray = obj;
                        [valueArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                            
                        }];
                    }
                    if (!object) {
                        object = [[objectClass alloc] init];
                    }
                }
            }
        }
    }];
    
    return object;
}

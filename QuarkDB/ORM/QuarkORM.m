//
//  QuarkORM.m
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/10.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import "QuarkORM.h"
#import <objc/runtime.h>
#import <objc/message.h>

id convertDictionaryToObject(NSDictionary<NSString *, id> *dictionary, Class objectClass) {
    if (dictionary.count == 0) {
        return nil;
    }
    
    __block id object = nil;
    
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (![obj isKindOfClass:NSNumber.class] && ![obj isKindOfClass:NSString.class] && ![obj isKindOfClass:NSArray.class] && ![obj isKindOfClass:NSDictionary.class]) {
            // obj 不是 NSNumber NSString NSArray NSDictionary 类型直接过滤掉
            return;
        }
        objc_property_t property = class_getProperty(objectClass, key.UTF8String);
        // property 存在
        if (property) {
            const char *attributeCString = property_getAttributes(property);
            if (attributeCString) {
                
                NSString *attribute = [NSString stringWithUTF8String:attributeCString];
                NSArray<NSString *> *attributeArray = [attribute componentsSeparatedByString:@","];
                
                if ([attributeArray containsObject:@"R"]) {
                    // 只读 property 忽略
                    return;
                }

                // 获取 setter
                // 如果存在 setter= 的自定义 setter 情况
                __block NSString *setterMethodString = nil;
                if ([attribute containsString:@",S"]) {
                    [attributeArray enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        if ([obj hasPrefix:@"S"] && obj.length >= 2) {
                            setterMethodString = [obj substringFromIndex:1];
                            *stop = YES;
                        }
                    }];
                } else {
                    // 标准 setter
                    NSString *propertyName = [NSString stringWithUTF8String:property_getName(property)];
                    if (propertyName.length >= 1) {
                        NSString *firstWord = [propertyName substringToIndex:1].uppercaseString;
                        NSString *otherWord = nil;
                        if (propertyName.length >= 2) {
                            otherWord = [propertyName substringFromIndex:1];
                        }
                        setterMethodString = [NSString stringWithFormat:@"set%@%@:", firstWord, otherWord.length > 0 ? otherWord : @""];
                    }
                }
                
                if (setterMethodString.length == 0) {
                    // 没有 setter 方法则忽略
                    return;
                }
                
                SEL setterSelector = NSSelectorFromString(setterMethodString);
                
                if (attributeArray.firstObject && attributeArray.firstObject.length > 4) {
                    // T@"ClassName" 必定大于 4
                    NSString *className = [attributeArray.firstObject substringWithRange:NSMakeRange(3, attributeArray.firstObject.length - 4)];
                    Class class = NSClassFromString(className);
                    
                    if (![class instancesRespondToSelector:setterSelector]) {
                        // 没有对应的 setter 响应则忽略
                        return;
                    }
                    
                    if ([obj isKindOfClass:NSDictionary.class]) {
                        // 需要递归调用 convertDictionaryToObject
                        id value = convertDictionaryToObject(filterNSStringItem(obj), class);
                        if (!object) {
                            object = [[class alloc] init];
                        }
                        ((void (*)(id, SEL, id)) objc_msgSend)(object, setterSelector, value);
                        
                        return;
                    }
                    
                    if ([obj isKindOfClass:NSArray.class]) {
                        // TODO: 数组
                        return;
                    }
                    
                    if ([obj isKindOfClass:class]) {
                        // obj 必须是 property 的对象或者子类对象才能赋值
                        // 上面判断过 NSNumber NSString，因此这里只能是其子类或者基类
                        ((void (*)(id, SEL, id)) objc_msgSend)(object, setterSelector, obj);
                    }
                } else {
                    // 属性字符串不符合规范，忽略
                    return;
                }
            }
        }
    }];
    
    return object;
}

NSDictionary<NSString *, id> * filterNSStringItem(NSDictionary *dictionary) {
    NSMutableDictionary<NSString *, id> *mutableCopy = [NSMutableDictionary<NSString *, id> dictionaryWithCapacity:dictionary.count];
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([key isKindOfClass:NSString.class]) {
            mutableCopy[key] = obj;
        }
    }];
    
    return mutableCopy.count > 0 ? mutableCopy.copy : nil;
}

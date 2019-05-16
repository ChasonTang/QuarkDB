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

NS_ASSUME_NONNULL_BEGIN

void fetchAllSettableProperty(Class cls, objc_property_t *_Nullable destinationPropertyList, unsigned int *_Nullable destinationCount);

NS_ASSUME_NONNULL_END

void fetchAllSettableProperty(Class cls, objc_property_t *destinationPropertyList, unsigned int *destinationCount) {
    // 防御 destinationCount 和 destinationPropertyList 不匹配的情况
    // 1. (destinationCount == NULl || *destinationCount == 0) && destinationPropertyList != NULL
    // 2. destinationCount != NULL && *destinationCount != 0 && destinationPropertyList == NULL
    if (((destinationCount == NULL || *destinationCount == 0) && destinationPropertyList != NULL) || (destinationCount != NULL && *destinationCount != 0 && destinationPropertyList == NULL)) {
        return;
    }
    
    unsigned int count = 0;
    objc_property_t *propertyList = class_copyPropertyList(cls, &count);
    for (unsigned int i = 0; i < count; ++i) {
        char *value = property_copyAttributeValue(propertyList[i], "R");
        if (value) {
            // 只读 property 忽略
            free(value);
            continue;
        }
        
        char *attributeValueCString = property_copyAttributeValue(propertyList[i], "C");
        if (!attributeValueCString) {
            // 目前要求 copy
            continue;
        }
        free(attributeValueCString);
        
        attributeValueCString = property_copyAttributeValue(propertyList[i], "T");
        if (!attributeValueCString) {
            continue;
        }
        NSString *attributeValueString = [NSString stringWithUTF8String:attributeValueCString];
        if (!attributeValueString) {
            free(attributeValueCString);
            continue;
        }
        free(attributeValueCString);
        // 扫描类型
        NSScanner *scanner = [NSScanner scannerWithString:attributeValueString];
        if (![scanner scanString:@"@\"" intoString:nil]) {
            // 目前只支持对象
            continue;
        }
        
        if (!destinationCount) {
            destinationCount = malloc(sizeof(unsigned int));
            *destinationCount = 0;
        }
        // 将 objc_property_t 复制到目标数组
        // 如果 destinationPropertyList 没有分配内存
        if (!destinationPropertyList) {
            destinationPropertyList = malloc(sizeof(objc_property_t));
        } else {
            destinationPropertyList = realloc(destinationPropertyList, sizeof(objc_property_t) * (*destinationCount + 1));
        }
        destinationPropertyList[*destinationCount] = propertyList[i];
        ++*destinationCount;
    }
    // free 可以释放 NULL
    free(propertyList);
}

id convertObjectToObject(id jsonObject, Class objectClass) {
    // NSJSONSerialization 在数字比较大的时候会使用 NSDecimalNumber
    // NSNull 也是会被转换的，但是转模型不需要转这个类型
    // NSJSONReadingMutableContainers 导致变为 mutable JSON Array/Dictionary
    // NSJSONReadingMutableLeaves 导致叶子结点变为 NSMutableString
    // 这里隐含支持的 JSON 类型有 NSMutableString NSNull NSMutableDictionary NSMutableArray NSDecimalNumber
    if (![jsonObject isKindOfClass:NSString.class] || ![jsonObject isKindOfClass:NSNumber.class] || ![jsonObject isKindOfClass:NSArray.class] || ![jsonObject isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    id convertedObject = nil;
    if ((objectClass == NSString.class && [jsonObject isKindOfClass:NSString.class]) || (objectClass == NSNumber.class && [jsonObject isKindOfClass:NSNumber.class])) {
        return jsonObject;
    } else if (objectClass == NSArray.class && [jsonObject isKindOfClass:NSArray.class]) {
        // TODO: 循环赋值
    } else if ([jsonObject isKindOfClass:NSDictionary.class]){
        // TODO: 递归赋值
        NSDictionary *dictionary = jsonObject;
    } else {
        return nil;
    }
    
    unsigned int totalCount = 0;
    objc_property_t *totalPropertyList = NULL;
    
    if ([objectClass conformsToProtocol:@protocol(QuarkORMModel)]) {
        // 递归查找
        Class cls = objectClass;
        for (; cls; cls = class_getSuperclass(cls)) {
            fetchAllSettableProperty(cls, totalPropertyList, &totalCount);
            
            BOOL isContainProtocol = NO;
            unsigned int protocolCount = 0;
            Protocol * __unsafe_unretained *protocolList = class_copyProtocolList(cls, &protocolCount);
            for (unsigned int i = 0; i < protocolCount; ++i) {
                NSString *protocolName = [NSString stringWithUTF8String:protocol_getName(protocolList[i])];
                if ([protocolName isEqualToString:NSStringFromProtocol(@protocol(QuarkORMModel))]) {
                    isContainProtocol = YES;
                    break;
                }
            }
            free(protocolList);
            if (isContainProtocol) {
                break;
            }
        }
    } else {
        fetchAllSettableProperty(objectClass, totalPropertyList, &totalCount);
    }
    
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        // NSJSONSerialization 在数字比较大的时候会使用 NSDecimalNumber
        // NSNull 也是会被转换的，但是转模型不需要转这个类型
        // NSJSONReadingMutableContainers 导致变为 mutable JSON Array/Dictionary
        // NSJSONReadingMutableLeaves 导致叶子结点变为 NSMutableString
        // 这里隐含支持的 JSON 类型有 NSMutableString NSNull NSMutableDictionary NSMutableArray NSDecimalNumber
        if (![obj isKindOfClass:NSString.class] || ![obj isKindOfClass:NSNumber.class] || ![obj isKindOfClass:NSArray.class] || ![obj isKindOfClass:NSDictionary.class]) {
            return;
        }
        for (unsigned int i = 0; i < totalCount; ++i) {
            NSString *nameString = [NSString stringWithUTF8String:property_getName(totalPropertyList[i])];
            if (nameString.length > 0 && [nameString isEqualToString:key]) {
                // 匹配到 key
                // 判断类型相等
                char *attributeValueCString = property_copyAttributeValue(totalPropertyList[i], "T");
                if (!attributeValueCString) {
                    break;
                }
                NSString *attributeValueString = [NSString stringWithUTF8String:attributeValueCString];
                if (!attributeValueString) {
                    free(attributeValueCString);
                    break;
                }
                free(attributeValueCString);
                // 扫描类型
                NSScanner *scanner = [NSScanner scannerWithString:attributeValueString];
                if (![scanner scanString:@"@\"" intoString:nil]) {
                    // 目前只支持对象，但是实际上前面已经过滤这种情况，属于兜底代码
                    break;
                }
                NSString *propertyType = nil;
                [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"<"]
                                        intoString:&propertyType];
                if (!propertyType) {
                    // propertyType 为空，正常情况不应该存在
                    break;
                }
                Class propertyClass = NSClassFromString(propertyType);
                if (!propertyClass) {
                    // 正常流程不应该存在 propertyClass == nil 的情况
                    break;
                }
                NSString *protocolName = nil;
                // 读取第一个协议名
                if ([scanner scanString:@"<" intoString:nil]) {
                    [scanner scanUpToString:@">" intoString:&protocolName];
                    
                    [scanner scanString:@">" intoString:NULL];
                }
                Class protocolClass = nil;
                if (protocolName) {
                    protocolClass = NSClassFromString(protocolName);
                }
                id convertedObject = nil;
                if ((propertyClass == NSString.class && [obj isKindOfClass:NSString.class]) || (propertyClass == NSNumber.class && [obj isKindOfClass:NSNumber.class])) {
                    // 直接赋值 NSString/NSNumber
                    convertedObject = obj;
                } else if (propertyClass == NSArray.class && protocolClass && [obj isKindOfClass:NSArray.class]) {
                    // 属于数组并且带有类型，则循环转换
                    NSMutableArray *resultArray = nil;
                    [obj enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                        id arrayObject = nil;
                        if ((protocolClass == NSString.class && [obj isKindOfClass:NSString.class]) || (protocolClass == NSNumber.class && [obj isKindOfClass:NSNumber.class])) {
                            // 直接赋值
                            arrayObject = obj;
                        } else if ()
                    }];
                } else if ([obj isKindOfClass:NSDictionary.class]){
                    // 对象类型，转换
                    convertedObject = convertDictionaryToObject(obj, propertyClass);
                }
                // 获取 setter
                NSString *setterMethodString = nil;
                attributeValueCString = property_copyAttributeValue(totalPropertyList[i], "S");
                if (attributeValueCString) {
                    // 自定义 setter
                    setterMethodString = [NSString stringWithUTF8String:attributeValueCString];
                } else {
                    // 默认 setter
                    // 上面已经判断过 nameString.length > 0
                    NSString *firstWord = [nameString substringToIndex:1].uppercaseString;
                    NSString *otherWord = nil;
                    if (nameString.length > 1) {
                        otherWord = [nameString substringFromIndex:1];
                    }
                    setterMethodString = [NSString stringWithFormat:@"set%@%@:", firstWord, otherWord.length > 0 ? otherWord : @""];
                }
                free(attributeValueCString);
                if (setterMethodString.length == 0) {
                    // 正常情况不应该走到这里，属于对 stringWithUTF8String 返回 nil 的兜底处理
                    break;
                }
                // TODO: 调用 setter 赋值
                break;
            }
        }
        
        for (unsigned i = 0; i < totalCount; ++i) {
            NSString *nameString = [NSString stringWithCString:property_getName(totalPropertyList[i]) encoding:NSUTF8StringEncoding];
            if ([nameString isEqualToString:key]) {
                // 匹配到 key
                const char *attributeCString = property_getAttributes(totalPropertyList[i]);
                if (attributeCString) {
                    NSString *attributeString = [NSString stringWithCString:attributeCString encoding:NSUTF8StringEncoding];
                    NSArray<NSString *> *attributeArray = [attributeString componentsSeparatedByString:@","];
                    if ([attributeArray containsObject:@"R"]) {
                        // 只读 property 忽略
                        break;
                    }
                    // 获取 setter
                    // 如果存在 setter= 的自定义 setter 情况
                    __block NSString *setterMethodString = nil;
                    if ([attributeString containsString:@",S"]) {
                        [attributeArray enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                            if ([obj hasPrefix:@"S"] && obj.length >= 2) {
                                setterMethodString = [obj substringFromIndex:1];
                                *stop = YES;
                            }
                        }];
                    } else {
                        // 标准 setter
                        if (nameString.length >= 1) {
                            NSString *firstWord = [nameString substringToIndex:1].uppercaseString;
                            NSString *otherWord = nil;
                            if (nameString.length >= 2) {
                                otherWord = [nameString substringFromIndex:1];
                            }
                            setterMethodString = [NSString stringWithFormat:@"set%@%@:", firstWord, otherWord.length > 0 ? otherWord : @""];
                        }
                    }
                }
                
                break;
            }
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
    
    // totalPropertyList == NULl, free will no operation
    free(totalPropertyList);
    
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

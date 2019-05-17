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

void fetchAllSettableProperty(Class cls, objc_property_t *_Nullable *destinationPropertyList, unsigned int *destinationCount);

NS_ASSUME_NONNULL_END

void fetchAllSettableProperty(Class cls, objc_property_t **destinationPropertyListPointer, unsigned int *destinationCountPointer) {
    if (destinationPropertyListPointer == NULL || destinationCountPointer == NULL) {
        return;
    }
    // 防御 destinationCount 和 destinationPropertyList 不匹配的情况
    // 1. *destinationCountPointer == 0 && *destinationPropertyListPointer != NULL
    // 2. *destinationCountPointer != 0 && *destinationPropertyListPointer == NULL
    if ((*destinationCountPointer == 0 && *destinationPropertyListPointer != NULL) || (*destinationCountPointer != 0 && *destinationPropertyListPointer == NULL)) {
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
        // 将 objc_property_t 复制到目标数组
        *destinationPropertyListPointer = reallocf(*destinationPropertyListPointer, sizeof(objc_property_t) * (*destinationCountPointer + 1));
        if (destinationPropertyListPointer) {
            // 由于 [] 比 * 优先级更高，因此需要使用括号
            (*destinationPropertyListPointer)[*destinationCountPointer] = propertyList[i];
            ++*destinationCountPointer;
        }
    }
    // free 可以释放 NULL
    free(propertyList);
}

id convertDictionaryToObject(NSDictionary<NSString *, id> *dictionary, Class objectClass) {
    if (dictionary.count == 0) {
        return nil;
    }
    
    unsigned int totalCount = 0;
    objc_property_t *totalPropertyList = NULL;
    
    if ([objectClass conformsToProtocol:@protocol(QuarkORMModel)]) {
        // 递归查找
        Class cls = objectClass;
        for (; cls; cls = class_getSuperclass(cls)) {
            fetchAllSettableProperty(cls, &totalPropertyList, &totalCount);
            
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
        fetchAllSettableProperty(objectClass, &totalPropertyList, &totalCount);
    }
    
    __block id modelObject = nil;
    
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
                    convertedObject = convertArrayToObject(obj, protocolClass);
                } else if ([obj isKindOfClass:NSDictionary.class]){
                    // 对象类型，转换
                    convertedObject = convertDictionaryToObject(obj, propertyClass);
                }
                if (!convertedObject) {
                    // 如果没有可转换的对象，则跳过
                    break;
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
                // 调用 setter 赋值
                SEL setterSelector = NSSelectorFromString(setterMethodString);
                if (![objectClass instancesRespondToSelector:setterSelector]) {
                    // 没有对应的 setter 响应则忽略，但是一般情况下不会进这个逻辑，因为 readwrite property 肯定有 setter
                    break;
                }
                if (!modelObject) {
                    // 由于设计构造函数运行时无法获取，因此只能使用 init 构造
                    modelObject = [[objectClass alloc] init];
                }
                ((void (*)(id, SEL, id)) objc_msgSend)(modelObject, setterSelector, convertedObject);
                
                break;
            }
        }
    }];
    
    // totalPropertyList == NULl, free will no operation
    free(totalPropertyList);
    
    return modelObject;
}

NSArray *convertArrayToObject(NSArray *array, Class arrayItemClass) {
    if (array.count == 0) {
        return nil;
    }
    // 这里只能支持 NSString NSNumber NSDictionary 转换，不支持 NSArray 嵌套转换，因为丢失了类型信息
    if (arrayItemClass != NSString.class && arrayItemClass != NSNumber.class && arrayItemClass != NSDictionary.class) {
        return nil;
    }
    __block NSMutableArray *resultMutableArray = nil;
    [array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id item = nil;
        if ((arrayItemClass == NSString.class && [obj isKindOfClass:NSString.class]) || (arrayItemClass == NSNumber.class && [obj isKindOfClass:NSNumber.class])) {
            item = obj;
        } else if (arrayItemClass == NSDictionary.class && [obj isKindOfClass:NSDictionary.class]) {
            item = convertDictionaryToObject(obj, arrayItemClass);
        }
        if (item) {
            if (!resultMutableArray) {
                resultMutableArray = [NSMutableArray arrayWithCapacity:array.count];
            }
            // 添加对象
            [resultMutableArray addObject:item];
        }
    }];
    
    // iOS 11 之前可能存在性能问题
    return resultMutableArray.copy;
}

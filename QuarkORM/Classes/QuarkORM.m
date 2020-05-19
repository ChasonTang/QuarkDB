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

static void fetchAllGettableOrSettableProperty(Class cls, objc_property_t *_Nullable *destinationPropertyList, unsigned int *destinationCount, BOOL isGettableProperty);

static void extractProperty(Class objectClass, unsigned int *totalCount, objc_property_t *_Nullable *totalPropertyList, BOOL isGettableProperty);

static NSString *_Nullable convert_underline_to_camel_case(NSString *underlineString);

NS_ASSUME_NONNULL_END

NSString *convert_underline_to_camel_case(NSString *underlineString) {
    NSArray<NSString *> *componentArray = [underlineString componentsSeparatedByString:@"_"];
    if (componentArray.count > 0) {
        NSMutableArray<NSString *> *resultComponentArray = [NSMutableArray arrayWithCapacity:componentArray.count];
        [componentArray enumerateObjectsUsingBlock:^(NSString *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
            if (idx != 0 && obj.length > 0) {
                NSString *firstWord = [obj substringToIndex:1].uppercaseString;
                NSString *otherWord = nil;
                if (obj.length > 1) {
                    otherWord = [obj substringFromIndex:1];
                }
                [resultComponentArray addObject:[NSString stringWithFormat:@"%@%@", firstWord, otherWord ?: @""]];
            } else {
                [resultComponentArray addObject:obj];
            }
        }];

        return [resultComponentArray componentsJoinedByString:@""];
    } else {
        return nil;
    }
}

void fetchAllGettableOrSettableProperty(Class cls, objc_property_t **destinationPropertyListPointer, unsigned int *destinationCountPointer, BOOL isGettableProperty) {
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
        if (value && !isGettableProperty) {
            // 获取 setter 的时候，只读 property 忽略
            free(value);
            continue;
        }
        // 如果获取 getter 时，此属性为 readonly，会导致 value 有内存分配，因此需要 free
        free(value);
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
        if (*destinationPropertyListPointer) {
            // 由于 [] 比 * 优先级更高，因此需要使用括号
            (*destinationPropertyListPointer)[*destinationCountPointer] = propertyList[i];
            ++*destinationCountPointer;
        } else {
            *destinationCountPointer = 0;
        }
    }
    // free 可以释放 NULL
    free(propertyList);
}

void extractProperty(Class objectClass, unsigned int *totalCount, objc_property_t *_Nullable *totalPropertyList, BOOL isGettableProperty) {
    if ([objectClass conformsToProtocol:@protocol(QuarkORMModel)]) {
        // 递归查找
        Class cls = objectClass;
        for (; cls; cls = class_getSuperclass(cls)) {
            fetchAllGettableOrSettableProperty(cls, totalPropertyList, totalCount, isGettableProperty);
            
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
        fetchAllGettableOrSettableProperty(objectClass, totalPropertyList, totalCount, isGettableProperty);
    }
}

id qk_convert_dictionary_to_object(NSDictionary<NSString *, id> *dictionary, Class objectClass, BOOL needUnderlineToCamelCase) {
    if (dictionary.count == 0) {
        return nil;
    }
    
    unsigned int totalCount = 0;
    objc_property_t *totalPropertyList = NULL;
    
    extractProperty(objectClass, &totalCount, &totalPropertyList, NO);
    
    __block id modelObject = nil;
    
    [dictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSString *newKey = key;
        if (needUnderlineToCamelCase) {
            newKey = convert_underline_to_camel_case(key);
        }
        if (newKey.length > 0) {
            key = newKey;
        }
        // NSJSONSerialization 在数字比较大的时候会使用 NSDecimalNumber
        // NSNull 也是会被转换的，但是转模型不需要转这个类型
        // NSJSONReadingMutableContainers 导致变为 mutable JSON Array/Dictionary
        // NSJSONReadingMutableLeaves 导致叶子结点变为 NSMutableString
        // 这里隐含支持的 JSON 类型有 NSMutableString NSMutableDictionary NSMutableArray NSDecimalNumber
        if (![obj isKindOfClass:NSString.class] && ![obj isKindOfClass:NSNumber.class] && ![obj isKindOfClass:NSArray.class] && ![obj isKindOfClass:NSDictionary.class]) {
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
                if (([obj isKindOfClass:NSDecimalNumber.class] && propertyClass == NSDecimalNumber.class) || (propertyClass == NSNumber.class && [obj isKindOfClass:NSNumber.class]) || (propertyClass == NSString.class && [obj isKindOfClass:NSString.class])) {
                    // 直接赋值 NSString/NSNumber
                    convertedObject = obj;
                } else if (propertyClass == NSArray.class && [obj isKindOfClass:NSArray.class]) {
                    // 属于数组，则循环转换
                    NSArray *arrayObj = obj;
                    if (arrayObj.count == 0) {
                        convertedObject = nil;
                    } else {
                        __block NSMutableArray *resultMutableArray = nil;
                        [arrayObj enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                            id item = nil;
                            // 数组带类型，则要求类型匹配，或者字典转模型
                            // 没有类型则只支持 NSArray NSNumber NSDecimalNumber，等价于 NSArray<NSNumber, NSString, NSDecimalNumber> * 声明了三个协议
                            if ((protocolClass == NSDecimalNumber.class && [obj isKindOfClass:NSDecimalNumber.class]) || (protocolClass == NSString.class && [obj isKindOfClass:NSString.class]) || (protocolClass == NSNumber.class && [obj isKindOfClass:NSNumber.class]) || [obj isKindOfClass:NSString.class] || [obj isKindOfClass:NSNumber.class]) {
                                item = obj;
                            } else if (protocolClass && [obj isKindOfClass:NSDictionary.class]) {
                                item = qk_convert_dictionary_to_object(obj, protocolClass, needUnderlineToCamelCase);
                            }
                            
                            if (item) {
                                if (!resultMutableArray) {
                                    resultMutableArray = [NSMutableArray arrayWithCapacity:arrayObj.count];
                                }
                                // 添加对象
                                [resultMutableArray addObject:item];
                            }
                        }];
                        // iOS 11 之前可能存在性能问题
                        convertedObject = resultMutableArray.copy;
                    }
                } else if ([obj isKindOfClass:NSDictionary.class]){
                    // 对象类型，转换
                    convertedObject = qk_convert_dictionary_to_object(obj, propertyClass, needUnderlineToCamelCase);
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

NSDictionary *qk_convert_object_to_dictionary(id model) {
    unsigned int totalCount = 0;
    objc_property_t *totalPropertyList = NULL;
    
    extractProperty([model class], &totalCount, &totalPropertyList, YES);
    
    NSMutableDictionary *jsonDictionary = nil;
    if (totalCount == 0 || totalPropertyList == NULL) {
        return nil;
    }
    // 这里使用 int i 是为了防止 unsigned int 溢出
    for (int i = totalCount - 1; i >= 0; --i) {
        NSString *propertyName = [NSString stringWithUTF8String:property_getName(totalPropertyList[i])];
        // 没有 propertyName 则直接下一个属性
        if (!propertyName) {
            continue;
        }
        char *attributeValueCString = property_copyAttributeValue(totalPropertyList[i], "T");
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
        NSString *propertyType = nil;
        [scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\"<"]
                                intoString:&propertyType];
        if (!propertyType) {
            // propertyType 为空，正常情况不应该存在
            continue;
        }
        Class propertyClass = NSClassFromString(propertyType);
        if (!propertyClass) {
            // 正常流程不应该存在 propertyClass == nil 的情况
            continue;
        }
        
        // 获取 getter
        NSString *getterMethodString = nil;
        attributeValueCString = property_copyAttributeValue(totalPropertyList[i], "G");
        if (attributeValueCString) {
            // 自定义 getter
            getterMethodString = [NSString stringWithUTF8String:attributeValueCString];
        } else {
            // 默认 getter
            getterMethodString = propertyName;
        }
        free(attributeValueCString);
        if (getterMethodString.length == 0) {
            // 正常情况不应该走到这里，属于对 stringWithUTF8String 返回 nil 的兜底处理
            continue;
        }
        // 调用 getter 赋值
        SEL getterSelector = NSSelectorFromString(getterMethodString);
        if (![[model class] instancesRespondToSelector:getterSelector]) {
            // 没有对应的 setter 响应则忽略，但是一般情况下不会进这个逻辑，因为 readwrite property 肯定有 setter
            continue;
        }
        id propertyObject = ((id (*)(id, SEL)) objc_msgSend)(model, getterSelector);
        // 设置字典
        if (!propertyObject) {
            // nil 则继续
            continue;
        }
        id item = nil;
        if (propertyClass == NSString.class || propertyClass == NSNumber.class || propertyClass == NSDecimalNumber.class) {
            // 直接设置
            item = propertyObject;
        } else if (propertyClass == NSArray.class) {
            item = qk_convert_object_array_to_array(propertyObject);
        } else {
            // 递归设置
            item = qk_convert_object_to_dictionary(propertyObject);
        }
        
        if (item) {
            if (!jsonDictionary) {
                jsonDictionary = [NSMutableDictionary dictionaryWithCapacity:totalCount];
            }
            jsonDictionary[propertyName] = item;
        }
    }
    
    free(totalPropertyList);
    
    return jsonDictionary.copy;
}

NSArray *_Nullable qk_convert_object_array_to_array(NSArray *array) {
    __block NSMutableArray *resultArray = nil;
    [array enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        id item = nil;
        if ([obj isKindOfClass:NSNumber.class] || [obj isKindOfClass:NSString.class]) {
            item = obj;
        } else if ([obj isKindOfClass:NSArray.class]) {
            item = qk_convert_object_array_to_array(obj);
        } else {
            item = qk_convert_object_to_dictionary(obj);
        }
        if (item) {
            if (!resultArray) {
                resultArray = [NSMutableArray arrayWithCapacity:array.count];
            }
            [resultArray addObject:item];
        }
    }];
    
    return resultArray.copy;
}

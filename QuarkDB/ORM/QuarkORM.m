//
//  QuarkORM.m
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/10.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import "QuarkORM.h"

id convertDictionaryToObject(NSDictionary *dictionary, Class objectClass) {
    if (dictionary.count == 0) {
        return nil;
    }
    // 表示 dictionary 中至少有一个字段能转换到对象字段中
    __block BOOL isConvertable = NO;
    [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        
    }]
}

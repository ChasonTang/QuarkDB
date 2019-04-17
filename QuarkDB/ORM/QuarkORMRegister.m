//
//  QuarkORMRegister.m
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/13.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import "QuarkORMRegister.h"

NS_ASSUME_NONNULL_BEGIN

@interface QuarkORMRegister ()

@property (nonatomic, copy, nullable) NSDictionary<Class<QuarkORMProtocol>, > *mapperArray;

@end

NS_ASSUME_NONNULL_END

@implementation QuarkORMRegister

- (void)registeMapperWithClass:(Class<QuarkORMProtocol>)class {
    if (!self.mapperArray) {
        self.mapperArray = [NSSet<Class<QuarkORMProtocol>> setWithObject:class];
    } else {
        NSMutableSet<Class<QuarkORMProtocol>> *mapperArray = self.mapperArray.mutableCopy;
        [mapperArray addObject:class];
        self.mapperArray = mapperArray;
    }
}

@end

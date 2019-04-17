//
//  QuarkORMAttribute.h
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/13.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, QuarkORMStorageEnumeration) {
    QuarkORMStorageEnumerationAssign = 0,
    QuarkORMStorageEnumerationCopy,
    QuarkORMStorageEnumerationStrong,
    QuarkORMStorageEnumerationWeak,
}

@interface QuarkORMAttribute : NSObject

@property (nonatomic, assign) BOOL isReadonly;

@property (nonatomic, assign) BOOL isAtomic;

@property ()

@end

NS_ASSUME_NONNULL_END

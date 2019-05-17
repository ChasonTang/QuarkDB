//
//  QuarkORM.h
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/10.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol QuarkORMModel

@end

id _Nullable convertDictionaryToObject(NSDictionary *dictionary, Class objectClass);

id _Nullable convertObjectToDictionaryOrArray(id model);

NS_ASSUME_NONNULL_END

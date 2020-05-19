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

id _Nullable qk_convert_dictionary_to_object(NSDictionary *dictionary, Class objectClass, BOOL needUnderlineToCamelCase);

NSDictionary *_Nullable qk_convert_object_to_dictionary(id model);

NSArray *_Nullable qk_convert_object_array_to_array(NSArray *array);

NS_ASSUME_NONNULL_END

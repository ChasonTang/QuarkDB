//
//  QuarkORMRegister.h
//  QuarkDB
//
//  Created by ChasonTang on 2019/4/13.
//  Copyright © 2019 Warmbloom. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol QuarkORMProtocol
@end

@interface QuarkORMRegister : NSObject

- (void)registeMapperWithClass:(Class<QuarkORMProtocol>)class;

@end

NS_ASSUME_NONNULL_END

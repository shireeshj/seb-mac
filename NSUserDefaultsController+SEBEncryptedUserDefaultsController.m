//
//  NSUserDefaultsController+SEBEncryptedUserDefaultsController.m
//  SafeExamBrowser
//
//  Created by Daniel R. Schneider on 30.08.12.
//  Copyright (c) 2010-2014 Daniel R. Schneider, ETH Zurich,
//  Educational Development and Technology (LET),
//  based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen
//  Project concept: Thomas Piendl, Daniel R. Schneider,
//  Dirk Bauer, Kai Reuter, Tobias Halbherr, Karsten Burger, Marco Lehre,
//  Brigitte Schmucki, Oliver Rahs. French localization: Nicolas Dunand
//
//  ``The contents of this file are subject to the Mozilla Public License
//  Version 1.1 (the "License"); you may not use this file except in
//  compliance with the License. You may obtain a copy of the License at
//  http://www.mozilla.org/MPL/
//
//  Software distributed under the License is distributed on an "AS IS"
//  basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
//  License for the specific language governing rights and limitations
//  under the License.
//
//  The Original Code is Safe Exam Browser for Mac OS X.
//
//  The Initial Developer of the Original Code is Daniel R. Schneider.
//  Portions created by Daniel R. Schneider are Copyright
//  (c) 2010-2014 Daniel R. Schneider, ETH Zurich, Educational Development
//  and Technology (LET), based on the original idea of Safe Exam Browser
//  by Stefan Schneider, University of Giessen. All Rights Reserved.
//
//  Contributor(s): ______________________________________.
//


#import "NSUserDefaultsController+SEBEncryptedUserDefaultsController.h"
#import "NSUserDefaults+SEBEncryptedUserDefaults.h"
#import "RNEncryptor.h"
#import "RNDecryptor.h"
#import "SEBCryptor.h"
#import "Constants.h"

@implementation NSUserDefaultsController (SEBEncryptedUserDefaultsController)


- (id)secureValueForKeyPath:(NSString *)keyPath
{
    if ([NSUserDefaults userDefaultsPrivate]) {
        NSArray *pathElements = [keyPath componentsSeparatedByString:@"."];
        NSString *key = [pathElements objectAtIndex:[pathElements count]-1];
        id value = [[NSUserDefaults privateUserDefaults] valueForKey:key];
        //id value = [self.defaults secureObjectForKey:key];
#ifdef DEBUG
        NSLog(@"keypath: %@ [[NSUserDefaults privateUserDefaults] valueForKey:%@]] = %@", keyPath, key, value);
#endif
        return value;
    } else {
        NSData *encrypted = [super valueForKeyPath:keyPath];
        
        if (encrypted == nil) {
            // Value = nil -> invalid
            return nil;
        }
        NSError *error;
//        NSData *decrypted = [RNDecryptor decryptData:encrypted
//                                        withPassword:userDefaultsMasala
//                                               error:&error];
        NSData *decrypted = [[SEBCryptor sharedSEBCryptor] decryptData:encrypted error:&error];
        
        id value = [NSKeyedUnarchiver unarchiveObjectWithData:decrypted];
#ifdef DEBUG
        NSLog(@"[super valueForKeyPath:%@] = %@ (decrypted)", keyPath, value);
#endif
        return value;
    }
}


- (void)setSecureValue:(id)value forKeyPath:(NSString *)keyPath
{
    if ([NSUserDefaults userDefaultsPrivate]) {
        NSArray *pathElements = [keyPath componentsSeparatedByString:@"."];
        NSString *key = [pathElements objectAtIndex:[pathElements count]-1];
        if (value == nil) value = [NSNull null];
        [[NSUserDefaults privateUserDefaults] setValue:value forKey:key];
        //[self.defaults setSecureObject:value forKey:key];
#ifdef DEBUG
        NSLog(@"keypath: %@ [[NSUserDefaults privateUserDefaults] setValue:%@ forKey:%@]", keyPath, value, key);
#endif
    } else {
        if (value == nil || keyPath == nil) {
            // Use non-secure method
            [super setValue:value forKeyPath:keyPath];
            
        } else {
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:value];
            NSError *error;
//            NSData *encryptedData = [RNEncryptor encryptData:data
//                                                withSettings:kRNCryptorAES256Settings
//                                                    password:userDefaultsMasala
//                                                       error:&error];
            NSData *encryptedData = [[SEBCryptor sharedSEBCryptor] encryptData:data error:&error];
            
#ifdef DEBUG
            NSLog(@"[super setValue:(encrypted %@) forKeyPath:%@]", value, keyPath);
#endif
            [super setValue:encryptedData forKeyPath:keyPath];
        }
    }
}


@end

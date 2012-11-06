//
//  TDCache.m
//  TouchDB
//
//  Created by Jens Alfke on 6/17/11.
//  Copyright 2011 Couchbase, Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "TDCache.h"


static const NSUInteger kDefaultRetainLimit = 50;


@implementation TDCache


- (id)init {
    return [self initWithRetainLimit: kDefaultRetainLimit];
}


- (id)initWithRetainLimit: (NSUInteger)retainLimit {
    self = [super init];
    if (self) {
#if TDCACHE_IS_SMART
        // Construct an NSMapTable with weak references to values, which automatically removes
        // key/value pairs when a value is dealloced.
        _map = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsStrongMemory |
                                                       NSPointerFunctionsObjectPersonality
                                         valueOptions: NSPointerFunctionsZeroingWeakMemory |
                                                       NSPointerFunctionsObjectPersonality
                                             capacity: 100];
#else
        // Construct a CFDictionary that doesn't retain its values. It does _not_ automatically
        // remove dealloced values, so we'll have to do it manually in -resourceBeingDeallocated.
        CFDictionaryValueCallBacks valueCB = kCFTypeDictionaryValueCallBacks;
        valueCB.retain = NULL;
        valueCB.release = NULL;
        _map = (NSMutableDictionary*)CFBridgingRelease(CFDictionaryCreateMutable(
                       NULL, 100, &kCFCopyStringDictionaryKeyCallBacks, &valueCB));
#endif
        if (retainLimit > 0) {
            _cache = [[NSCache alloc] init];
            _cache.countLimit = retainLimit;
        }
    }
    return self;
}


#if ! TDCACHE_IS_SMART
- (void)dealloc {
    for (id<TDCacheable> doc in _map.objectEnumerator)
        doc.owningCache = nil;
}
#endif


- (void) addResource: (id<TDCacheable>)resource {
#if ! TDCACHE_IS_SMART
    resource.owningCache = self;
#endif
    NSString* key = resource.cacheKey;
    NSAssert(![_map objectForKey: key], @"Caching duplicate items for '%@': %p, now %p",
             key, [_map objectForKey: key], resource);
    [_map setObject: resource forKey: key];
    if (_cache)
        [_cache setObject: resource forKey: key];
}


- (id<TDCacheable>) resourceWithCacheKey: (NSString*)docID {
    id<TDCacheable> doc = [_map objectForKey: docID];
    if (doc && _cache && ![_cache objectForKey:docID])
        [_cache setObject: doc forKey: docID];  // re-add doc to NSCache since it's recently used
    return doc;
}


- (void) forgetResource: (id<TDCacheable>)resource {
#if ! TDCACHE_IS_SMART
    TDCache* cache = resource.owningCache;
    if (cache) {
        NSAssert(cache == self, @"Removing object from the wrong cache");
        resource.owningCache = nil;
        [_map removeObjectForKey: resource.cacheKey];
    }
#else
    [_map removeObjectForKey: resource.cacheKey];
#endif
}


#if ! TDCACHE_IS_SMART
- (void) resourceBeingDealloced:(id<TDCacheable>)resource {
    [_map removeObjectForKey: resource.cacheKey];
}
#endif


- (void) unretainResources {
    [_cache removeAllObjects];
}


- (void) forgetAllResources {
    [_map removeAllObjects];
    [_cache removeAllObjects];
}


@end

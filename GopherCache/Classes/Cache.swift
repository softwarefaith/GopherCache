//
//  Cache.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/9/3.
//

import Foundation



/// Cache strategy, you can choose memory cache or disk cache
public struct CacheAccessOptions: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    public static let disk   = CacheAccessOptions(rawValue: 1 << 0)
    public static let memory = CacheAccessOptions(rawValue: 1 << 1)

    public static let `default`: CacheAccessOptions = [.disk, .memory]
}

/// Cache appearance layer, integrated memory cache and disk cache, stored objects must comply with the CacheProtocol protocol, instance method calls through the access: CacheAccessOptions method parameter selection memory cache or disk cache
public class Cache<ValueType:CacheProtocol> {
    
    let memoryCache:MemoryCache<String,ValueType>
    
    let diskCache:DiskCache<ValueType>
    
    /// diskCache or Cache name
    let name:String!
    
    /// Initialization method
    ///
    /// - Parameters:
    ///   - memoryConfig: memoryCache config
    ///   - diskConfig: diskConfig config
    public required init(memoryConfig:MemoryConfig,diskConfig:DiskConfig) {
    
        self.name = diskConfig.name
        self.memoryCache = MemoryCache(config: memoryConfig)
        self.diskCache = DiskCache(diskConfig: diskConfig)
    }
    
    /// Convenient Initialization method
    ///
    /// - Parameters:
    ///   - name: diskCache name --> DiskConfig name property
    ///   - expired: expire date
    public convenience init(name:String, expired:Expired = .never){
        let memory = MemoryConfig(expired: expired)
        let disk = DiskConfig(name: name, expired: expired)
        self.init(memoryConfig:memory,diskConfig: disk)
    }
}

extension Cache {
    ///Synchronously fetch value for key in both memory and disk caches
    public func object(forKey key: String,
                       access: CacheAccessOptions = .default) -> ValueType? {
        
        if access.contains(.memory){
            
            if let value = memoryCache.object(forKey: key) {
                  return value
            }
            CacheLog("syn key: \(key) -- not in memory")
        }
        
        if access.contains(.disk){
            if let value = diskCache.object(forKey: key) {
                return value
            }
            CacheLog("syn key: \(key) -- not in disk")
        }
        return nil
    }
     ///Synchronously check value for key in both memory and disk caches
    public func containsObejct(forKey key: String,
                               access: CacheAccessOptions = .default) -> Bool {
        
        var found = false
        if access.contains(.memory) {
            found = memoryCache.containsObejct(forKey: key)
        }
        if !found,access.contains(.disk) {
            found = diskCache.containsObejct(forKey: key)
        }
        return found
    }
     ///Synchronously set value for key in both memory and disk caches
    public func setObject(_ object: ValueType, forKey key: String,access: CacheAccessOptions = .default) {
        
        if access.contains(.memory) {
            memoryCache.setObject(object, forKey: key)
        }
        if access.contains(.disk) {
            diskCache.setObject(object, forKey: key)
        }
        
    }
    ///Synchronously remove value for key in both memory and disk caches
    public func removeObject(forKey key: String,access: CacheAccessOptions = .default) {
        
        if access.contains(.memory) {
            memoryCache.removeObject(forKey: key)
        }
        if access.contains(.disk) {
            diskCache.removeObject(forKey: key)
        }
    }
     ///Synchronously remove all value for key in both memory and disk caches
    public func removeAllObjects(access: CacheAccessOptions = .default) {
        if access.contains(.memory) {
            memoryCache.removeAllObjects()
        }
        if access.contains(.disk) {
            diskCache.removeAllObjects()
        }
    }

}

extension Cache {
    ///Asynchronously fetch value for key in both memory and disk caches,
    public func object(for key: String,completion: ((ValueType?) -> Void)?,access: CacheAccessOptions = .default) {
        
        if access.contains(.memory){
            
            if let value = memoryCache.object(forKey: key) {
               completion?(value)
            } else {
                 CacheLog("asy key: \(key) -- not in memory")
            }
        }
        
        if access.contains(.disk){
            diskCache.object(for: key, completion: completion)
        }
    }
      ///Asynchronously check value for key in both memory and disk caches,
    public func containsObejct(forKey key: String, completion: ((Bool) -> Void)?,access: CacheAccessOptions = .default) {
        
        var found = false
        if access.contains(.memory) {
            found = memoryCache.containsObejct(forKey: key)
        }
        if found {
            completion?(found)
        }
    
        if access.contains(.disk) {
            diskCache.containsObejct(forKey: key,completion: completion)
        }

    }
     ///Asynchronously set value for key in both memory and disk caches,
    public func setObject(_ object: ValueType, forKey key: String, completion: (() -> Void)?,access: CacheAccessOptions = .default) {
        
        if access.contains(.memory) {
            memoryCache.setObject(object, forKey: key)
        }
        if access.contains(.disk) {
            diskCache.setObject(object, forKey: key,completion: completion)
        }
        
    }
    ///Asynchronously remove value for key in both memory and disk caches,
    public func removeObject(forKey key: String, completion: ((String) -> Void)?,access: CacheAccessOptions = .default) {
        
        if access.contains(.memory) {
            memoryCache.removeObject(forKey: key)
        }
        if access.contains(.disk) {
            diskCache.removeObject(forKey: key,completion:completion )
        }
        
    }
     ///Asynchronously remove  all value for key in both memory and disk caches
    public func removeAllObjects(completion: (() -> Void)?,access: CacheAccessOptions = .default) {
        if access.contains(.memory) {
            memoryCache.removeAllObjects()
        }
        if access.contains(.disk) {
            diskCache.removeAllObjects(completion: completion)
        }
    }
    
    
}

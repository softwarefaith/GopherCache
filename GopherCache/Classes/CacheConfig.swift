//
//  CacheConfig.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/12.
//

import Foundation

///set the expiration date
public enum Expired {
   
    case never
    case seconds(TimeInterval)
    case date(Date)
    
    public var date: Date {
        switch self {
        case .never:
            return Date(timeIntervalSince1970: 60 * 60 * 24 * 365 * 68)
        case .seconds(let seconds):
            return Date().addingTimeInterval(seconds)
        case .date(let date):
            return date
        }
    }
    
    public var ageLimit: TimeInterval {
        switch self {
        case .never:
            return 60 * 60 * 24 * 365 * 68
        case .seconds(let seconds):
            return seconds
        case .date(let date):
            return date.timeIntervalSinceNow
        }
    }
}

/// Disk cache configuration
public class DiskConfig {
    
    //如果为nil,默认值为Caches 文件夹
    /* 代码如下：
     fileManager.url(
     for: .applicationSupportDirectory,
     in: .userDomainMask,
     appropriateFor: nil,
     create: true
     )
 */
    public let directory: URL?
    ///The name of the cache;default is nil
    public let name:String
    
    
    /// The maximum number of objects the cache should hold. defalut is Int.max
    public var countLimit:Int
    
    ///bytes
    public var constLimit:Int
    
    public let expired:Expired
    
    ///If the object's data size (in bytes) is larger than this value, then object willbe stored as a file, otherwise the object will be stored in sqlite.0 means all objects will be stored as separated files, NSUIntegerMax means allobjects will be stored in sqlite.The default value is 20480 (20KB).
    public var inlineThreshold: Int = 1024*20
    
    /// The minimum free disk space (in bytes) which the cache should kept.

    /*** @discussion The default value is 0, which means no limit.
    If the free disk space is lower than this value, the cache will remove objects
    to free some disk space. This is not a strict limit—if the free disk space goes
    over the limit, the objects could be evicted later in background queue.***/

    public var freeDiskSpaceLimit: Int = 0
    
    ///  The auto trim check time interval in seconds. Default is 60 (1 minute).
    public var autoTrimInterval: TimeInterval = 60
    
    public required init(name:String,expired:Expired,countLimit:Int,constLimit:Int ,directory: URL? = nil){
        self.name = name;
        self.countLimit = countLimit;
        self.constLimit = constLimit;
        self.expired = expired
        self.directory = directory
    }
    
    public convenience init(name:String){
        self.init(name: name, expired: .never)
    }
    
    public convenience init(name:String,expired:Expired = .never){
        self.init(name: name, expired: expired, countLimit: Int.max, constLimit: Int.max)
    }
}
/// Memory cache configuration
public class MemoryConfig {
    
    public var countLimit:Int
    
    public var constLimit:Int
    
    public var expired:Expired
    
    //The auto trim check time interval in seconds.Default is 5.0
    public  var autoTrimInterval: TimeInterval = 5.0
    
    public required init(countLimit:Int,
                constLimit:Int,
                expired:Expired){
        
        self.countLimit = countLimit;
        self.constLimit = constLimit;
        self.expired = expired
    }
    
    public convenience init(expired:Expired = .never){
        
       self.init(countLimit: Int.max, constLimit: Int.max, expired: expired)
    }
    
}



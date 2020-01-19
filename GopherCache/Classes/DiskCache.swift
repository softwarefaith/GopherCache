//
//  DiskCache.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/12.
//

import Foundation

///DiskCache  LRU arithmetic
public class DiskCache<T:DataConvertable> {
    
    public let fileManager :FileManager
    
    public let diskConfig:DiskConfig
    ///缓存路径`directory+name`
    public let path :String
    
    private let  lock: DispatchSemaphore = DispatchSemaphore(value: 1)
    
    private let  ioQueue: DispatchQueue = DispatchQueue(label: "com.GopherCache.disk.access", qos: .utility, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil)
    
    let kvs: KVStorage!
    
    var logsPrint:Bool = true
    
    public required init(diskConfig:DiskConfig,fileManager:FileManager) {
        
        self.diskConfig = diskConfig
        self.fileManager = fileManager
        
        let url: URL
        
        if let directory = diskConfig.directory {
            url = directory
        } else {
            url = try!fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        
        self.path = url.appendingPathComponent(diskConfig.name, isDirectory: true).path
        
        if(logsPrint) {
            CacheLog("diskpath:+\(self.path)")
        }
        kvs = KVStorage(path: self.path)
        
        trimRecursively()
    }
    
    public convenience init(diskConfig:DiskConfig){
        
        self.init(diskConfig: diskConfig,fileManager: FileManager.default)
    }
    
    public convenience init(cacheName:String){
        let diskConfig = DiskConfig(name: cacheName)
        self.init(diskConfig: diskConfig)
    }
    
}



//MARK: -- trim
extension DiskCache {
    private func trimRecursively() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: DispatchTime.now() + self.diskConfig.autoTrimInterval) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.trimBackground()
            strongSelf.trimRecursively()
        }
    }
    
    private func trimBackground() {
        ioQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            _ =
            strongSelf.lock.wait(timeout: .distantFuture)
            strongSelf.trimToCost(strongSelf.diskConfig.constLimit)
            strongSelf.trimToCount(strongSelf.diskConfig.countLimit)
            strongSelf.trimToAge(strongSelf.diskConfig.expired.ageLimit)
            strongSelf.trimToFreeDiskSpace(strongSelf.diskConfig.freeDiskSpaceLimit)
            strongSelf.lock.signal()
        }
    }
    
    private func trimToCount(_ count: Int) {
        if count >= Int.max { return }
        kvs.removeItemsToFitCount(count)
    }
    
    private func trimToCost(_ cost: Int) {
        if cost >= Int.max { return }
        kvs.removeItemsToFitSize(cost)
    }
    
    private func trimToAge(_ ageLimit: TimeInterval) {
        if ageLimit <= 0 {
            kvs.removeAllItems()
            return
        }
        let timestamp = TimeInterval(time(nil))
        if timestamp <= ageLimit { return }
        let age = timestamp - ageLimit;
        if (Int(age) >= Int.max) {return};
        kvs.removeItemsEarlierThanTime(Int(age))
    }
    
    private func trimToFreeDiskSpace(_ space: Int) {
        if space == 0 { return }
        let totalBytes = kvs.getItemsSize()
        if totalBytes <= 0 { return }
        let diskFreeBytes = freeSpaceInDisk()
        if diskFreeBytes < 0 { return }
        let needTrimBytes = space - diskFreeBytes
        if needTrimBytes <= 0 { return }
        var costLimit = totalBytes - needTrimBytes
        if costLimit < 0 { costLimit = 0 }
        trimToCost(costLimit)
    }
    
    private func freeSpaceInDisk() -> Int {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let space = attributes[FileAttributeKey.systemFreeSize] as! Int
            if space < 0 { return -1 }
            return space
        } catch {
            return -1
        }
    }
}


//MARK: --ICacheAsyProtocol
extension DiskCache:ICacheAsyProtocol {
    public func object(for key: String, completion: ((T?) -> Void)? = nil) {
        ioQueue.async {
            [weak  self] in
            
            guard let strongSelf = self else{
                completion?(nil)
                return
            }
            let obj = strongSelf.object(forKey: key)
            completion?(obj)
        }
    }
    
    public func containsObejct(forKey key: String, completion: ((Bool) -> Void)?) {
        ioQueue.async {
            [weak  self] in
            
            guard let strongSelf = self else{
                completion?(false)
                return
            }
            completion?(strongSelf.containsObejct(forKey: key))
        }
    }
    
    public func setObject(_ object: T, forKey key: String, completion: (() -> Void)?) {
        ioQueue.async { [weak  self] in
            
            guard let strongSelf = self else{
                completion?()
                return
            }
            strongSelf.setObject(object, forKey: key)
            completion?()
        }
    }
    
    public func removeObject(forKey key: String, completion: ((String) -> Void)?) {
        ioQueue.async {
            [weak  self] in
            guard let strongSelf = self else{
                completion?(key)
                return
            }
            strongSelf.removeObject(forKey: key)
            completion?(key)
        }
    }
    
    public func removeAllObjects(completion: (() -> Void)?) {
        ioQueue.async {
            [weak  self] in
            guard let strongSelf = self else{
                completion?()
                return
            }
            strongSelf.removeAllObjects()
            completion?()
        }
    }
    
    public func totalCount(completion: @escaping (Int) -> Void) {
        ioQueue.async { [weak self] in
            guard let strongSelf = self else { completion(-1); return }
            let cost = strongSelf.totalCount()
            completion(cost)
        }
        
    }
    
    
    public func totalCost(completion: @escaping (Int) -> Void) {
        ioQueue.async { [weak self] in
            guard let strongSelf = self else { completion(-1); return }
            let cost = strongSelf.totalCost()
            completion(cost)
        }
    }
    
}
//MARK: --ICacheSynProtocol
extension DiskCache:ICacheSynProtocol{
    public func object(forKey key: String) -> T? {
        
        _ = lock.wait(timeout: .distantFuture)
        defer {
             lock.signal()
        }
        let item = kvs.getItemForKey(key)
        
        guard let data = item?.value else {
            
            return nil
        }
        return T.convertFromData(data)
    }
    
    public func containsObejct(forKey key: String) -> Bool {
        _ = lock.wait(timeout: .distantFuture)
        
        defer {
            lock.signal()
        }
        return kvs.itemExistsForKey(key)
    }
    
    public func setObject(_ object: T, forKey key: String) {
        _ = lock.wait(timeout: .distantFuture)
        defer {
            lock.signal()
        }
        var filename: String?
        
        guard let data = T.convertToData(object) else {
            CacheLog("object convertToData error\(type(of: object))")
            return
        }
        if data.count > diskConfig.inlineThreshold {
            filename = MD5(key)
        }
        kvs.saveItem(with: key, value: data, filename: filename, extendedData: nil)
    }
    
    public func removeObject(forKey key: String) {
        _ = lock.wait(timeout: .distantFuture)
        
        defer {
            lock.signal()
        }
        kvs.removeItem(key: key)
    }
    
    public func removeAllObjects() {
        _ = lock.wait(timeout: .distantFuture)
        
        defer {
            lock.signal()
        }
         kvs.removeAllItems()
        return
    }
    
    public func totalCount() -> Int {
        
        _ = lock.wait(timeout: .distantFuture)
        defer {
            lock.signal()
        }
        let count = kvs.getItemsCount()
        return count
    }
    
    public func totalCost() -> Int {
        _ = lock.wait(timeout: .distantFuture)
        defer {
            lock.signal()
        }
        let cost = kvs.getItemsSize()
        return cost
    }
    
}


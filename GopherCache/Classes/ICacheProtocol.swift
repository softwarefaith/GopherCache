//
//  ICacheProtocol.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/12.
//

import Foundation

/*
    整体接口参照系统NSCache类型定义
 */


public protocol ICacheProtocol:ICacheSynProtocol&ICacheAsyProtocol{
     associatedtype T
}

/// 同步缓存接口
public protocol ICacheSynProtocol {
    
    associatedtype T
    
    associatedtype K:Hashable
    
    
    /// Synchronously fetch value from cache.
    ///
    /// - Parameter key: key
    /// - Returns: value
    func object(forKey key: K) -> T?
   
    ///  Synchronously check if value identified by key exists in cache.
    func containsObejct(forKey key:K)->Bool
    
    
    ///  Synchronously set value for key in Cache
    ///
    func setObject(_ object: T, forKey key:K)
    
    ///  Synchronously remove value for key in Cache
    ///
    func removeObject(forKey key: K)
    
    ///  Synchronously remove all value for key in Cache
    ///
    func removeAllObjects()
    
    ///  Synchronously fetch totalCount in Cache
    ///
    func totalCount() -> Int
    ///  Synchronously fetch totalCost in Cache
    ///
    func totalCost() -> Int

}


/// 异步缓存接口
public protocol ICacheAsyProtocol {
    
    associatedtype T
    
    associatedtype K:Hashable
    
    ///  Asynchronously fetch value from cache.
    ///
    /// - Parameters:
    ///   - key: key
    ///   - completion: Asynchronously callback
    func object(for key: K, completion: ((T?) -> Void)?)
    

    ///   Asynchronously check if value identified by key exists in cache.
    ///
    /// - Parameters:
    ///   - key: key
    ///   - completion:  Asynchronously callback result
    func containsObejct(forKey key:K,completion: ((Bool) -> Void)?)->Void
    
    ///  Asynchronously set value for key
    ///
    /// - Parameters:
    ///   - object: store value
    ///   - key: key
    ///   - completion: Asynchronously callback
    func setObject(_ object: T, forKey key:K,completion: (() -> Void)?)
    
    
    /// Asynchronously remove value for key
    ///
    /// - Parameters:
    ///   - key: key
    ///   - completion: Asynchronously callback key
    func removeObject(forKey key: K,completion: ((K) -> Void)?)
    
    /// Asynchronously remove all value in cache
    ///
    /// - Parameter completion: Asynchronously callback
    func removeAllObjects(completion: (() -> Void)?)
    
    /// Asynchronously get totalCount in Cache
    ///
    /// - Parameter completion: Asynchronously callback totalCount
    func totalCount(completion: @escaping (Int) -> Void)
    
    /// Asynchronously get totalCost in Cache
    ///
    /// - Parameter completion: Asynchronously callback totalCost
    func totalCost(completion: @escaping (Int) -> Void)
    
}

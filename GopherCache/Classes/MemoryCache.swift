//
//  MemoryCache.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/12.
//

import Foundation
#if canImport(UIKit)
import UIKit.UIApplication
#endif


///Memory cache, internal LRU algorithm implemented by bidirectional list

public final class MemoryCache<Key, Value> where Key: Hashable {

    
    public let memoryConfig:MemoryConfig
    
    private var lock: pthread_mutex_t = pthread_mutex_t()
    private let lru: LinkedMap<Key, Value> = LinkedMap()
    private let queue: DispatchQueue = DispatchQueue(label: "com.Goher.cache.memory.access")
    
    var removeAllObjectsOnMemoryWarning: Bool = true
    
    var removeAllObjectsWhenEnteringBackground: Bool = true
    
    var releaseOnMainThread: Bool {
        set {
            pthread_mutex_lock(&lock)
            lru.releaseOnMainThread = newValue
            pthread_mutex_unlock(&lock)
        }
        get {
            var  flag = false
            pthread_mutex_lock(&lock)
            flag =  lru.releaseOnMainThread
            pthread_mutex_unlock(&lock)
            return flag
        }
    }
    
    var releaseAsynchronously: Bool {
        set {
            pthread_mutex_lock(&lock)
            lru.releaseAsynchronously = newValue
            pthread_mutex_unlock(&lock)
        }
        get {
            var  flag = false
            pthread_mutex_lock(&lock)
            flag =  lru.releaseAsynchronously
            pthread_mutex_unlock(&lock)
            return flag
        }
    }
    
    private var observers: [NSObjectProtocol] = []

    
    public required init(config: MemoryConfig){
        self.memoryConfig = config
        pthread_mutex_init(&lock, nil)
        trimRecursively()
    }
    
    public convenience init(){
        
        self.init(config:MemoryConfig())
    }
    
    deinit {
        removeNotification()
        lru.removeAll()
        pthread_mutex_destroy(&lock)
    }
}

extension MemoryCache {
    
    func addNotification() {
        #if canImport(UIKit)
        let memoryWarningObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
           
            if self.removeAllObjectsOnMemoryWarning {
                self.removeAll()
            }
        }
        
        let enterBackgroundObserver = NotificationCenter.default.addObserver(forName: Notification.Name.UIApplicationDidEnterBackground, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            if self.removeAllObjectsWhenEnteringBackground {
                self.removeAll()
            }
        }
        observers.append(contentsOf: [memoryWarningObserver, enterBackgroundObserver])
        #endif
    }
    
    func removeNotification() {
        
         #if canImport(UIKit)
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
        }
        observers.removeAll()
        #endif
    }
    final func removeAll() {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
         lru.removeAll()
    }
    
}


//MARK: -- trim 系列
extension MemoryCache {
    
    private func trimRecursively() {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + memoryConfig.autoTrimInterval) { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.trimInBackground()
            strongSelf.trimRecursively()
        }
    }
    
    private func trimInBackground() {

        queue.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.trimToCost(strongSelf.memoryConfig.constLimit)
            strongSelf.trimToCount(strongSelf.memoryConfig.countLimit)

         strongSelf.trimToAge(strongSelf.memoryConfig.expired.ageLimit)

        }
    }
    
    func trimCondition(exc:()->Bool){
        
        var finish = false
        
        var holder: ContiguousArray<LinkedMap<Key, Value>.NodeRef> = []
        while !finish {
            if pthread_mutex_trylock(&lock) == 0 {
                if exc() {
                    if let nodeRef = lru.removeTail() {
                        holder.append(nodeRef)
                    }
                } else {
                    finish = true
                }
                pthread_mutex_unlock(&lock)
            } else {
                usleep(10 * 1000) //10 ms
            }
        }
        guard !holder.isEmpty else { return }
        let queue = lru.releaseOnMainThread ? DispatchQueue.main : MemoryCacheReleaseQueue
        queue.async {
            for nodeRef in holder {
                nodeRef.deinitialize(count: 1)
                nodeRef.deallocate()
            }
        }
        
    }
    
    func trimToCost(_ cost: Int) {
        
        var finish = false
        pthread_mutex_lock(&lock)
        if cost <= 0 {
            lru.removeAll()
            finish = true
        } else if lru.totalCost() <= cost {
            finish = true
        }
        pthread_mutex_unlock(&lock)
        if finish { return }
        trimCondition {
            lru.totalCost() > cost
        }
    }
    
    func trimToAge(_ age: TimeInterval){
        
        let ageLimit = memoryConfig.expired.ageLimit
        
        var finish = false
        let now = currentTime()
        pthread_mutex_lock(&lock)
        if ageLimit <= .zero {
            lru.removeAll()
            finish = true
        } else if lru.tail == nil || now - lru.tail!.pointee.time <= ageLimit {
            finish = true
        }
        pthread_mutex_unlock(&lock)
        if finish { return }
        
        trimCondition {
            lru.tail != nil && now - lru.tail!.pointee.time > ageLimit
        }
    }
    
    func trimToCount(_ count: Int){
    
        var finish = false
        pthread_mutex_lock(&lock)
        if count <= 0 {
            lru.removeAll()
            finish = true
        } else if lru.totalCount() <= count {
            finish = true
        }
        pthread_mutex_unlock(&lock)
        if finish { return }
        
        trimCondition {
            lru.totalCount() > count
        }
    }
}

extension MemoryCache {
    final subscript(_ key: Key) -> Value? {
        get {
            return object(forKey: key)
        }
        set {
            if let v = newValue{
                 setObject(v , forKey: key)
            }
        }
    }
}

//MARK: -- ICacheSynProtocol impl
extension MemoryCache:ICacheSynProtocol {
    public func totalCount() -> Int {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        let count = lru.totalCount()
        return count
    }
    
    public func totalCost() -> Int {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        let const = lru.totalCost()
        return const
    }
    
    
    public typealias T = Value
    public typealias V = Key
    
    public func object(forKey key: Key) -> Value? {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        return lru.object(forKey: key)
    }
    
    public func containsObejct(forKey key: Key) -> Bool {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        return lru.containsObejct(forKey: key)
    }
    
    public func setObject(_ object: Value, forKey key: Key) {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        lru.setObject(object, forKey: key)
        
        //判断
        let costLimit = memoryConfig.constLimit
        
        if lru.totalCost() > costLimit {
            queue.async {
                self.trimToCost(costLimit)
            }
        }
        let countLimit = memoryConfig.countLimit
        if lru.totalCount() > countLimit {
            lru.removeTail(isDealloc: true)
        }
        
    }
    
    public func removeObject(forKey key: Key) {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        lru.removeObject(forKey: key)
    }
    
    public func removeAllObjects() {
        pthread_mutex_lock(&lock)
        defer {
            pthread_mutex_unlock(&lock)
        }
        lru.removeAllObjects()
    }
    
}


//MARK: -- LinkedNode
/**
 A linked map used by MemoryCache.
 It's not thread-safe and does not validate the parameters.
 
 Typically, you should not use this class directly.
 */
private let MemoryCacheReleaseQueue: DispatchQueue = DispatchQueue(label: "com.cache.memory.release", qos: .utility)


struct LinkedNode<Key, Value>: Equatable where Key: Hashable {

    // var prev:LinkedNode
    //Value type 'LinkedNode<Key, Value>' cannot have a stored property that recursively contains it
    var prev: UnsafeMutablePointer<LinkedNode>?
    var next: UnsafeMutablePointer<LinkedNode>?
    let key: Key
    var value: Value?
    var cost: Int = 0
    var time: TimeInterval = currentTime()
    
    init(key: Key, value: Value?, cost: Int = 0) {
        self.key = key
        self.value = value
        self.cost = cost
    }
    
    static func == (lhs: LinkedNode<Key, Value>, rhs: LinkedNode<Key, Value>) -> Bool {

        return lhs.key == rhs.key
    }
}

fileprivate final class LinkedMap<Key, Value> where Key: Hashable{

    
    typealias Node = LinkedNode<Key, Value>
    typealias NodeRef = UnsafeMutablePointer<Node>
    
    var nodeRefsMap: [Key: NodeRef] = [:]
    var totalNodeCost: Int = 0
    var totalNodeCount: Int = 0
    var head: NodeRef?
    var tail: NodeRef?
    var releaseOnMainThread: Bool = false
    var releaseAsynchronously: Bool = true
}

extension LinkedMap {
    
    /// Insert a node at head and update the total cost.
    final func insert(atHead nodeRef:NodeRef) {
        nodeRefsMap[nodeRef.pointee.key] = nodeRef
        totalNodeCost += nodeRef.pointee.cost
        totalNodeCount += 1
        if head != nil {
            nodeRef.pointee.next = head
            head?.pointee.prev = nodeRef
            head = nodeRef
        } else {
            tail = nodeRef
            head = nodeRef
        }
    }
    
    /// Bring a inner node to header.
    final func bring(toHead nodeRef: NodeRef) {
        guard head != nodeRef else { return }
        
        if tail == nodeRef {
            tail = nodeRef.pointee.prev
            tail?.pointee.next = nil
        } else {
            nodeRef.pointee.next?.pointee.prev =  nodeRef.pointee.prev
            nodeRef.pointee.prev?.pointee.next =  nodeRef.pointee.next
        }
        
        nodeRef.pointee.next = head
        nodeRef.pointee.prev = nil
        head?.pointee.prev = nodeRef
        head = nodeRef
    }
    
    /// Remove a inner node and update the total cost.
    final func remove(_ nodeRef: NodeRef,isDealloc:Bool = false) {
        nodeRefsMap.removeValue(forKey: nodeRef.pointee.key)
        totalNodeCost -=  nodeRef.pointee.cost
        totalNodeCount -= 1
        
        if nodeRef.pointee.next != nil {
            nodeRef.pointee.next?.pointee.prev =  nodeRef.pointee.prev
        }
        
        if nodeRef.pointee.prev != nil {
            nodeRef.pointee.prev?.pointee.next = nodeRef.pointee.next
        }
        
        if head == nodeRef {
            head =  nodeRef.pointee.next
        }
        
        if tail == nodeRef {
            tail =  nodeRef.pointee.prev
        }
        
        if isDealloc {
            safeDeallocNodeRef(ref: nodeRef)
        }
        
    }
    
    /// Remove tail node if exist.
    // if isDealloc = ture  返回 nil
    @discardableResult
    final func removeTail(isDealloc:Bool = false) -> NodeRef? {
        guard let tmpTail = tail else { return nil }
        nodeRefsMap.removeValue(forKey: tmpTail.pointee.key)
        totalNodeCost -= tmpTail.pointee.cost
        totalNodeCount -= 1
        if head == tail {
            head = nil
            tail = nil
        } else {
            tail = tail?.pointee.prev
            tail?.pointee.next = nil
        }
        
        if isDealloc {
            safeDeallocNodeRef(ref: tmpTail)
            return nil
        }
        
        return tmpTail
    }
    
    /// Remove all node
    final func removeAll() {
        totalNodeCost = 0
        totalNodeCount = 0
        head = nil
        tail = nil
        guard !nodeRefsMap.isEmpty else { return }
        
        let holder: [Key:NodeRef] = nodeRefsMap
        nodeRefsMap = [:]
        if releaseAsynchronously {
            let queue = releaseOnMainThread ? DispatchQueue.main : MemoryCacheReleaseQueue
            queue.async {
                for nodeRef in holder.values {
                    self.deallocNodeRef(ref: nodeRef)
                }
            }
        } else if releaseOnMainThread && pthread_main_np() != .zero {
            DispatchQueue.main.async {
                // hold and release in specified queue
                for nodeRef in holder.values {
                    self.deallocNodeRef(ref: nodeRef)
                }
            }
        } else {
            // nothing
            for nodeRef in holder.values {
                self.deallocNodeRef(ref: nodeRef)
            }
        }
    }
    
    func deallocNodeRef(ref:NodeRef) {
        ref.deinitialize(count: 1)
        ref.deallocate()
    }
    
    func safeDeallocNodeRef(ref:NodeRef) {
        if releaseAsynchronously {
            let queue = releaseOnMainThread ? DispatchQueue.main : MemoryCacheReleaseQueue
            queue.async {
                self.deallocNodeRef(ref: ref)
            }
        } else if releaseOnMainThread && pthread_main_np() != 0 {
            DispatchQueue.main.async {
                self.deallocNodeRef(ref: ref)
            }
        } else {
            deallocNodeRef(ref: ref)
        }
    }
}



//MARK: ICacheSynProtocol Impl
extension LinkedMap:ICacheSynProtocol{
    
    typealias T = Value
    typealias K = Key
    
    func object(forKey key: Key) -> Value? {
        guard let nodeRef = nodeRefsMap[key] else {
            return nil
        }
        nodeRef.pointee.time = currentTime()
        bring(toHead: nodeRef)
        return nodeRef.pointee.value
    }
    
    func containsObejct(forKey key: Key) -> Bool {
        let contains = nodeRefsMap.contains { (k, _) -> Bool in
          
            return k == key
        }
        return contains
    }
    
    func setObject(_ object: Value, forKey key: Key) {
        let now = currentTime()
        
        let cost = MemoryLayout.stride(ofValue: object)
        if let nodeRef = nodeRefsMap[key] {
            //存在,更新
            totalNodeCost -= nodeRef.pointee.cost
            totalNodeCost += cost
            nodeRef.pointee.cost = cost
            nodeRef.pointee.time = now
            nodeRef.pointee.value = object
            bring(toHead: nodeRef)
        } else {
            //不存在创建
            let node = LinkedNode<Key, Value>(key: key, value: object, cost: cost)
            let nodeRef = UnsafeMutablePointer<LinkedNode<Key, Value>>.allocate(capacity: 1)
            nodeRef.initialize(to: node)
            insert(atHead: nodeRef)
        }
    
    }
    
    func removeObject(forKey key: Key) {
        if let nodeRef = nodeRefsMap[key] {
            remove(nodeRef,isDealloc: true)
        }
    }
    
    func removeAllObjects() {
        removeAll()
    }
    func totalCount() -> Int {
       return self.totalNodeCount
    }
    
    func totalCost() -> Int {
         return self.totalNodeCost
    }
}


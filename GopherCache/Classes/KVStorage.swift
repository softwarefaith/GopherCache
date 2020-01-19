//
//  KVStorage.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/20.
//

import Foundation
import SQLite3

/*
 设计思想：
  1>文件:  data>20KB    file <-> MetaFile
 
 
 
  2>SQLite
 
 
 
 */


/*
 File:
 /path/
 /manifest.sqlite
 /manifest.sqlite-shm
 /manifest.sqlite-wal
 /data/
 /e10adc3949ba59abbe56e057f20f883e
 /e10adc3949ba59abbe56e057f20f883e
 /trash/
 /unused_file_or_folder
 
 SQL:
 create table if not exists manifest (
 key                 text,
 filename            text,
 size                integer,
 inlinedata         blob,
 modification_time   integer,
 last_access_time    integer,
 extendeddata       blob,
 primary key(key),
 );
 create index if not exists last_access_time_idx on manifest(last_access_time);
 */

private let kMaxErrorRetryCount: Int = 8

private let kMinRetryTimeInterval: TimeInterval = 2

private let kMaxPathLength: Int = numericCast(PATH_MAX) - 64

private let kDBFileName: String = "manifest.sqlite"

private let kDBShmFileName: String = "manifest.sqlite-shm"

private let kDBWalFileName: String = "manifest.sqlite-wal"

private let kDataDirectoryName: String = "data"

private let kTrashDirectoryName: String = "trash"

final class KVStorageItem {
    var key: String = ""
    var size: Int = 0
    var modTime: Int = 0
    var accessTime: Int = 0
    
    var filename: String?
    var value: Data?
    var extendedData: Data?
}


///KVStorage is a multi-thread unsafe disk cache tool.
///The value is stored as a file in file system, when value beyond 20kb.
///The value is stored in sqlite with blob type, when value within 20kb.
final class KVStorage {
    
    enum StorageType {
        /** The value is stored as a file in file system. */
        case file
        /** The value is stored in sqlite with blob type. */
        case sqlite
        /** The value is stored in file system or sqlite based on your choice. */
        case mixed
     }
    
    let path: String!
    
    //MARK: -- 相关路径属性
    var dataPath:String {
       return (path as NSString).appendingPathComponent(kDataDirectoryName)
    }
    var trashPath:String {
        return (path as NSString).appendingPathComponent(kTrashDirectoryName)
    }
    var dbPath:String {
        return (path as NSString).appendingPathComponent(kDBFileName)
       
    }
    
    public let fileManager :FileManager = FileManager.default
    
    let trasnQueue : DispatchQueue = DispatchQueue(label: "com.GopherCache.disk.trash", qos: .utility)
    ///存储类型
    var type:StorageType = .mixed
    
    var logsPrint = true
    
    private var db: OpaquePointer?
    //cached stmts
    private var dbStmtCache: [String: OpaquePointer]?=nil
    private var dbLastOpenErrorTime: TimeInterval = 0
    private var dbOpenErrorCount: Int = 0
    
    /// 可失败构造器，文件夹创建失败  返回 nil
    required init?(path: String,storeType:StorageType = .mixed) {
        self.path = path;
        self.type = storeType
        //构建相关存储文件夹
        do {
            try self.createDirecroty(path: self.path)
            try self.createDirecroty(path: self.dataPath)
            try self.createDirecroty(path: self.trashPath)
        } catch  {
            
             CacheLog(error.localizedDescription)
          
            return nil
        }
        //数据库操作
        if !dbOpen() || !dbInitialize() {
            // db file may broken
            dbClose()
            reset() // rebuild
            if !dbOpen() || !dbInitialize() {
    
                CacheLog("KVStorage init error: fail to open sqlite db.")
               
            }
        }
        fileEmptyTrashInBackground()
    }
    
    private func reset() {
        do {
           
            try fileManager.removeItem(atPath: (path as NSString).appendingPathComponent(kDBFileName))
            try fileManager.removeItem(atPath: (path as NSString).appendingPathComponent(kDBShmFileName))
            try fileManager.removeItem(atPath: (path as NSString).appendingPathComponent(kDBWalFileName))
            
            fileMoveAllToTrash()
            fileEmptyTrashInBackground()
        } catch (let error) {
            if logsPrint {
                CacheLog("reset():\(error.localizedDescription)")
            }
        }
    }

    deinit {
        dbClose()
    }

}

//MARK:-- 保存
extension KVStorage {
    
    @discardableResult
    func saveItem(_ item: KVStorageItem) -> Bool {
        if item.value == nil {
              CacheLog("KVStorageItem.value can't be nil.")
            return false
        }
        return saveItem(with: item.key, value: item.value!, filename: item.filename, extendedData: item.extendedData)
    }
    
    @discardableResult
    func saveItem(with key: String, value: Data, filename: String? = nil, extendedData: Data? = nil) -> Bool {
        
        if key.isEmpty || value.isEmpty { return false }
        
        if type == .file && (filename?.count ?? 0) > 0 {
            return false
        }
        // 文件存储
        if filename != nil {
            if !fileWrite(with: key, data: value) { return false }
            if !dbSave(key: key, value: value, filename: filename, extendedData: extendedData) {
                fileDelete(with: filename!)
                return false
            }
            return true
        } else {
            
            if type != .sqlite {
                
                if let filename = dbGetFilename(with: key) {
                   fileDelete(with: filename)
                }
            }
           
        }
        //数据库存储
        return dbSave(key: key, value: value, filename: nil, extendedData: extendedData)
    }
}

//MARK:-- 获取
extension KVStorage {
    
    func getItemForKey(_ key: String) -> KVStorageItem? {
        guard !key.isEmpty else { return nil }
        guard let item = dbGetItem(key: key, excludeInlineData: false) else { return nil }
        dbUpdateAccessTime(key)
        if let fileName = item.filename {
            if let value = fileRead(with: fileName) {
                item.value = value
            } else {
                dbDeleteItem(key)
                return nil
            }
        }
        return item
    }
    
     func getItemInfoForKey(_ key: String) -> KVStorageItem? {
        guard !key.isEmpty else { return nil }
        return dbGetItem(key: key, excludeInlineData: true)
    }
    
     func getItemValueForKey(_ key: String) -> Data? {
        guard !key.isEmpty else { return nil }
        var value: Data?
        switch type {
        case .file:
            if let fileName = dbGetFilename(with: key) {
                value = fileRead(with: fileName)
                if value == nil {
                    dbDeleteItem(key)
                }
            }
        case .sqlite:
            value = dbGetValue(key: key)
        case .mixed:
            if let fileName = dbGetFilename(with: key) {
                value = fileRead(with: fileName)
                if value == nil {
                    dbDeleteItem(key)
                }
            } else {
                value = dbGetValue(key: key)
            }
        }
        if value != nil {
            dbUpdateAccessTime(key)
        }
        return value
    }
    
     func getItemForKeys(_ keys: [String]) -> [KVStorageItem]? {
        guard !keys.isEmpty else { return nil }
        if var items = dbGetItems(keys: keys, excludeInlineData: false), !items.isEmpty {
            if type == .sqlite {
                var index = 0
                var max = items.count
                repeat {
                    let item = items[index]
                    if let fileName = item.filename {
                        if let value = fileRead(with: fileName) {
                            item.value = value
                        } else {
                           
                            dbDeleteItem(item.key)
                            items.remove(at: index)
                            index -= 1
                            max -= 1
                        }
                    }
                    index += 1
                } while(index < max)
            }
            return items.isEmpty ? nil : items
        } else {
            return nil
        }
    }
    
    func getItemInfoForKeys(_ keys: [String]) -> [KVStorageItem]? {
        guard !keys.isEmpty else { return nil }
        return dbGetItems(keys: keys, excludeInlineData: true)
    }
    
     func getItemValueForKeys(_ keys: [String]) -> [String: Any]? {
        guard let items = getItemForKeys(keys) else { return nil }
        var keyAndValue = [String: Any]()
        for item in items {
            if item.key.count > 0, let value = item.value {
                keyAndValue[item.key] = value
            }
        }
        return keyAndValue.isEmpty ? nil : keyAndValue
    }
    
    func itemExistsForKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        return dbGetItemCount(key: key) > 0
    }
    
    func getItemsCount() -> Int {
        return dbGetTotalItemCount()
    }
    
    func getItemsSize() -> Int {
        return dbGetTotalItemSize()
    }
    
    
}

//MARK:-- 删除
extension KVStorage {
    
    @discardableResult
    public func removeItem(key: String) -> Bool {
        guard !key.isEmpty else { return false }
        switch type {
        case .sqlite:
            return dbDeleteItem(key)
        case .file, .mixed:
            if let fileName = dbGetFilename(with: key) {
                fileDelete(with: fileName)
            }
            return dbDeleteItem(key)
        }
    }
    @discardableResult

    public func removeItems(keys: [String]) -> Bool {
        guard !keys.isEmpty else { return false }
        switch type {
        case .sqlite:
            return dbDeleteItems(keys)
        case .file, .mixed:
            if let fileNames = dbGetFileNames(keys: keys), !fileNames.isEmpty {
                for file in fileNames {
                    fileDelete(with: file)
                }
            }
            return dbDeleteItems(keys)
        }
    }
    @discardableResult

    public func removeAllItems() -> Bool {
        guard dbClose() else {
            CacheLog("removeAllItems -- closed error")
            return false
            
        }
        reset()
        guard dbOpen() else {
              CacheLog("removeAllItems -- dbOpen error")
            return false
            
        }
        guard dbInitialize() else {
              CacheLog("removeAllItems -- dbInitialize error")
            return false
            
        }
        return true
    }
    @discardableResult

    public func removeItemsLargerThanSize(_ size: Int) -> Bool {
        guard size != Int.max else { return true }
        guard size > 0 else { return removeAllItems() }
        switch type {
        case .sqlite:
            if dbDeleteItemsWithSizeLargerThan(size) {
                dbCheckpoint()
                return true
            }
        case .file, .mixed:
            if let fileNames = dbGetFilenamesWithSizeLargerThan(size) {
                for file in fileNames {
                    fileDelete(with: file)
                }
            }
            if dbDeleteItemsWithSizeLargerThan(size) {
                dbCheckpoint()
                return true
            }
        }
        return false
    }
    @discardableResult

    public func removeItemsEarlierThanTime(_ time: Int) -> Bool {
        guard time > 0 else { return true }
        guard time != Int.max else { return removeAllItems() }
        switch type {
        case .sqlite:
            if dbDeleteItemsWithTimeEarlierThan(time) {
                dbCheckpoint()
                return true
            }
        case .file, .mixed:
            if let fileNames = dbGetFilenamesWithTimeEarlierThan(time) {
                for file in fileNames {
                    fileDelete(with: file)
                }
            }
            if dbDeleteItemsWithTimeEarlierThan(time) {
                dbCheckpoint()
                return true
            }
        }
        return false
    }
    @discardableResult

    public func removeItemsToFitSize(_ maxSize: Int) -> Bool {
        guard maxSize != Int.max else { return true }
        guard maxSize > 0 else { return removeAllItems() }
        var total = dbGetTotalItemSize()
        guard total >= 0 else { return false }
        guard total > maxSize else { return true }
        var suc = false
        dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 16)?.forEach({ (item) in
            if let fileName = item.filename {
                fileDelete(with: fileName)
            }
            suc = dbDeleteItem(item.key)
            
            total -= item.size
            if total <= maxSize || !suc {
                return
            }
        })
        if suc {
            dbCheckpoint()
        }
        return suc
    }
    @discardableResult

    public func removeItemsToFitCount(_ maxCount: Int) -> Bool {
        guard maxCount != Int.max else { return true }
        guard maxCount > 0 else { return removeAllItems() }
        var total = dbGetTotalItemCount()
        guard total >= 0 else { return false }
        guard total > maxCount else { return true }
        var suc = false
        dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 16)?.forEach({ (item) in
            if let fileName = item.filename {
                fileDelete(with: fileName)
            }
            
            suc = dbDeleteItem(item.key)
            
            total -= 1
            if total <= maxCount || !suc {
                return
            }
        })
        if suc {
            dbCheckpoint()
        }
        return suc
    }
    
    public func removeAllItemsWithProgressBlock(progress: ((_ removedCount: Int, _ totalCount: Int) -> Void)?,
                                                end: ((_ error: Bool) -> Void)?) {
        let total = dbGetTotalItemCount()
        if total <= 0 {
            end?(total < 0)
        } else {
            var left = total
            var suc = false
            dbGetItemSizeInfoOrderByTimeAscWithLimit(count: 32)?.forEach({ (item) in
                if let fileName = item.filename {
                    fileDelete(with: fileName)
                }
                suc = dbDeleteItem(item.key)
                
                left -= 1
                if left <= 0 || !suc {
                    return
                }
                progress?(total - left, total)
            })
            if suc {
                dbCheckpoint()
            }
            end?(!suc)
        }
    }

    
    
}

//MARK: -- File 操作
extension KVStorage {
    
    @discardableResult
    private func fileWrite(with filename: String, data: Data) -> Bool {
        let path = (dataPath as NSString).appending(filename)
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch (let error) {
          
            CacheLog(error.localizedDescription)
            return false
        }
    }
    
    @discardableResult
    private func fileRead(with filename: String) -> Data? {
        let path = (dataPath as NSString).appendingPathComponent(filename)
        do {
            return try Data(contentsOf: URL(fileURLWithPath: path))
        } catch (let error) {
            CacheLog(error.localizedDescription)
            return nil
        }
    }
    
    @discardableResult
    private func fileDelete(with filename: String) -> Bool {
        let path = (dataPath as NSString).appendingPathComponent(filename)
        do {
            try fileManager.removeItem(atPath: path)
            return true
        } catch (let error) {
            CacheLog(error.localizedDescription)
            return false
        }
    }
    
    @discardableResult
    private func fileMoveAllToTrash() -> Bool {
    //获得的这个CFUUID值系统并没有存储。
        //每次调用CFUUIDCreate，系统都会返回一个新的唯一标示符
//        let uuidRef = CFUUIDCreate(nil)
//        let uuid = CFUUIDCreateString(nil, uuidRef)! as String
        let uuid = UUID().uuidString
        let tmpPath = (trashPath as NSString).appendingPathComponent(uuid)
        do {
            try fileManager.moveItem(atPath: dataPath, toPath: tmpPath)
            try fileManager.createDirectory(atPath: dataPath, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch (let error) {
            CacheLog("fileMoveAllToTrash: \(error.localizedDescription)")
            return false
        }
    }

    
    private func fileEmptyTrashInBackground() {
        let trashTempPath = trashPath
        DispatchQueue.global(qos: .background).async {
            let manager = FileManager()
            do {
                let directoryContents = try manager.contentsOfDirectory(atPath: trashTempPath)
                for path in directoryContents {
                    let fullPath = (trashTempPath as NSString).appendingPathComponent(path)
                    try manager.removeItem(atPath: fullPath)
                }
            } catch (let error) {
                 CacheLog(error.localizedDescription)
            }
        }
    }
    
   
}

//MARK:-- 数据库相关操作
private extension KVStorage {
    
    ///数据库打开操作
     func dbOpen() -> Bool {
        if db != nil { return true }
        
        let result = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil)
        
        if result == SQLITE_OK {
            dbStmtCache = [:]
            dbLastOpenErrorTime = 0
            dbOpenErrorCount = 0
            //TODO: sqlite3_key 数据库加密
            return true
        } else {
            db = nil
            dbStmtCache = nil
            dbLastOpenErrorTime = currentTime()
            dbOpenErrorCount += 1
            
            CacheLog("sqlite open failed: \(result).")
            return false
        }
    }
     ///数据库关闭
    @discardableResult
    private func dbClose() -> Bool {
        if db == nil { return true }
        
        var result: Int32 = 0
        var stmtFinalized = false
        var retry = false
        
        dbStmtCache = nil // release those cached stmts
        
        repeat {
            retry = false
            if #available(iOS 8.2, *) {
                result = sqlite3_close_v2(db)
            } else {
                // Fallback on earlier versions
                result = sqlite3_close(db)
            }
            if result == SQLITE_BUSY || result == SQLITE_LOCKED { // Some stmts have not be finalized.
                CacheLog("sqlite close repeat: \(result).")
                if !stmtFinalized {
                    var stmt: OpaquePointer?
                    stmt = sqlite3_next_stmt(db, nil) // Find the stmt that has not be finalized.
                    while stmt != nil  {
                        sqlite3_finalize(stmt)
                        retry = true
                        stmt = sqlite3_next_stmt(db, nil)
                    }
                    stmtFinalized = true
                }
            } else if result != SQLITE_OK {
                CacheLog("sqlite close failed: \(result).")
                return false
            }
        } while retry
        
        db = nil
        return true
    }
    
    /// 初始化数据库 启用WAL模式：默认值为journal_mode=DELETE
    func dbInitialize() -> Bool {
        let sql = "pragma journal_mode = wal; pragma synchronous = normal; create table if not exists manifest (key text, filename text, size integer, inline_data blob, modification_time integer, last_access_time integer, extended_data blob, primary key(key)); create index if not exists last_access_time_idx on manifest(last_access_time);"
        return dbExecute(sql)
    }
    
    func dbCheckpoint() {
        guard dbCheck() else { return }
        // Cause a checkpoint to occur, merge `sqlite-wal` file to `sqlite` file.
        sqlite3_wal_checkpoint(db, nil)
    }
    
    /// sql 语句执行
    private func dbExecute(_ sql: String) -> Bool {
        if sql.isEmpty { return false }
        if !dbCheck() { return false }
        var pError: UnsafeMutablePointer<Int8>?
        let result = sqlite3_exec(db, (sql as NSString).utf8String, nil, nil, &pError)
        if pError != nil {
            let errmsg = String(cString: pError!)

            CacheLog("sqlite execute \(sql) error: \(errmsg).")
            sqlite3_free(pError)
        }
        return result == SQLITE_OK
    }
    
    private func dbCheck() -> Bool {
        if db == nil {
            if dbOpenErrorCount < kMaxErrorRetryCount && currentTime() - dbLastOpenErrorTime > kMinRetryTimeInterval {
                return dbOpen() && dbInitialize()
            } else {
                return false
            }
        }
        return true
    }
    
    
    private func dbPrepareStmt(_ sql: String) -> OpaquePointer? {
        if sql.isEmpty || dbCheck() == false {
            return nil
        }
        var stmt:OpaquePointer? = nil
        let result = sqlite3_prepare_v2(db, (sql as NSString).utf8String, -1, &stmt, nil)
        if result != SQLITE_OK {
            logDBMessage(sql)
            return nil
        }
//        var stmt = dbStmtCache?[sql]
//        if stmt != nil  {
//            sqlite3_reset(stmt)
//        } else {
//            let result = sqlite3_prepare_v2(db, (sql as NSString).utf8String, -1, &stmt, nil)
//            if result != SQLITE_OK {
//                logDBMessage(sql)
//                return nil
//            }
//            dbStmtCache?[sql] = stmt
//        }
        return stmt
    }
    
    /// - Returns: string like "?, ?, ?"
    private func dbJoinedkeys(_ keys: [Any]) -> String {
        var str = ""
        let count = keys.count
        for i in 0..<count {
            str += "?"
            if i + 1 != count {
                str += ","
            }
        }
        return str
    }
    
    private func dbBindJoinedKeys(_ keys: [String], stmt: OpaquePointer, from index: Int) {
        for i in 0..<keys.count {
             let key = keys[index] as NSString
            sqlite3_bind_text(stmt, Int32(index + i), key.utf8String, -1, nil)
        }
    }
    
    
    private func dbSave(key: String, value: Data, filename: String?, extendedData: Data?) -> Bool {
        let sql = "insert or replace into manifest (key, filename, size, inline_data, modification_time, last_access_time, extended_data) values (?1, ?2, ?3, ?4, ?5, ?6, ?7);"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        let timestamp = Int32(time(nil))
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        if let file = filename {
            sqlite3_bind_text(stmt, 2, (file as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_text(stmt, 2, nil, -1, nil)
        }
        sqlite3_bind_int(stmt, 3, Int32(value.count))
        if let _ = filename {
              sqlite3_bind_blob(stmt, 4, nil, 0, nil)
        } else {
              sqlite3_bind_blob(stmt, 4, (value as NSData).bytes, Int32(value.count), nil)
        }
        sqlite3_bind_int(stmt, 5, timestamp)
        sqlite3_bind_int(stmt, 6, timestamp)
        if let exData = extendedData {
            sqlite3_bind_blob(stmt, 7, (exData as NSData).bytes, Int32(exData.count), nil)
        } else {
            sqlite3_bind_blob(stmt, 7, nil, 0, nil)
        }
        
        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
           
            CacheLog("sqlite insert error (\(result): (\(errorDBMessage))")
            return false
        }
        return true
    }
    
    //MARK: -- === Update
    @discardableResult
    func dbUpdateAccessTime(_ key: String) -> Bool {
        let sql = "update manifest set last_access_time = ?1 where key = ?2;"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_int(stmt, 1, Int32(time(nil)))
        sqlite3_bind_text(stmt, 2, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
           
            if logsPrint {
                CacheLog("sqlite update error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        return true
    }
    
    @discardableResult
    func dbUpdateAccessTimes(_ keys: [String]) -> Bool {
        guard dbCheck() else { return false }
        let sql = "update manifest set last_access_time = \(Int32(time(nil))) where key in (\(dbJoinedkeys(keys)));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(db, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
           
            if logsPrint {
                CacheLog("sqlite stmt prepare error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        dbBindJoinedKeys(keys, stmt: stmt, from: 1)
        result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if (result != SQLITE_DONE) {
           
            if logsPrint {
                CacheLog("sqlite update error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        return true
    }
    //MARK: -- ===== GET=======
    
    func dbGetItemFromStmt(stmt: OpaquePointer, excludeInlineData: Bool) -> KVStorageItem {
        let item = KVStorageItem()
        var index: Int32 = 0
        
        if  let key = sqlite3_column_text(stmt, index) {
             item.key = String(cString:key)
        }
        index += 1
        
        if  let filename = sqlite3_column_text(stmt, index) {
            item.filename = String(cString: filename)
        }
       
        index += 1
        item.size = Int(sqlite3_column_int(stmt, index))
        index += 1
        let inlineData: UnsafeRawPointer? = excludeInlineData ? nil : sqlite3_column_blob(stmt, index)
        let inlineDataLength = excludeInlineData ? 0 : sqlite3_column_bytes(stmt, index)
        index += 1
        if inlineDataLength > 0 && (inlineData != nil) {
            item.value = NSData(bytes: inlineData, length: Int(inlineDataLength)) as Data
        }
        item.modTime = Int(sqlite3_column_int(stmt, index))
        index += 1
        item.accessTime = Int(sqlite3_column_int(stmt, index))
        index += 1
        let extendedData: UnsafeRawPointer? = sqlite3_column_blob(stmt, index)
        let extendedDataLength = sqlite3_column_bytes(stmt, index)
        if extendedDataLength > 0 && (extendedData != nil) {
            item.extendedData = NSData(bytes: extendedData, length: Int(extendedDataLength)) as Data
        }
        return item
    }
    
    func dbGetItem(key: String, excludeInlineData: Bool) -> KVStorageItem? {
        let sql = excludeInlineData ? "select key, filename, size, modification_time, last_access_time, extended_data from manifest where key = ?1;"
            : "select key, filename, size, inline_data, modification_time, last_access_time, extended_data from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        var item: KVStorageItem?
        let result = sqlite3_step(stmt)
        if (result == SQLITE_ROW) {
            item = dbGetItemFromStmt(stmt: stmt, excludeInlineData: excludeInlineData)
        } else {
            if (result != SQLITE_DONE) {
                if logsPrint {
                    CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
            }
        }
        return item
    }
    
    func dbGetItems(keys: [String], excludeInlineData: Bool) -> [KVStorageItem]? {
        guard dbCheck() else { return nil }
        let sql: String
        if (excludeInlineData) {
            sql = "select key, filename, size, modification_time, last_access_time, extended_data from manifest where key in (\(dbJoinedkeys(keys)));"
        } else {
            sql = "select key, filename, size, inline_data, modification_time, last_access_time, extended_data from manifest where key in (\(dbJoinedkeys(keys))"
        }
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(db, sql, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            
            if logsPrint {
                CacheLog("sqlite stmt prepare error (\(result): (\(errorDBMessage))")
            }
            return nil
        }
        dbBindJoinedKeys(keys, stmt: stmt, from: 1)
        var items: [KVStorageItem]? = [KVStorageItem]()
        repeat {
            result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                items?.append(dbGetItemFromStmt(stmt: stmt, excludeInlineData: excludeInlineData))
            } else if (result == SQLITE_DONE) {
                break
            } else {
               
                if logsPrint {
                    CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
                items = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return items
    }
    
      func dbGetValue(key: String) -> Data? {
        let sql = "select inline_data from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result == SQLITE_ROW) {
            let inlineData: UnsafeRawPointer? = sqlite3_column_blob(stmt, 0)
            let inlineDataLength = sqlite3_column_bytes(stmt, 0)
            guard inlineDataLength > 0 && (inlineData != nil) else {
                return nil
            }
            return NSData(bytes: inlineData, length: Int(inlineDataLength)) as Data
        } else {
            if (result != SQLITE_DONE) {
              
                if logsPrint {
                    CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
            }
            return nil
        }
    }

    
    
    private func dbGetFilename(with key: String) -> String? {
        let sql = "select filename from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            let fileName = sqlite3_column_text(stmt, 0)
            if fileName != nil {
                return String(cString: fileName!)
            }
        } else {
            if result != SQLITE_DONE {
                logDBMessage("dbGetFilename---key: \(key)")
            }
        }
        return nil
    }
    
    func dbGetFileNames(keys: [String]) -> [String]? {
        guard dbCheck() else { return nil }
        let sql = "select filename from manifest where key in (\(dbJoinedkeys(keys)));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(db, (sql as NSString).utf8String, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
           
            if logsPrint {
                CacheLog("sqlite stmt prepare error (\(result): (\(errorDBMessage))")
            }
            return nil
        }
        dbBindJoinedKeys(keys, stmt: stmt, from: 1)
        var fileNames: [String]? = [String]()
        repeat {
            result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                fileNames?.append(String(cString: UnsafePointer(sqlite3_column_text(stmt, 0))))
            } else if (result == SQLITE_DONE) {
                break
            } else {
                if  logsPrint {
                    CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
                fileNames = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return fileNames
    }
    
    func dbGetFilenames(sql: String, param: Int32) -> [String]? {
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        sqlite3_bind_int(stmt, 1, Int32(param))
        var fileNames: [String]? = [String]()
        repeat {
            let result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                fileNames?.append(String(cString: UnsafePointer(sqlite3_column_text(stmt, 0))))
            } else if (result == SQLITE_DONE) {
                break
            } else {
        
                if logsPrint {
                    CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
                fileNames = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return fileNames
    }
    
    func dbGetFilenamesWithSizeLargerThan(_ size: Int) -> [String]? {
        let sql = "select filename from manifest where size > ?1 and filename is not null;"
        return dbGetFilenames(sql: sql, param: Int32(size))
    }
    
    func dbGetFilenamesWithTimeEarlierThan(_ time: Int) -> [String]? {
        let sql = "select filename from manifest where last_access_time < ?1 and filename is not null;"
        return dbGetFilenames(sql: sql, param: Int32(time))
    }
    
     func dbGetItemSizeInfoOrderByTimeAscWithLimit(count: Int) -> [KVStorageItem]? {
        let sql = "select key, filename, size from manifest order by last_access_time asc limit ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return nil }
        var items: [KVStorageItem]? = [KVStorageItem]()
        repeat {
            let result = sqlite3_step(stmt)
            if (result == SQLITE_ROW) {
                let item = KVStorageItem()
                item.key = String(cString: UnsafePointer(sqlite3_column_text(stmt, 0)))
                item.filename = String(cString: UnsafePointer(sqlite3_column_text(stmt, 1)))
                item.size = Int(sqlite3_column_int(stmt, 2))
                items?.append(item)
            } else if (result == SQLITE_DONE) {
                break
            } else {
                
                if logsPrint{
                   CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
                }
                items = nil
                break
            }
        } while(true)
        sqlite3_finalize(stmt)
        return items
    }
    
     func dbGetItemCount(key: String) -> Int {
        let sql = "select count(key) from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return -1 }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if result != SQLITE_ROW {
            if logsPrint{
                CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
            }
           
            return -1
        }
        return Int(sqlite3_column_int(stmt, 0))
    }
    
     func dbGetInt(_ sql: String) -> Int {
        guard let stmt = dbPrepareStmt(sql) else { return -1 }
        let result = sqlite3_step(stmt)
        if result != SQLITE_ROW {
            if logsPrint{
                CacheLog("sqlite query error (\(result): (\(errorDBMessage))")
            }
            return 0
        }
        return Int(sqlite3_column_int(stmt, 0))
    }
    
    func dbGetTotalItemSize() -> Int {
        return dbGetInt("select sum(size) from manifest;")
    }
    
     func dbGetTotalItemCount() -> Int {
        return dbGetInt("select count(*) from manifest;")
    }
    
  
       //MARK: -- ===== Delete=======
    
     func dbDeleteItem(sql: String, param: Int32) -> Bool {
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_int(stmt, 1, param)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
           
            CacheLog("sqlite delete error (\(result): (\(errorDBMessage))")
            return false
        }
        return true
    }
    
     func dbDeleteItemsWithSizeLargerThan(_ size: Int) -> Bool {
        return dbDeleteItem(sql: "delete from manifest where size > ?1;", param: Int32(size))
    }
    
     func dbDeleteItemsWithTimeEarlierThan(_ time: Int) -> Bool {
        return dbDeleteItem(sql: "delete from manifest where last_access_time < ?1;", param: Int32(time))
    }
    
 
    @discardableResult
    func dbDeleteItem(_ key: String) -> Bool {
        
        guard key.count>0 else {
            CacheLog("key is empty")
            return true
        }
        
        let sql = "delete from manifest where key = ?1;"
        guard let stmt = dbPrepareStmt(sql) else { return false }
        sqlite3_bind_text(stmt, 1, (key as NSString).utf8String, -1, nil)
        let result = sqlite3_step(stmt)
        if (result != SQLITE_DONE) {
            if logsPrint {
                CacheLog("sqlite delete error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        return true
    }
    
     func dbDeleteItems(_ keys: [String]) -> Bool {
        guard dbCheck() else { return false }
        let sql = "delete from manifest where key in (\(dbJoinedkeys(keys));"
        var stmtPointer: OpaquePointer?
        var result = sqlite3_prepare_v2(db, (sql as NSString).utf8String, -1, &stmtPointer, nil)
        guard result == SQLITE_OK, let stmt = stmtPointer else {
            if logsPrint {
                CacheLog("sqlite stmt prepare error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        dbBindJoinedKeys(keys, stmt: stmt, from: 1)
        result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        if (result == SQLITE_ERROR) {
            if logsPrint {
                CacheLog("sqlite stmt prepare error (\(result): (\(errorDBMessage))")
            }
            return false
        }
        return true
    }
    
}

//MARK：－－Prvate
extension KVStorage {
    
    func createDirecroty(path:String) throws {
        
      
        //判断文件夹是否存在
        var isDir:ObjCBool = ObjCBool(booleanLiteral: false)
        guard !fileManager.fileExists(atPath: path, isDirectory: &isDir),isDir.boolValue == false else {
            
           CacheLog("fileExists + \(path)")
            
            return
        }
        //不存在就创建
        try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: nil)
         CacheLog("createDirecroty + \(path)")
    }

    fileprivate var errorDBMessage: String {
        if let errorPointer = sqlite3_errmsg(db) {
            let errorDBMessage = String(cString: errorPointer)
            return errorDBMessage
        } else {
            return "No error message"
        }
    }
    
    fileprivate func logDBMessage(_ info:String = "") {
        if logsPrint {
             CacheLog("sqlite query \(info) error: \(errorDBMessage).")
        }
    }
        
}


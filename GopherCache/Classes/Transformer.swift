//
//  Transformer.swift
//  GopherCache
//
//  Created by 蔡杰 on 2019/8/20.
//

import Foundation


/// comform protocols --> DataConvertable & Equatable

public protocol CacheProtocol : DataConvertable{

    
}

public protocol DataConvertable {
    
    /// convert obj:DataConvertable to DataConvertable
    ///
    /// - Parameter obj: model
    /// - Returns: data
    static func convertToData(_ obj:Self) -> Data?
    
    /// convert from data to obj
    ///
    /// - Parameter data: Data [in Disk Cache]
    /// - Returns: obj
    static func convertFromData(_ data:Data) -> Self?
}

extension Data: CacheProtocol {
    public static func convertToData(_ obj: Data) -> Data? {
        return obj
    }
    
    public static func convertFromData(_ data: Data) -> Data? {
        return data
    }
}

extension String: CacheProtocol {
    public static func convertToData(_ obj: String) -> Data? {
         return obj.data(using: .utf8, allowLossyConversion: false)
    }
    
    public static func convertFromData(_ data: Data) -> String? {
         return String(data: data, encoding: .utf8)
    }
}

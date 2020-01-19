//
//  CacheTests.swift
//  GopherCache_Tests
//
//  Created by 蔡杰 on 2019/9/5.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest

import Quick
import Nimble
import GopherCache

struct User {
    
    var name: String? = ""
    var uid: Int = 0
}


extension User: CacheProtocol {
    static func convertToData(_ obj: User) -> Data? {
        let json = ["identification":  obj.uid, "name": obj.name] as [String : Any]
        return try! JSONSerialization.data(withJSONObject: json)
    }
    
    static func convertFromData(_ data: Data) -> User? {
                 let dict = try! JSONSerialization.jsonObject(with: data) as! [String : Any]
        
                var user = User()
                user.uid = dict["identification"] as! Int
                user.name = dict["name"] as? String
                return user
    }
    
//    typealias Result = User
//
//    static func fromData(data: NSData) -> User.Result? {
//        let dict = try! NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as! [NSObject: AnyObject]
//
//        let user = User()
//        user.uid = dict["identification"] as! Int
//        user.name = dict["name"] as? String
//        user.badassery = Badassery(rawValue: dict["badassery"] as! String)!
//        return user
//    }
//
//    func toData() -> NSData {
//        let json = ["identification": uid, "name": name, "badassery": badassery.rawValue]
//        return try! NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions())
//    }
}


class CacheTests: QuickSpec{

    override func spec() {
        let countOfString:Int = 60
        
        let key = "StringKey"
        describe("these will fail") {
            
            it("create Cache") {
                
                let cache = Cache<String>(name:"CacheTest")
                
                for i  in 0..<countOfString {
                    let v = "StringValue+\(i)"
                    // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    cache.setObject(v, forKey: k)
                }
                
               expect(cache.containsObejct(forKey: "StringKey+30")) == true
                
               expect(cache.object(forKey: "StringKey+29")) == "StringValue+29"
                
               cache.removeObject(forKey: key+"12",access: .memory)
                
               expect(cache.containsObejct(forKey: "StringKey+12")) == true
                
               expect(cache.object(forKey: "StringKey+12")) == "StringValue+12"
                
               cache.removeObject(forKey: key+"13",access: .disk)
                
               expect(cache.containsObejct(forKey: "StringKey+13")) == true
                
               expect(cache.object(forKey: "StringKey+13",access:.memory)) == "StringValue+13"
                
              cache.removeAllObjects(access: .memory)
                
             expect(cache.containsObejct(forKey: "StringKey+2")) == true
                
                //异步添加
                for i  in 60..<80 {
                    let v = "StringValue+\(i)"
                    // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    cache.setObject(v, forKey: k, completion: {
                        
                    })
                }
            
                cache.object(for: "StringKey+70", completion: { value in
                    expect(value) == "StringValue+70"
                })
                
               
               
                expect(cache.containsObejct(forKey: "StringKey+70", access: .memory)) == true
                
                cache.containsObejct(forKey: "StringKey+65", completion: { (flag) in
                    expect(flag) == true
                })
                
                  Thread.sleep(forTimeInterval: 5)
            
                
            }

            
             it("test user"){
                let cache = Cache<User>(name:"CacheUser")
                
                var user = User()
                user.name = "Usr"
                user.uid = 123456
                
                cache.setObject(user, forKey: "user")
                
                 expect(cache.containsObejct(forKey: "user")) == true
                
                expect(cache.object(forKey: "user",access:.disk)?.name) == "Usr"
                
            }

        }
                
    }
}

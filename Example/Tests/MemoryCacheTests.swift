//
//  MemoryCacheTests.swift
//  GopherCache_Tests
//
//  Created by 蔡杰 on 2019/8/28.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
import Quick
import Nimble
import GopherCache


class MemoryCacheTests: QuickSpec {
    
    var memoryCache:MemoryCache! = MemoryCache<String,String>()
   

    override func spec() {
        
        let countOfString:UInt = 60
    
        describe("memoryCache") {
            //
            it("setObject") {
                //var const:UInt = 0
                
                self.memoryCache.memoryConfig.countLimit = 20
                
                self.memoryCache.memoryConfig.expired = .seconds(3)
                
                //添加 0 - 59 个元素
                for i  in 0..<countOfString {
                    let v = "StringValue+\(i)"
                   // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    self.memoryCache.setObject(v, forKey: k)
                }
                //暂停2s 保证异步线程删除0-39  保留40 - 59
                Thread.sleep(forTimeInterval: 1)
                
                expect(self.memoryCache.totalCount()) == 20
                
                expect(self.memoryCache.containsObejct(forKey: "StringKey+59")) == true
                
                 expect(self.memoryCache.object(forKey: "StringKey+45")) == "StringValue+45"
                
                expect(self.memoryCache.containsObejct(forKey: "StringKey+40")) == true
                
                expect(self.memoryCache.containsObejct(forKey: "StringKey39")) == false
                
                let test = self.memoryCache.object(forKey: "StringKey+38")
                expect(test == nil) == true
                //删除 40 ... 49
                for i  in 40 ..< 50 {
                    let k = "StringKey+\(i)"
                    self.memoryCache.removeObject(forKey: k)
                }
                expect(self.memoryCache.totalCount()) == 10
                
                //保证 缓存过期
                 Thread.sleep(forTimeInterval: 10)
                 expect(self.memoryCache.totalCount()) == 0
                
                self.memoryCache.removeAllObjects()
                
                expect(self.memoryCache.totalCount()) == 0
                
            }

        }
    }

}

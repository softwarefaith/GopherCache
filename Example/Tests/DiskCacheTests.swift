//
//  DiskCacheTests.swift
//  GopherCache_Tests
//
//  Created by 蔡杰 on 2019/8/20.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest

import Quick
import Nimble
import GopherCache

class DiskCacheTests: QuickSpec {

    override func spec() {
        
     let countOfString:Int = 60
        describe("these will fail") {
            
            it("create DiskCache") {
                
                let diskConfig = DiskConfig(name: "StringCache",expired: .seconds(4))
                diskConfig.autoTrimInterval = 5
                
                
                let diskCache = DiskCache<String>(diskConfig: diskConfig)
                
                //添加 0 - 59 个元素
                for i  in 0..<countOfString {
                    let v = "StringValue+\(i)"
                    // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    diskCache.setObject(v, forKey: k)
                }
               
              
                
               // expect(diskCache.totalCount()) == countOfString
                
                expect(diskCache.containsObejct(forKey: "StringKey+59")) == true
                
                expect(diskCache.object(forKey: "StringKey+59")) == "StringValue+59"
                expect(diskCache.object(forKey: "StringKey+45")) == "StringValue+45"
                
                expect(diskCache.containsObejct(forKey: "StringKey+40")) == true
                
                expect(diskCache.containsObejct(forKey: "StringKey39")) == false
                
                //删除 40 ... 49
                for i  in 40 ..< 50 {
                    let k = "StringKey+\(i)"
                    diskCache.removeObject(forKey: k)
                }
               // expect(diskCache.totalCount()) == countOfString-10
                
                //保证 缓存过期
//                Thread.sleep(forTimeInterval: 10)

                
                diskCache.removeAllObjects()
                
                for i  in 60..<countOfString+60 {
                    let v = "StringValue+\(i)"
                    // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    diskCache.setObject(v, forKey: k)
                }
                
                expect(diskCache.object(forKey: "StringKey+80")) == "StringValue+80"
                expect(diskCache.object(forKey: "StringKey+85")) == "StringValue+85"
                
               expect(diskCache.totalCount()) == countOfString
                
                diskCache.removeAllObjects()
                
                 expect(diskCache.totalCount()) == 0
                
                for i  in 120..<180{
                    let v = "StringValue+\(i)"
                    // const += UInt( MemoryLayout.stride(ofValue: type(of: v)))
                    let k = "StringKey+\(i)"
                    
                    diskCache.setObject(v, forKey: k, completion: {
                        
                    });
                }
                
               expect(diskCache.containsObejct(forKey: "StringKey+59")) == false

               diskCache.removeObject(forKey: "StringKey+129")
                
               diskCache.object(for: "StringKey+145", completion: { value in
                    expect(value) == "StringValue+145"
                })
                
                diskCache.object(for: "StringKey+170", completion: { value in
                    expect(value) == "StringValue+170"
                })
                
                diskCache.object(for: "StringKey+175", completion: { value in
                    expect(value) == "StringValue+175"
                })
               
                
                diskCache.containsObejct(forKey: "StringKey+129", completion: { (flag) in
                   
                    expect(flag) == flag
                })
                
                diskCache.containsObejct(forKey: "StringKey+128", completion: { flag in
                 
                    expect(flag) == true
                })
                
                diskCache.containsObejct(forKey: "StringKey+150", completion: {  flag in
                    
                    expect(flag) == true
                })
                
                Thread.sleep(forTimeInterval:20)
                
                diskCache.containsObejct(forKey: "StringKey+150", completion: { flag in
                    expect(flag) == false
                })
               
                waitUntil { done in
                    Thread.sleep(forTimeInterval: 0.5)
                   expect(diskCache.totalCount()) == 0
                    
                    done()
                }
            
                return 
            }
            
    
    }
    }

}

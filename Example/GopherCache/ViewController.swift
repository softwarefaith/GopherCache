//
//  ViewController.swift
//  GopherCache
//
//  Created by softwarefaith@126.com on 08/12/2019.
//  Copyright (c) 2019 softwarefaith@126.com. All rights reserved.
//

import UIKit
import SQLite3

class Temp {
    let a = 0
    let b = "123445"
    
    let a1 = 0
    let b1 = "123445"
}

struct  Temp1 {
    let a = 0
    let b = "123445"
    let a1 = 0
    let b1 = "123445"
}

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        

      let t = Temp()
    
        print(MemoryLayout.stride(ofValue: t))
        
        print(MemoryLayout.stride(ofValue: type(of: t)))
        
        let t2 = Temp1()
        print(MemoryLayout.stride(ofValue: t2))
        
        print(MemoryLayout.stride(ofValue: type(of: t2)))
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    


}


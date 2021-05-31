//
//  ViewController.swift
//  Webasyst
//
//  Created by viktkobst on 05/12/2021.
//  Copyright (c) 2021 viktkobst. All rights reserved.
//

import UIKit
import Webasyst

class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        WebasystApp().checkUserAuth { result in
            print(result)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
}


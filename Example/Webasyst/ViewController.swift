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
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func showAuth(_ sender: Any) {
        WebasystApp.authWebasyst(navigationController: self.navigationController ?? UINavigationController()) { success in
            switch success {
            case .success:
                print("Успех")
            case .error(error: _):
                print("не успех")
            }
        }
        
    }
    
}


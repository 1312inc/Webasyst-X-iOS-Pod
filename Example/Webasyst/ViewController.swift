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
    
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var imageView: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        WebasystApp.getAllUserInstall { result in
            for install in result ?? [] {
                if let image = install.image {
                    self.imageView.image = UIImage(data: image)
                    self.button.setTitle(install.name, for: .normal)
                }
            }
        }
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


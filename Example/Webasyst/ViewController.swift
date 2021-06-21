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
    
    @IBOutlet weak var authButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        WebasystApp().checkUserAuth { result in
            switch result {
            case .authorized:
                DispatchQueue.main.async {
                    self.authButton.setTitle("Вы уже авторизованы", for: .normal)
                }
            case .nonAuthorized:
                DispatchQueue.main.async {
                    self.authButton.setTitle("Авторизация", for: .normal)
                }
            case .error(message: _):
                DispatchQueue.main.async {
                    self.authButton.setTitle("Ошибка авторизации", for: .normal)
                }
                
            }
        }
        WebasystApp().getAllUserInstall { result in
            print(result)
        }
    }
    
    @IBAction func authButtonTap(_ sender: Any) {
        WebasystApp().oAuthLogin(navigationController: self.navigationController ?? UINavigationController()) { result in
            switch result {
            case .success:
                print("success")
            case .error(error: let error):
                print(error)
            }
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
}


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
    
    private var install: [UserInstall] = []
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(InstallTableViewCell.self, forCellReuseIdentifier: InstallTableViewCell.identifier)
        WebasystApp.getAllUserInstall { result in
            self.install = result ?? []
            self.tableView.reloadData()
        }
        let profile = WebasystApp.getProfileData()
        print(profile)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
}

extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return install.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: InstallTableViewCell.identifier, for: indexPath) as! InstallTableViewCell
        let install = install[indexPath.row]
        cell.configure(install)
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 120
    }
    
    
}


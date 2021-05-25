//
//  InstallTableViewCell.swift
//  Webasyst_Example
//
//  Created by Виктор Кобыхно on 25.05.2021.
//  Copyright © 2021 CocoaPods. All rights reserved.
//

import UIKit
import Webasyst

class InstallTableViewCell: UITableViewCell {

    public static var identifier = "InstallCell"
    private var ImageColor: UIImageView = {
        let image = UIImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        return image
    }()
    private var nameLabel: UILabel = {
        let label = UILabel()
        label.text = "привет"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var domainName: UILabel = {
        let label = UILabel()
        label.text = "привет"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private var urlName: UILabel = {
        let label = UILabel()
        label.text = "привет"
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }
    
    public func configure(_ install: UserInstall) {
        if let image = install.image {
            self.ImageColor.image = UIImage(data: image)
        }
        self.nameLabel.text = install.name
        self.urlName.text = install.url
        self.domainName.text = install.domain
        contentView.addSubview(ImageColor)
        contentView.addSubview(nameLabel)
        contentView.addSubview(domainName)
        contentView.addSubview(urlName)
        ImageColor.contentMode = .scaleAspectFill
        ImageColor.layer.masksToBounds = false
        ImageColor.layer.cornerRadius = 50
        ImageColor.clipsToBounds = true
        NSLayoutConstraint.activate([
            self.ImageColor.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            self.ImageColor.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            self.ImageColor.widthAnchor.constraint(equalToConstant: 100),
            self.ImageColor.heightAnchor.constraint(equalToConstant: 100),
            self.nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            self.nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 10),
            self.nameLabel.leadingAnchor.constraint(equalTo: ImageColor.trailingAnchor, constant: 10),
            self.domainName.centerYAnchor.constraint(equalTo: ImageColor.centerYAnchor),
            self.domainName.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 10),
            self.domainName.leadingAnchor.constraint(equalTo: ImageColor.trailingAnchor, constant: 10),
            self.urlName.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            self.urlName.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 10),
            self.urlName.leadingAnchor.constraint(equalTo: ImageColor.trailingAnchor, constant: 10)
        ])
    }
    
}

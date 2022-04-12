//
//  ViewController.swift
//  demo
//
//  Created by Phil Chang on 2022/4/11.
//  Copyright © 2022 Phil. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }


}

extension ViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 8
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = PlayerViewController.displayName(for: DemoType(rawValue: UInt(indexPath.row)) ?? .avPlayerNormal)
        return cell
    }
}

extension ViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let vc = PlayerViewController()
        vc.demoType = DemoType(rawValue: UInt(indexPath.row)) ?? .avPlayerNormal
        self.navigationController?.pushViewController(vc, animated: true)
    }
}

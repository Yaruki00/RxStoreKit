//
//  StoreHelper.swift
//  MangaPark
//
//  Created by Domon on 2019/05/07.
//  Copyright © 2019 Yuta Kawabe. All rights reserved.
//

import Foundation
import UIKit

/// 課金処理周りの便利アラートを表示できるExtension, UIViewControllerに実装するイメージです
public protocol StoreAlertHelperable {
    
    /// 未処理トランザクションがある旨のAlertを表示してくれます
    ///
    /// - Parameters:
    ///   - action: 未処理Actionトランザクションの実行処理のAction
    func showUnfinishedPurchasedTransactionAlert(action: @escaping () -> Void)
    
    /// 課金処理中のTransactionがあるかどうかを確認して、それぞれに合ったAlertを表示してくれます
    /// StoreKitをimportしたくなかったので引数の方がAnyになってます
    ///
    /// - Parameter vc: alertを表示するVC
    func showProcessingTransactionAlert(processingTransactionList: [Any])
    
    /// 課金処理中のTransactionがある場合のAlertを表示してくれます
    ///
    /// - Parameter vc: alertを表示するVC
    func showExistProcessingTransactionListAlert()
    
    /// 課金処理中のTransactionが無い場合のAlertを表示してくれます
    ///
    /// - Parameter vc: alertを表示するVC
    func showNoProcessingTransactionListAlert()
}

public extension StoreAlertHelperable where Self: UIViewController {
    
    func showUnfinishedPurchasedTransactionAlert(action: @escaping () -> Void) {
        let alert = UIAlertController(title: "アプリ内課金が正常に終了していません", message: "再度課金アイテムの反映処理を行います(新たに課金が発生することはありません)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in action() }))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showProcessingTransactionAlert(processingTransactionList: [Any]) {
        if processingTransactionList.isEmpty {
            self.showNoProcessingTransactionListAlert()
        } else {
            self.showExistProcessingTransactionListAlert()
        }
    }
    
    func showExistProcessingTransactionListAlert() {
        let alert = UIAlertController(title: "課金処理中のアイテムが存在します", message: "少々お待ち下さい(ファミリー共有を使用している場合は保護者からの承認をお待ち下さい)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showNoProcessingTransactionListAlert() {
        let alert = UIAlertController(title: "課金処理中のアイテムは存在しません", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}

//
//  StoreError.swift
//  Pods-RxStoreKit_Tests
//
//  Created by OkadaTomosuke on 2019/02/26.
//

import Foundation
import StoreKit

public enum StoreError: Error {
    
    // Appleサーバーから課金Itemの取得に失敗した
    case couldNotFetchProductList
    // updateTransactionにてpurchasedにならずに失敗した
    case couldNotPurchasedTransaction(SKPaymentTransactionState)
    // Receiptの更新に失敗しました
    case couldNotGetReceipt
    // Receiptの更新に失敗しました
    case couldNotRefreshReceipt
    // PurchasedではないTransactionを終了しようとしたため
    case finishNotPurchasedTransaction
    // トランザクションの復元に失敗した
    case couldNotRestoreTransaction
    // StoreKit内にあるSKErrorから作成されたError
    case skError(SKError)
}

extension StoreError {
    
    init(skError: Error) {
        guard let skError = skError as? SKError else {
            self = .skError(SKError(.unknown, userInfo: [:]))
            return
        }
        self = .skError(skError)
    }
}

extension StoreError {
    
    /// 仮で30_000系にしてます
    public var code: Int {
        switch self {
        case .couldNotFetchProductList:
            return 30_001
        case .couldNotPurchasedTransaction:
            return 30_002
        case .couldNotGetReceipt:
            return 30_003
        case .couldNotRefreshReceipt:
            return 30_004
        case .finishNotPurchasedTransaction:
            return 30_005
        case .couldNotRestoreTransaction:
            return 30_006
        case .skError(let error):
            return 31_000 + error.errorCode
        }
    }
    
    /// 仮でそれっぽい文言入れてます
    public var message: String {
        let errorCode = "\n\nerror code: \(self.code)"
        switch self {
        case .couldNotFetchProductList:
            return "課金アイテムの取得に失敗しました。ネットワークを確認して再試行してください。" + errorCode
        case .couldNotPurchasedTransaction(let state):
            return self.getTransactionStateMessage(state) + errorCode
        case .couldNotGetReceipt:
            return "課金データの取得に失敗しました。アプリを再起動して再試行してください。" + errorCode
        case .couldNotRefreshReceipt:
            return "リストアに失敗しました。ネットワークを確認して再試行してください。" + errorCode
        case .finishNotPurchasedTransaction:
            return "課金エラー。アプリを再起動して再試行してください。" + errorCode
        case .couldNotRestoreTransaction:
            return "リストアに失敗しました。ネットワークを確認して再試行してください。" + errorCode
        case .skError(let error):
            switch error.code {
            case .unknown:
                return "課金エラー。ネットワークを確認して再試行してください。" + errorCode
            case .paymentCancelled:
                return "キャンセルされたため課金処理を終了しました。" + errorCode
            case .paymentNotAllowed:
                return "設定 > 一般 > 機能制限 からApp内課金をONにしてください。" + errorCode
            default:
                return "課金エラー。エラーコードを添付の上、お問い合わせください。" + errorCode
            }
        }
    }
    
    /// TransactionStateに合わせたメッセージを返します
    /// 基本的にはエラー時なので、failed or deferred のみ想定しているメソッドです
    ///
    /// - Parameter state: SKPaymentTransactionState
    /// - Returns: メッセージ
    private func getTransactionStateMessage(_ state: SKPaymentTransactionState) -> String {
        switch state {
        case .purchased:
            // 基本ありえない
            return "課金処理が完了しましたが不具合が発生しているようです。アプリを再起動してコインが付与されているかご確認ください。"
        case .purchasing:
            // 基本ありえない
            return "Apple側で課金処理中です。しばらく経ってから再度ご確認ください。"
        case .failed:
            return "課金に失敗しました。ネットワークを確認して再試行してください。"
        case .deferred:
            return "承認待ちです。保護者からの承認をお待ち下さい。"
        case .restored:
            // 基本ありえない
            return "課金エラー。アプリを再起動して再試行してください。(.restored)"
        @unknown default:
            return "課金エラー。アプリを再起動して再試行してください。(.unknown)"
        }
    }
}

//
//  StoreDataStore.swift
//  RxStoreKit
//
//  Created by OkadaTomosuke on 2019/02/26.
//

import Foundation
import StoreKit
import RxSwift
import RxCocoa

// MARK: - StoreDataStoreProvider
final class StoreDataStoreProvider {
    
    static func provide() -> StoreDataStore {
        return StoreDataStoreImpl()
    }
}

// MARK: - StoreDataStore
protocol StoreDataStore: class {
    /// 課金アイテム情報要求結果
    var fetchProductsResult: PublishRelay<(succeeded: Bool, products: [SKProduct], invalidProductIds: [String])> { get }
    /// 購入処理結果
    var purchaseResult: PublishRelay<(succeeded: Bool, transaction: SKPaymentTransaction)> { get }
    /// レシート要求結果
    var getReceiptResult: PublishRelay<(succeeded: Bool, receipt: String)> { get }
    /// 復元処理結果
    var restoreResult: PublishRelay<(succeeded: Bool, transactions: [SKPaymentTransaction])> { get }
    /// FinishTransactionが完了したらtrueが投げられます
    var isFinishPurchasedTransactionSucceeded: PublishRelay<Bool> { get }
    
    /// Appleサーバーから課金Item一覧を取得します
    func fetchProducts(productIds: [String])
    /// 課金Itemの購入処理を実行します
    /// サブスクリプションもこのメソッドでええで
    func purchaseProduct(_ product: SKProduct)
    /// 端末内に保存されているReceiptを取得してbase64Encodedします
    func getReceipt()
    /// Restore時に使用
    /// Appleのサーバーにある最新のReceiptを端末に持ってきて保存します
    /// 定期購読の場合はサーバーでReceiptを更新するため、端末内に最新のReceiptが存在しない場合がありますので
    /// Restoreする場合は必ず呼ぶようにしてください。
    func refreshReceipt()
    /// Appleの課金は終わっているがサーバーの課金が終わっていないTransactionのListを返します
    /// transactionState == .purchasedのものだけ返します。
    func getUnfinishedPurchasedTransactionList() -> [SKPaymentTransaction]
    /// Appleで課金処理中のものだけ返します。
    /// transactionState == .purchasing, .deferredのものだけ返します
    func getProcessingTransactionList() -> [SKPaymentTransaction]
    /// 課金処理がすべて完了したらFinishします
    /// Listの中の終了していい物だけ終了します
    func finishPurchasedTransaction(_ transaction: SKPaymentTransaction)
    /// トランザクションの復元
    func restore()
}

// MARK: - StoreDataStoreImpl
final class StoreDataStoreImpl: NSObject, StoreDataStore {
    
    // MARK: - var
    var fetchProductsResult = PublishRelay<(succeeded: Bool, products: [SKProduct], invalidProductIds: [String])>()
    var purchaseResult = PublishRelay<(succeeded: Bool, transaction: SKPaymentTransaction)>()
    var getReceiptResult = PublishRelay<(succeeded: Bool, receipt: String)>()
    var restoreResult = PublishRelay<(succeeded: Bool, transactions: [SKPaymentTransaction])>()
    var isFinishPurchasedTransactionSucceeded = PublishRelay<Bool>()
    
    /// 要求完了するまで強参照しておく必要があります
    private var productsRequest: SKProductsRequest?
    /// 要求完了するまで強参照しておく必要があります
    private var receiptRequest: SKReceiptRefreshRequest?
    /// 購入時に対象のトランザクションを判別するために使用します
    private var purchasingPayment: SKPayment?
    /// 復元中のトランザクションを一時的に格納するために使用します
    private var restoringTransactions = [SKPaymentTransaction]()
    /// 復元中のトランザクションを一時的に格納するために使用します
    private var finishingTransactions = [SKPaymentTransaction]()
    
    // MARK: - init
    
    override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    // MARK: - func
    
    func fetchProducts(productIds: [String]) {
        self.productsRequest = SKProductsRequest(productIdentifiers: Set(productIds))
        self.productsRequest?.delegate = self
        self.productsRequest?.start()
    }
    
    func purchaseProduct(_ product: SKProduct) {
        let payment = SKPayment(product: product)
        self.purchasingPayment = payment
        SKPaymentQueue.default().add(payment)
    }
    
    func getReceipt() {
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
            let receiptData = try? Data(contentsOf: receiptURL) else {
                self.getReceiptResult.accept((succeeded: false, receipt: ""))
                return
        }
        let receipt = receiptData.base64EncodedString(options: .endLineWithCarriageReturn)
        self.getReceiptResult.accept((succeeded: true, receipt: receipt))
    }
    
    func refreshReceipt() {
        self.receiptRequest = SKReceiptRefreshRequest()
        self.receiptRequest?.delegate = self
        self.receiptRequest?.start()
    }
    
    func getUnfinishedPurchasedTransactionList() -> [SKPaymentTransaction] {
        return SKPaymentQueue.default().transactions.filter { transaction in
            switch transaction.transactionState {
            case .purchased:
                if transaction.original != nil {
                    // originalがnil出ない場合は定期購読の2回目以降のtransactionのため
                    // 勝手に終了させておきます。定期購読の継続に関してはサーバー側で行うはずなので
                    self.finishTransaction(transaction)
                    return false
                }
                return true
            case .purchasing, .deferred:
                return false
            case .failed, .restored:
                // 失敗(failed)したらTransactionに残していてもしょうがないので消す
                // restoredは今回のパターンでは考えないので(ありえないので)消す
                self.finishTransaction(transaction)
                return false
            @unknown default:
                fatalError("not implemented case")
            }
        }
    }
    
    func getProcessingTransactionList() -> [SKPaymentTransaction] {
        return SKPaymentQueue.default().transactions.filter { transaction in
            switch transaction.transactionState {
            case .purchased:
                return false
            case .purchasing, .deferred:
                return true
            case .failed, .restored:
                // 失敗(failed)したらTransactionに残していてもしょうがないので消す
                // restoredは今回のパターンでは考えないので(ありえないので)消す
                self.finishTransaction(transaction)
                return false
            @unknown default:
                fatalError("not implemented case")
            }
        }
    }
    
    func finishPurchasedTransaction(_ transaction: SKPaymentTransaction) {
        switch transaction.transactionState {
        case .purchased:
            self.finishTransaction(transaction)
        case .purchasing, .deferred, .failed, .restored:
            // 課金中(purchasing),延期中(deferred)(親に確認中),失敗(failed), restoredの場合は失敗扱いにする
            self.isFinishPurchasedTransactionSucceeded.accept(false)
        @unknown default:
            fatalError("not implemented case")
        }
    }
    
    func restore() {
        self.restoringTransactions = []
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    
    /// Transactionを削除した際にい自分のTransactionかどうか判断するため
    private func finishTransaction(_ transaction: SKPaymentTransaction) {
        self.finishingTransactions.append(transaction)
        SKPaymentQueue.default().finishTransaction(transaction)
    }
}

// MARK: - SKProductsRequestDelegate
extension StoreDataStoreImpl: SKProductsRequestDelegate {
    
    /// Appleサーバーから課金Item一覧が取得されたら呼ばれます
    /// ※requestDidFinish(SKRequest)も呼ばれます(たぶん)
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        self.fetchProductsResult.accept((succeeded: true, products: response.products, invalidProductIds: response.invalidProductIdentifiers))
    }
    
    /// SKRequestをstartして、処理が成功したら呼ばれます
    func requestDidFinish(_ request: SKRequest) {
        switch request {
        case is SKReceiptRefreshRequest:
            // Restore時にReceiptの更新に成功したら呼ばれます
            self.getReceipt()
        default:
            break
        }
    }
    
    /// SKRequestをstartして、処理が失敗したら呼ばれます
    func request(_ request: SKRequest, didFailWithError error: Error) {
        switch request {
        case is SKProductsRequest:
            // Appleのサーバーから課金Itemの取得に失敗したら呼ばれます
            self.fetchProductsResult.accept((succeeded: false, products: [], invalidProductIds: []))
        case is SKReceiptRefreshRequest:
            // Restore時にReceiptの更新に失敗したら呼ばれます
            self.getReceiptResult.accept((succeeded: false, receipt: ""))
        default:
            // それ以外のパターンは想定していないです。
            // なんかあります？
            break
        }
    }
}

// MARK: - SKPaymentTransactionObserver ここには他の課金Actionによる呼び出しも含まれるので注1意
extension StoreDataStoreImpl: SKPaymentTransactionObserver {
    
    /// トランザクション配列が変更されたとき（追加または状態の変更）に送信されます。 クライアントはトランザクションの状態を確認し、必要に応じて終了する必要があります。
    /// purchase処理の場合は自分の意図したpayment以外はスルーします
    /// 複数画面で同時に購入をしている場合にどちらのpaymentなのか判断できないため
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // 課金完了(purchased)の場合は成功ステータスとトランザクションを返す
                if self.purchasingPayment == transaction.payment {
                    self.purchaseResult.accept((succeeded: true, transaction: transaction))
                }
            case .restored:
                // 復元に成功したら配列に積んでおく
                // paymentQueueRestoreCompletedTransactionsFinished()が呼ばれたときにまとめて返す
                self.restoringTransactions.append(transaction)
            case .deferred:
                // 延期中(deferred)(親に確認中)の場合は一旦処理自体は終了させて、戻します
                if self.purchasingPayment == transaction.payment {
                    self.purchaseResult.accept((succeeded: false, transaction: transaction))
                }
            case .failed:
                if self.purchasingPayment == transaction.payment {
                    // 失敗(failed)したらTransactionに残していてもしょうがないので消す
                    self.finishTransaction(transaction)
                    self.purchaseResult.accept((succeeded: false, transaction: transaction))
                }
            case .purchasing:
                // 課金処理中(purchasing)の場合はそっとしておく
                continue
            @unknown default:
                assertionFailure("not implemented case")
                continue
            }
        }
    }
    
    /// トランザクションがキューから削除されたときに送信される（finishTransaction：を介して）
    func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            // finishingTransactions(自分で消そうとしたTransaction)のの場合のみ処理を行う
            if self.finishingTransactions.contains(transaction) {
                self.finishingTransactions.removeAll { $0 == transaction }
                switch transaction.transactionState {
                case .purchased:
                    self.isFinishPurchasedTransactionSucceeded.accept(true)
                case .purchasing, .deferred, .failed, .restored:
                    break
                @unknown default:
                    fatalError("not implemented case")
                }
            }
        }
    }
    
    /// SKPaymentQueue.default().restoreCompletedTransactions() したときに
    /// restoredに失敗した場合に呼ばれます
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        self.restoreResult.accept((succeeded: false, transactions: []))
        self.restoringTransactions = []
    }
    
    /// SKPaymentQueue.default().restoreCompletedTransactions() したときに
    /// restoredに成功した場合に呼ばれます
    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        self.restoreResult.accept((succeeded: true, transactions: self.restoringTransactions))
        self.restoringTransactions = []
    }
    
    /// 課金時に追加のダウンロードコンテンツをAppStore側で設定している場合に使用します
    func paymentQueue(_ queue: SKPaymentQueue, updatedDownloads downloads: [SKDownload]) {
        // NOP
    }
    
    /// AppStore側で課金Itemを表示する場合に使用します。
    /// ※この機能を使用するとアプリをインストールする前に課金させることができます
    @available(iOS 11.0, *)
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        // NOP
        return false
    }
}

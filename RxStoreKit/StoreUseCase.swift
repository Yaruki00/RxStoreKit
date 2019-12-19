//
//  StoreDataStore.swift
//  RxStoreKit
//
//  Created by OkadaTomosuke on 2019/02/26.
//

import Foundation
import RxSwift
import StoreKit

/// APIの課金アイテムのレスポンスのデータ
public protocol APIProductData {
    
    /// このproductIdentifierとSKProductのproductIdentifierが一致しているものだけ有効なデータとして返ってきます
    var productIdentifier: String { get }
}

/// StoreUseCaseProvider
public final class StoreUseCaseProvider {
    
    /// provideするよ
    ///
    /// - Returns: StoreUseCaseImplが返りますよー
    public static func provide() -> StoreUseCase {
        return StoreUseCaseImpl(
            storeDataStore: StoreDataStoreProvider.provide()
        )
    }
}

/// StoreKit周りの処理をUseCaseでラップしたもの
public protocol StoreUseCase {
    
    /// サーバーから取得したDataとAppleに登録されているDataのproductIdentifierを比較して
    /// 有効なサーバーから取得したDataとSKProductのTapleを返します
    ///
    /// - Parameter apiDataList: サーバーから取得した課金ItemのDataを想定
    /// - Returns: 有効なサーバーから取得したDataとSKProductのTaple
    func getProducts<T: APIProductData>(apiDataList: [T]) -> Single<[(apiData: T, appleData: SKProduct)]>
    
    /// 有効なサーバーから取得したDataとSKProductの配列を返します
    ///
    /// - Parameter productIds: productIdentifier
    /// - Returns: 有効なサーバーから取得したDataとSKProductのTaple
    func getProducts(productIds: [String]) -> Single<[SKProduct]>
    
    /// 引数のSKProductに対して課金処理を実行します
    ///
    /// - Parameter product: 課金対象のProduct
    /// - Returns: 処理が成功したかどうかのBool値とTransaction
    func purchase(product: SKProduct) -> Single<(SKPaymentTransaction, String)>
    
    /// 端末内に保存されているReceipt情報を取得します
    ///
    /// - Returns: Receiptをbase64encodeしたString
    func getReceipt() -> Single<String>
    
    /// 端末に保存されているReceiptを更新して取得します
    ///
    /// - Returns: 更新したReceiptをbase64encodeしたString
    func getRestoreReceipt() -> Single<String>
    
    /// 引数のTransactionがpurchasedだった場合にのみfinishさせます
    ///
    /// - Parameter transactions: finishさせたいTransaction
    /// - Returns: Completable
    func finishPurchasedTransaction(_ transaction: SKPaymentTransaction) -> Completable
    
    /// 未処理Transactionの中で.purchasedの一覧を取得
    ///
    /// - Returns: 未処理Transactionの中で.purchasedの一覧
    func getUnfinishedPurchasedTransactionList() -> [SKPaymentTransaction]
    
    /// 未処理Transactionの中で.purchasing, .deferredの一覧を取得
    ///
    /// - Returns: 未処理Transactionの中で.purchasing, .deferredの一覧
    func getProcessingTransactionList() -> [SKPaymentTransaction]
    
    /// トランザクションを復元して成功(.restored)したものを返す
    ///
    /// - Returns: 復元に成功(.restored)したトランザクションの一覧
    func restore() -> Single<[SKPaymentTransaction]>
}

private final class StoreUseCaseImpl {
    
    var storeDataStore: StoreDataStore
    
    init(storeDataStore: StoreDataStore) {
        self.storeDataStore = storeDataStore
    }
}

extension StoreUseCaseImpl: StoreUseCase {
    
    func getProducts<T: APIProductData>(apiDataList: [T]) -> Single<[(apiData: T, appleData: SKProduct)]> {
        let productIds = apiDataList.map { $0.productIdentifier }
        return Single.create { [unowned self] dataObserver in
            let disposable = self.storeDataStore.fetchProductsResult.subscribe(
                onNext: { (succeeded, products, invalidProductIds) in
                    if succeeded {
                        let tapleList: [(apiData: T, appleData: SKProduct)] = apiDataList.compactMap { apiData in
                            guard let product = products.first(where: { $0.productIdentifier == apiData.productIdentifier }) else {
                                return nil
                            }
                            // FIXME: 本当はinvalidProductIds返して使ってないIDあるよーとかしたいんですが、一旦
                            return (apiData, product)
                        }
                        dataObserver(.success(tapleList))
                    }
                    else {
                        dataObserver(.error(StoreError.couldNotFetchProductList))
                    }
            })
            self.storeDataStore.fetchProducts(productIds: productIds)
            return disposable
        }
    }
    
    func getProducts(productIds: [String]) -> Single<[SKProduct]> {
        return Single.create { [unowned self] dataObserver in
            let disposable = self.storeDataStore.fetchProductsResult.subscribe(
                onNext: { (succeeded, products, invalidProductIds) in
                    if succeeded {
                        // FIXME: 本当はinvalidProductIds返して使ってないIDあるよーとかしたいんですが、一旦
                        dataObserver(.success(products))
                    }
                    else {
                        dataObserver(.error(StoreError.couldNotFetchProductList))
                    }
            })
            self.storeDataStore.fetchProducts(productIds: productIds)
            return disposable
        }
    }
    
    func purchase(product: SKProduct) -> Single<(SKPaymentTransaction, String)> {
        return Single<(SKPaymentTransaction)>.create { [unowned self] dataObserver in
            let disposable = self.storeDataStore.purchaseResult.subscribe(
                onNext: { (succeeded, transaction) in
                    if succeeded {
                        dataObserver(.success(transaction))
                    }
                    else {
                        if let skError = transaction.error as? SKError {
                            // https://developer.apple.com/documentation/storekit/skpaymenttransaction/1411269-error
                            // failedの場合はSKErrorを伝搬
                            dataObserver(.error(StoreError.skError(skError)))
                        }
                        else {
                            dataObserver(.error(StoreError.couldNotPurchasedTransaction(transaction.transactionState)))
                        }
                    }
            })
            self.storeDataStore.purchaseProduct(product)
            return disposable
            }
            .flatMap { [unowned self] transaction in
                return Single<(SKPaymentTransaction, String)>.create { dataObserver in
                    let disposable = self.getReceipt().subscribe(
                        onSuccess: { receipt in
                            dataObserver(.success((transaction, receipt)))
                    },
                        onError: { e in
                            dataObserver(.error(e))
                    })
                    return disposable
                }
        }
    }
    
    func getReceipt() -> Single<String> {
        return Single.create { [unowned self] dataObserver in
            let disposable = self.storeDataStore.getReceiptResult.subscribe(
                onNext: { (succeeded, receipt) in
                    if succeeded {
                        dataObserver(.success(receipt))
                    }
                    else {
                        dataObserver(.error(StoreError.couldNotGetReceipt))
                    }
            })
            self.storeDataStore.getReceipt()
            return disposable
        }
    }
    
    func getRestoreReceipt() -> Single<String> {
        return Single.create { [unowned self] observer in
            let disposable = self.storeDataStore.getReceiptResult.subscribe(
                onNext: { (succeeded, receipt) in
                    if succeeded {
                        observer(.success(receipt))
                    }
                    else {
                        observer(.error(StoreError.couldNotRefreshReceipt))
                    }
            })
            self.storeDataStore.refreshReceipt()
            return disposable
        }
    }
    
    func finishPurchasedTransaction(_ transaction: SKPaymentTransaction) -> Completable {
        return Completable.create { [unowned self] observer in
            let disposable = self.storeDataStore.isFinishPurchasedTransactionSucceeded.subscribe(
                onNext: { isFinishSucceeded in
                    if isFinishSucceeded {
                        observer(.completed)
                    }
                    else {
                        observer(.error(StoreError.finishNotPurchasedTransaction))
                    }
            })
            self.storeDataStore.finishPurchasedTransaction(transaction)
            return disposable
        }
    }
    
    func getUnfinishedPurchasedTransactionList() -> [SKPaymentTransaction] {
        return self.storeDataStore.getUnfinishedPurchasedTransactionList()
    }
    
    func getProcessingTransactionList() -> [SKPaymentTransaction] {
        return self.storeDataStore.getProcessingTransactionList()
    }
    
    func restore() -> Single<[SKPaymentTransaction]> {
        return Single.create { [unowned self] observer in
            let disposable = self.storeDataStore.restoreResult.subscribe(
                onNext: { (succeeded, transactions) in
                    if succeeded {
                        observer(.success(transactions))
                    }
                    else {
                        observer(.error(StoreError.couldNotRestoreTransaction))
                    }
            })
            self.storeDataStore.restore()
            return disposable
        }
    }
}

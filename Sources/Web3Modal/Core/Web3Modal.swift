import CoinbaseWalletSDK
import Foundation
import SwiftUI
import phantom_swift

#if canImport(UIKit)
import UIKit
#endif

public let DesktopWallet_walletId = "desktopWallet"
public let MetaMask_walletId = "c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96"
public let MetaMaskSDK_walletId = MetaMask_walletId + "1"
public let Coinbase_walletId = "fd20dc426fb37566d803205b19bbc1d4096b248ac04548e3cfb6b3a38bd033aa"
public let Phantom_walletId = "a797aa35c0fadbfc1a53e7f675162ed5226968b44a19ee3d24385c64d1d3c393"

/// Web3Modal instance wrapper
///
/// ```Swift
/// let metadata = AppMetadata(
///     name: "Swift dapp",
///     description: "dapp",
///     url: "dapp.wallet.connect",
///     icons:  ["https://my_icon.com/1"]
/// )
/// Web3Modal.configure(projectId: PROJECT_ID, metadata: metadata)
/// Web3Modal.instance.getSessions()
/// ```
public class Web3Modal {
    /// Web3Modalt client instance
    public static var instance: Web3ModalClient = {
        guard let config = Web3Modal.config else {
            fatalError("Error - you must call Web3Modal.configure(_:) before accessing the shared instance.")
        }
        let client = Web3ModalClient(
            logger: ConsoleLogger(prefix: "📜", loggingLevel: .off),
            signClient: Sign.instance,
            pairingClient: Pair.instance as! (PairingClientProtocol & PairingInteracting & PairingRegisterer),
            store: .shared,
            analyticsService: .shared
        )
        
        let store = Store.shared
        
        if let session = client.getSessions().first {
            store.session = session
            store.connectedWith = .wc
            store.account = .init(from: session)
        } else if CoinbaseWalletSDK.shared.isConnected() {
            
            let storedAccount = AccountStorage.read()
            store.connectedWith = .cb
            store.account = storedAccount
        } else {
            AccountStorage.clear()
        }
        
        return client
    }()
    
    struct Config {
        static let sdkVersion: String = {
            guard
                let fileURL = Bundle.coreModule.url(forResource: "PackageConfig", withExtension: "json"),
                let data = try? Data(contentsOf: fileURL),
                let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let version = jsonObject["version"] as? String
            else {
                return "undefined"
            }
                    
            return "swift-\(version)"
        }()

        static let sdkType = "w3m"
        
        let projectId: String
        var metadata: AppMetadata
        let crypto: CryptoProvider
        var sessionParams: SessionParams
        var authRequestParams: AuthRequestParams?

        let includeWebWallets: Bool
        let recommendedWalletIds: [String]
        let excludedWalletIds: [String]
        let queryableWalletSchemes: [String]
        let customWallets: [Wallet]
        let coinbaseEnabled: Bool
        let metamaskSDKEnabled: Bool

        let onError: (Error) -> Void

    }
    
    private(set) static var config: Config!
    
    private(set) static var viewModel: Web3ModalViewModel!

    private init() {}

    /// Wallet instance wallet config method.
    /// - Parameters:
    ///   - metadata: App metadata
    public static func configure(
        projectId: String,
        metadata: AppMetadata,
        crypto: CryptoProvider,
        sessionParams: SessionParams = .default,
        authRequestParams: AuthRequestParams?,
        includeWebWallets: Bool = true,
        recommendedWalletIds: [String] = [],
        excludedWalletIds: [String] = [],
        queryableWalletSchemes: [String] = [],
        customWallets: [Wallet] = [],
        coinbaseEnabled: Bool = true,
        metamaskSDKEnabled: Bool = true,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        Pair.configure(metadata: metadata)
        
        Web3Modal.config = Web3Modal.Config(
            projectId: projectId,
            metadata: metadata,
            crypto: crypto,
            sessionParams: sessionParams,
            authRequestParams: authRequestParams,
            includeWebWallets: includeWebWallets,
            recommendedWalletIds: recommendedWalletIds,
            excludedWalletIds: excludedWalletIds,
            queryableWalletSchemes: queryableWalletSchemes,
            customWallets: customWallets,
            coinbaseEnabled: coinbaseEnabled,
            metamaskSDKEnabled: metamaskSDKEnabled,
            onError: onError
        )

        Sign.configure(crypto: crypto)

        let store = Store.shared
        let router = Router()
        let w3mApiInteractor = W3MAPIInteractor(store: store)
        let signInteractor = SignInteractor(store: store)
        let blockchainApiInteractor = BlockchainAPIInteractor(store: store)
        
        store.queryableWalletSchemes = queryableWalletSchemes
        store.customWallets = customWallets
        
        if metamaskSDKEnabled {
            configureMetaMaskIfNeeded(
                store: store,
                metadata: metadata,
                w3mApiInteractor: w3mApiInteractor
            )
        }
        
        if coinbaseEnabled {
            configureCoinbaseIfNeeded(
                store: store,
                metadata: metadata,
                w3mApiInteractor: w3mApiInteractor
            )
        }

        if sessionParams.optionalNamespaces?.keys.contains("solana") ?? false {
            configurePhantomIfNeeded(
                store: store,
                metadata: metadata,
                sessionParams: sessionParams,
                w3mApiInteractor: w3mApiInteractor
            )
        }
        
        Web3Modal.viewModel = Web3ModalViewModel(
            router: router,
            store: store,
            w3mApiInteractor: w3mApiInteractor,
            signInteractor: signInteractor,
            blockchainApiInteractor: blockchainApiInteractor,
            supportsAuthenticatedSession: (config.authRequestParams != nil)
        )
        
        Task {
            try? await w3mApiInteractor.fetchWalletImages(for: store.recentWallets + store.customWallets)
            try? await w3mApiInteractor.fetchAllWalletMetadata()
            try? await w3mApiInteractor.fetchFeaturedWallets()
            try? await w3mApiInteractor.fetchAllWalletsFirstPage()
            try? await w3mApiInteractor.prefetchChainImages()
        }
    }
    
    public static func set(sessionParams: SessionParams) {
        Web3Modal.config.sessionParams = sessionParams
    }
    
    public static func set(authRequestParams: AuthRequestParams?) {
        Web3Modal.config.authRequestParams = authRequestParams
    }
    
    private static func configureCoinbaseIfNeeded(
        store: Store,
        metadata: AppMetadata,
        w3mApiInteractor: W3MAPIInteractor
    ) {
        guard Web3Modal.config.coinbaseEnabled else { return }
        
        if let redirectLink = metadata.redirect?.universal ?? metadata.redirect?.native {
            CoinbaseWalletSDK.configure(callback: URL(string: redirectLink)!)
        } else {
            CoinbaseWalletSDK.configure(
                callback: URL(string: "w3mdapp://")!
            )
        }
            
        var wallet: Wallet = .init(
            id: Coinbase_walletId,
            name: "Coinbase",
            homepage: "https://www.coinbase.com/wallet/",
            imageId: "a5ebc364-8f91-4200-fcc6-be81310a0000",
            order: 4,
            mobileLink: nil,
            linkMode: nil,
            desktopLink: nil,
            webappLink: nil,
            appStore: "https://apps.apple.com/us/app/coinbase-wallet-nfts-crypto/id1278383455",
            alternativeConnectionMethod: {
                CoinbaseWalletSDK.shared.initiateHandshake { result, account in
                    switch result {
                        case .success:
                            guard
                                let account = account,
                                let blockchain = Blockchain(
                                    namespace: account.chain == "eth" ? "eip155" : "",
                                    reference: String(account.networkId)
                                )
                            else { return }
                        
                            store.connectedWith = .cb
                            store.account = .init(
                                address: account.address,
                                chain: blockchain
                            )
                        
                            withAnimation {
                                store.isModalShown = false
                            }
                            Web3Modal.viewModel.router.setRoute(Router.AccountSubpage.profile)
                            
                            let matchingChain = ChainPresets.allChains.first(where: {
                                $0.chainNamespace == blockchain.namespace && $0.chainReference == blockchain.reference
                            })
                        
                            store.selectedChain = matchingChain
                        
                            instance.coinbaseConnectedSubject.send()
                        
                        case .failure(let error):
                            store.toast = .init(style: .error, message: error.localizedDescription)
                    }
                }
            }
        )
            
        wallet.isInstalled = CoinbaseWalletSDK.isCoinbaseWalletInstalled()
            
        store.customWallets.append(wallet)
            
        Task { [wallet] in
            try? await w3mApiInteractor.fetchWalletImages(for: [wallet])
        }
    }
    
    private static func configurePhantomIfNeeded(
        store: Store,
        metadata: AppMetadata,
        sessionParams: SessionParams,
        w3mApiInteractor: W3MAPIInteractor
    ) {
        guard let redirectLink = metadata.redirect?.universal ?? metadata.redirect?.native
        else { return }

        let wallet: Wallet = .init(
            id: Phantom_walletId,
            name: "Phantom",
            homepage: "https://phantom.app/",
            imageId: "c38443bb-b3c1-4697-e569-408de3fcc100",
            order: 1,
            mobileLink: nil,
            linkMode: nil,
            desktopLink: nil,
            webappLink: nil,
            appStore: "https://apps.apple.com/app/phantom-solana-wallet/1598432977",
            isInstalled: PhantomClient.isInstalled(),
            alternativeConnectionMethod: {
                let cluster: SolanaCluster = .mainnetBeta
                let phantom = PhantomClient(config: .init(
                    appUrl: metadata.url,
                    cluster: cluster,
                    redirectUrl: redirectLink
                ))
                PhantomClient.shared = phantom
                
                Task { @MainActor in
                    do {
                        let session = try await phantom.connectWallet()
                        let blockchain = Blockchain(cluster.chainId)!
                        
                        store.connectedWith = .phantom
                        store.account = .init(
                            address: session.walletAddress,
                            chain: blockchain
                        )
                        
                        withAnimation {
                            store.isModalShown = false
                        }
                        Web3Modal.viewModel.router.setRoute(Router.AccountSubpage.profile)
                        
                        let matchingChain = ChainPresets.solChains.first(where: {
                            $0.chainNamespace == blockchain.namespace && $0.chainReference == blockchain.reference
                        })
                    
                        store.selectedChain = matchingChain
                    
                        instance.phantomConnectedSubject.send()
                    } catch {
                        store.toast = .init(style: .error, message: error.localizedDescription)
                    }
                }
            }
        )
                        
        store.customWallets.append(wallet)
            
        Task { [wallet] in
            try? await w3mApiInteractor.fetchWalletImages(for: [wallet])
        }
    }
}

#if canImport(UIKit)

public extension Web3Modal {
    static func selectChain(from presentingViewController: UIViewController? = nil) {
        guard let vc = presentingViewController ?? topViewController() else {
            assertionFailure("No controller found for presenting modal")
            return
        }
        
        _ = Web3Modal.instance
        
        Web3Modal.viewModel.router.setRoute(Router.NetworkSwitchSubpage.selectChain)
        
        Store.shared.connecting = true
        
        let modal = Web3ModalSheetController(router: Web3Modal.viewModel.router)
        vc.present(modal, animated: true)
    }
    
    static func present(from presentingViewController: UIViewController? = nil) {
        guard let vc = presentingViewController ?? topViewController() else {
            assertionFailure("No controller found for presenting modal")
            return
        }
        
        _ = Web3Modal.instance
        
        Store.shared.connecting = true
        
        Web3Modal.viewModel.router.setRoute(Store.shared.account != nil ? Router.AccountSubpage.profile : Router.ConnectingSubpage.connectWallet)
        
        let modal = Web3ModalSheetController(router: Web3Modal.viewModel.router)
        vc.present(modal, animated: true)
    }
    
    private static func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication
            .shared
            .connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .last { $0.isKeyWindow }?
            .rootViewController
        
        if let nav = base as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return topViewController(selected)
            }
        }
        
        if let presented = base?.presentedViewController {
            return topViewController(presented)
        }
        
        return base
    }
}

#elseif canImport(AppKit)

import AppKit

public extension Web3Modal {
    static func present(from presentingViewController: NSViewController? = nil) {
        let modal = Web3ModalSheetController()
        presentingViewController!.presentAsModalWindow(modal)
    }
}

#endif

public struct SessionParams {
    public let requiredNamespaces: [String: ProposalNamespace]
    public let optionalNamespaces: [String: ProposalNamespace]?
    public let sessionProperties: [String: String]?
    
    public init(requiredNamespaces: [String: ProposalNamespace], optionalNamespaces: [String: ProposalNamespace]? = nil, sessionProperties: [String: String]? = nil) {
        self.requiredNamespaces = requiredNamespaces
        self.optionalNamespaces = optionalNamespaces
        self.sessionProperties = sessionProperties
    }
    
    public static let `default`: Self = {
        let methods: Set<String> = Set(EthUtils.ethMethods)
        let events: Set<String> = ["chainChanged", "accountsChanged"]
        let ethBlockchains = ChainPresets.ethChains.map(\.id).compactMap(Blockchain.init)

        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: ethBlockchains,
                methods: methods,
                events: events
            )
        ]
        
        let solBlockchains = ChainPresets.solChains.map(\.id).compactMap(Blockchain.init)
        let optionalNamespaces: [String: ProposalNamespace] = [
            "solana": ProposalNamespace(
                chains: solBlockchains,
                methods: [
                    "solana_signMessage",
                    "solana_signTransaction"
                ], events: []
            )
        ]
       
        return SessionParams(
            requiredNamespaces: [:],
            optionalNamespaces: namespaces.merging(optionalNamespaces, uniquingKeysWith: { old, _ in old }),
            sessionProperties: nil
        )
    }()
}

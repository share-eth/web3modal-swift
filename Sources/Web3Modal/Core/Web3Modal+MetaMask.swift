//
//  Web3Modal+MetaMask.swift
//  swift-web3modal
//
//  Created by Daniel Hallman on 10/2/24.
//

import metamask_ios_sdk
import struct metamask_ios_sdk.AppMetadata
import struct WalletConnectPairing.AppMetadata
import Foundation
import UIKit
import SwiftUI

extension Web3Modal {
    
    internal static func configureMetaMaskIfNeeded(
        store: Store,
        metadata: WalletConnectPairing.AppMetadata,
        w3mApiInteractor: W3MAPIInteractor
    ) {        
        let dappScheme = metadata.redirect?.native?.replacingOccurrences(of: "://", with: "") ?? ""
        let sharedInstance = MetaMaskSDK.shared(
            .init(
                name: metadata.name,
                url: metadata.url,
                iconUrl: metadata.icons.first ?? ""
            ),
            transport: .deeplinking(dappScheme: dappScheme),
            enableDebug: true,
            sdkOptions: nil
        )
        
        // Disconnect in case there is an existing connection
        sharedInstance.disconnect()
        
        var wallet: Wallet = .init(
            id: MetaMaskSDK_walletId,
            name: "MetaMask SDK",
            homepage: "",
            imageId: "018b2d52-10e9-4158-1fde-a5d5bac5aa00",
            order: 3,
            mobileLink: nil,
            linkMode: nil,
            desktopLink: nil,
            webappLink: nil,
            appStore: "https://apps.apple.com/us/app/metamask-blockchain-wallet/id1438144202",
            alternativeConnectionMethod: {
                Task { @MainActor in
                    let result = await sharedInstance.connect()
                    switch result {
                    case .success(let accounts):
                        let address = sharedInstance.account
                        let chainId = sharedInstance.chainId.hasPrefix("0x") ? String(sharedInstance.chainId.dropFirst(2)) : sharedInstance.chainId
                        guard let blockchain = Blockchain(namespace: "eip155", reference: chainId ) else {
                            Task { @MainActor in
                                store.toast = .init(style: .error, message: "Connection failed")
                            }
                            return
                        }
                        
                        store.connectedWith = .metamask
                        store.account = .init(address: address, chain: blockchain)
                        
                        withAnimation {
                            store.isModalShown = false
                        }
                        Web3Modal.viewModel.router.setRoute(Router.AccountSubpage.profile)
                        
                        let matchingChain = ChainPresets.allChains.first(where: {
                            $0.chainNamespace == blockchain.namespace && $0.chainReference == blockchain.reference
                        })
                        
                        store.selectedChain = matchingChain
                        instance.metamaskConnectedSubject.send()
                        
                    case .failure(let error):
                        Task { @MainActor in
                            store.toast = .init(style: .error, message: error.localizedDescription)
                            Web3Modal.config.onError(error)
                        }
                        return
                    }
                }
            }
        )
        
        wallet.isInstalled = sharedInstance.isMetaMaskInstalled
        
        store.customWallets.append(wallet)
        
        Task { [wallet] in
            try? await w3mApiInteractor.fetchWalletImages(for: [wallet])
        }
    }
}

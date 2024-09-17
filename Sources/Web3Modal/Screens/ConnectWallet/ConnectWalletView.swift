import SwiftUI

struct ConnectWalletView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    @Environment(\.analyticsService) var analyticsService: AnalyticsService
    
    @EnvironmentObject var signInteractor: SignInteractor

    let displayWCConnection = false
    
    var wallets: [Wallet] {
        var recentWallets = store.recentWallets
        
        let result = (store.featuredWallets + store.customWallets).map { featuredWallet in
            var featuredWallet = featuredWallet
            let (index, matchingRecentWallet) = recentWallets.enumerated().first { (index, recentWallet) in
                featuredWallet.id == recentWallet.id
            } ?? (nil, nil)
            
            
            if let match = matchingRecentWallet, let matchingIndex = index  {
                featuredWallet.lastTimeUsed = match.lastTimeUsed
                recentWallets.remove(at: matchingIndex)
            }
            
            return featuredWallet
        }
        
        let recommended = Web3Modal.config.recommendedWalletIds
        let installed = store.installedWalletIds
        let distantPast = Date.distantPast
        
        return Array(unsortedWallets
            .sorted(by: { $0.order < $1.order } )
            .sorted(by: {
                if installed.contains($0.id) && installed.contains($1.id) {
                    return installed.firstIndex(of: $0.id)! < installed.firstIndex(of: $1.id)!
                } else {
                    return installed.contains($0.id) && !installed.contains($1.id)
                }
            } )
            .sorted(by: {
                if recommended.contains($0.id) && recommended.contains($1.id) {
                    return recommended.firstIndex(of: $0.id)! < recommended.firstIndex(of: $1.id)!
                } else {
                    return recommended.contains($0.id) && !recommended.contains($1.id)
                }
            } )
            .sorted(by: { $0.lastTimeUsed ?? distantPast > $1.lastTimeUsed ?? distantPast } )
            .sorted(by: { $0.id == "desktopWallet" && $1.id != "desktopWallet" } )
            .prefix(5)
        )
    }
    
    var body: some View {
        VStack {
            wcConnection()
            
            featuredWallets()
                
            Button(action: {
                router.setRoute(Router.ConnectingSubpage.allWallets)
                analyticsService.track(.CLICK_ALL_WALLETS)
            }, label: {
                Text("All wallets")
            })
            .buttonStyle(W3MListSelectStyle(
                imageContent: { _ in
                    Image.optionAll
                },
                tag: store.totalNumberOfWallets != 0 ? W3MTag(title: "\(store.totalNumberOfWallets)+", variant: .info) : nil
            ))
        }
        .padding(Spacing.s)
        .padding(.bottom)
    }
    
    @ViewBuilder
    private func featuredWallets() -> some View {
        ForEach(wallets, id: \.self) { wallet in
            Group {
                let isRecent: Bool = wallet.lastTimeUsed != nil
                let isInstalled: Bool = wallet.isInstalled
                let tagTitle: String? = isRecent ? "RECENT" : isInstalled ? "INSTALLED" : nil
                
                Button(action: {
                    Web3Modal.instance.didSelectWalletSubject.send(wallet)
                    if wallet.customDidSelect {
                        store.isModalShown = false
                        return
                    }
                    Task {
                        do {
                            try await signInteractor.connect(walletUniversalLink: wallet.linkMode)
                            router.setRoute(Router.ConnectingSubpage.walletDetail(wallet))
                            analyticsService.track(.SELECT_WALLET(name: wallet.name, platform: .mobile))
                        } catch {
                            store.toast = .init(style: .error, message: error.localizedDescription)
                        }
                    }
                }, label: {
                    Text(wallet.name)
                })
                .buttonStyle(W3MListSelectStyle(
                    imageContent: { _ in
                        Group {
                            if let storedImage = store.walletImages[wallet.id] {
                                Image(uiImage: storedImage)
                                    .resizable()
                            } else {
                                Image.Regular.wallet
                                    .resizable()
                                    .padding(Spacing.xxs)
                            }
                        }
                        .background(Color.Overgray005)
                        .backport.overlay {
                            RoundedRectangle(cornerRadius: Radius.xxxs)
                                .stroke(.Overgray010, lineWidth: 1)
                        }
                    },
                    tag: tagTitle != nil ? .init(title: tagTitle!, variant: .info) : nil
                ))
            }
        }
    }
    
    @ViewBuilder
    private func wcConnection() -> some View {
        if displayWCConnection {
            Button(action: {
                router.setRoute(Router.ConnectingSubpage.qr)
            }, label: {
                Text("WalletConnect")
            })
            .buttonStyle(W3MListSelectStyle(
                imageContent: { _ in
                    ZStack {
                        Color.Blue100
                        
                        Image.imageLogo
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(.white)
                    }
                },
                tag: W3MTag(title: "QR CODE", variant: .main)
            ))
        }
    }
}

struct ConnectWalletView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectWalletView()
    }
}

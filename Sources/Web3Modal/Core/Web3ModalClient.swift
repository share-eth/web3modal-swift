import class CoinbaseWalletSDK.CoinbaseWalletSDK
import struct CoinbaseWalletSDK.Action
import struct CoinbaseWalletSDK.ActionError
import Combine
import Foundation
import UIKit
import phantom_swift
import metamask_ios_sdk

// Web3 Modal Client
///
/// Cannot be instantiated outside of the SDK
///
/// Access via `Web3Modal.instance`
public class Web3ModalClient {
    // MARK: - Public Properties
    
    /// Publisher that sends sessions on every sessions update
    ///
    /// Event will be emited on controller and non-controller clients.
    public var sessionsPublisher: AnyPublisher<[Session], Never> {
        signClient.sessionsPublisher.eraseToAnyPublisher()
    }
    
    /// Publisher that sends session when one is settled
    ///
    /// Event is emited on proposer and responder client when both communicating peers have successfully established a session.
    public var sessionSettlePublisher: AnyPublisher<Session, Never> {
        signClient.sessionSettlePublisher.eraseToAnyPublisher()
    }
    
    /// Publisher that sends session proposal that has been rejected
    ///
    /// Event will be emited on dApp client only.
    public var sessionRejectionPublisher: AnyPublisher<(Session.Proposal, Reason), Never> {
        signClient.sessionRejectionPublisher.eraseToAnyPublisher()
    }
    
    /// Publisher that sends deleted session topic
    ///
    /// Event can be emited on any type of the client.
    public var sessionDeletePublisher: AnyPublisher<(String, Reason), Never> {
        signClient.sessionDeletePublisher.eraseToAnyPublisher()
    }
    
    /// Publisher that sends response for session request
    ///
    /// In most cases that event will be emited on dApp client.
    public var sessionResponsePublisher: AnyPublisher<W3MResponse, Never> {
        signClient.sessionResponsePublisher
            .map { response in
                W3MResponse(
                    id: response.id,
                    topic: response.topic,
                    chainId: response.chainId,
                    result: response.result
                )
            }
            .merge(with: coinbaseResponseSubject)
            .merge(with: phantomResponseSubject)
            .merge(with: metamaskResponseSubject)
            .eraseToAnyPublisher()
    }
    
    public var coinbaseResponseSubject = PassthroughSubject<W3MResponse, Never>()
    public var coinbaseConnectedSubject = PassthroughSubject<Void, Never>()
    
    public var phantomResponseSubject = PassthroughSubject<W3MResponse, Never>()
    public var phantomConnectedSubject = PassthroughSubject<Void, Never>()
    
    public var metamaskResponseSubject = PassthroughSubject<W3MResponse, Never>()
    public var metamaskConnectedSubject = PassthroughSubject<Void, Never>()
    
    public var didSelectWalletSubject = PassthroughSubject<Wallet, Never>()
    
    /// Publisher that sends web socket connection status
    public var socketConnectionStatusPublisher: AnyPublisher<SocketConnectionStatus, Never> {
        signClient.socketConnectionStatusPublisher.eraseToAnyPublisher()
    }
    
    /// Publisher that sends session event
    ///
    /// Event will be emited on dApp client only
    public var sessionEventPublisher: AnyPublisher<(event: Session.Event, sessionTopic: String, chainId: Blockchain?), Never> {
        signClient.sessionEventPublisher.eraseToAnyPublisher()
    }

    public var authResponsePublisher: AnyPublisher<(id: RPCID, result: Result<(Session?, [Cacao]), AuthError>), Never> {
        signClient.authResponsePublisher
    }

    public var isAnalyticsEnabled: Bool {
        return analyticsService.isAnalyticsEnabled
    }

    public var SIWEAuthenticationPublisher: AnyPublisher<Result<(message: String, signature: String), SIWEAuthenticationError>, Never> {
        return SIWEAuthenticationPublisherSubject.eraseToAnyPublisher()
    }

    internal let SIWEAuthenticationPublisherSubject = PassthroughSubject<Result<(message: String, signature: String), SIWEAuthenticationError>, Never>()

    // MARK: - Private Properties

    private let signClient: SignClient
    private let pairingClient: PairingClientProtocol & PairingInteracting & PairingRegisterer
    private let store: Store
    private let analyticsService: AnalyticsService
    private var disposeBag = Set<AnyCancellable>()
    public let logger: ConsoleLogging

    init(
        logger: ConsoleLogging,
        signClient: SignClient,
        pairingClient: PairingClientProtocol & PairingInteracting & PairingRegisterer,
        store: Store,
        analyticsService: AnalyticsService
    ) {
        self.logger = logger
        self.signClient = signClient
        self.pairingClient = pairingClient
        self.store = store
        self.analyticsService = analyticsService
        setUpConnectionEvents()
        analyticsService.track(.MODAL_LOADED)
    }
    
    /// For creating new pairing
    public func createPairing() async throws -> WalletConnectURI {
        logger.debug("Creating new pairing")
        do {
            return try await pairingClient.create()
        } catch {
            Web3Modal.config.onError(error)
            throw error
        }
    }
    
    /// For proposing a session to a wallet.
    /// Function will propose a session on existing pairing or create new one if not specified
    /// Namespaces from Web3Modal.config will be used
    /// - Parameters:
    ///   - topic: pairing topic
    public func connect(walletUniversalLink: String?) async throws -> WalletConnectURI? {
        logger.debug("Connecting Application")
        do {
            if let authParams = Web3Modal.config.authRequestParams {
                return try await signClient.authenticate(authParams, walletUniversalLink: walletUniversalLink)
            } else {
                return try await signClient.connect(
                    requiredNamespaces: Web3Modal.config.sessionParams.requiredNamespaces,
                    optionalNamespaces: Web3Modal.config.sessionParams.optionalNamespaces,
                    sessionProperties: Web3Modal.config.sessionParams.sessionProperties
                )
            }
        } catch {
            // Ignore the error when link is nil, this is intentionally - i think
            if walletUniversalLink != nil {
                Web3Modal.config.onError(error)
            }
            throw error
        }
    }

    /// Ping method allows to check if peer client is online and is subscribing for given topic
    ///
    ///  Should Error:
    ///  - When the session topic is not found
    ///
    /// - Parameters:
    ///   - topic: Topic of a session
    public func ping(topic: String) async throws {
        do {
            try await signClient.ping(topic: topic)
        } catch {
            Web3Modal.config.onError(error)
            throw error
        }
    }
    
    public func request(_ request: W3MJSONRPC) async throws -> Request? {
        logger.debug("Requesting: \(request.rawValues.method)")
        switch store.connectedWith {
        case .wc:
            guard
                let session = getSessions().first,
                let chain = getSelectedChain(),
                let blockchain = Blockchain(namespace: chain.chainNamespace, reference: chain.chainReference)
            else { return nil }
            
            let signRequest: Request
            if case let .personal_sign(address, message) = request {
                signRequest = try Request(
                    topic: session.topic,
                    method: request.rawValues.method,
                    params: AnyCodable(any: [message, address]),
                    chainId: blockchain
                )
            } else if case let .eth_signTypedData_v4(address, message) = request {
                signRequest = try Request(
                    topic: session.topic,
                    method: request.rawValues.method,
                    params: AnyCodable(any: [address, message]),
                    chainId: blockchain
                )
            } else {
                signRequest = try Request(
                    topic: session.topic,
                    method: request.rawValues.method,
                    params: AnyCodable(any: request.rawValues.params),
                    chainId: blockchain
                )
            }
            try await signClient.request(
                params: signRequest
            )
            return signRequest
        case .cb:
            
            guard let jsonRpc = request.toCbAction() else { return nil }
            
            // Execute on main as Coinbase SDK is not dispatching on main when calling UIApplication.openUrl()
            DispatchQueue.main.async {
                CoinbaseWalletSDK.shared.makeRequest(
                    .init(
                        actions: [
                            Action(jsonRpc: jsonRpc)
                        ]
                    )
                ) { result in
                    let response: W3MResponse
                    switch result {
                    case let .success(payload):
                        
                        switch payload.content.first {
                        case let .success(JSONString):
                            response = .init(result: .response(AnyCodable(JSONString)))
                        case let .failure(error):
                            response = .init(result: .error(.init(code: error.code, message: error.message)))
                        case .none:
                            response = .init(result: .error(.init(code: -1, message: "Empty response")))
                        }
                    case let .failure(error):
                        Web3Modal.config.onError(error)
                        
                        if let cbError = error as? ActionError {
                            response = .init(result: .error(.init(code: cbError.code, message: cbError.message)))
                        } else {
                            response = .init(result: .error(.init(code: -1, message: error.localizedDescription)))
                        }
                    }
                    
                    self.coinbaseResponseSubject.send(response)
                }
            }
        case .phantom:
            // This is a workaround for solana sign message support
            if case let .personal_sign(address, message) = request {
                let response: W3MResponse
                do {
                    let signature = try await PhantomClient.shared?.signMessage(message: message)
                    signature?.toHexEncodedString()
                    response = .init(result: .response(AnyCodable(signature)))
                } catch {
                    response = .init(result: .error(.init(code: -1, message: error.localizedDescription)))
                }
                self.phantomResponseSubject.send(response)
            } else {
                fatalError("TODO: Not implemented yet")
            }
        case .metamask:
            if case let .personal_sign(address, message) = request {
                let response: W3MResponse
                let result = await MetaMaskSDK.sharedInstance!.personalSign(message: message, address: address)
                switch result {
                case .success(let signature):
                    response = .init(result: .response(AnyCodable(signature)))
                case .failure(let error):
                    response = .init(result: .error(.init(code: error.code, message: error.message)))
                }
                self.metamaskResponseSubject.send(response)
            } else if case let .eth_signTypedData_v4(address, message) = request {
                let response: W3MResponse
                let result = await MetaMaskSDK.sharedInstance!.signTypedDataV4(typedData: message, address: address)
                switch result {
                case .success(let signature):
                    response = .init(result: .response(AnyCodable(signature)))
                case .failure(let error):
                    response = .init(result: .error(.init(code: error.code, message: error.message)))
                }
                self.metamaskResponseSubject.send(response)
            } else {
                fatalError("TODO: Not implemented yet")
            }
            
        case .none:
            break
        }
        
        return nil
    }
    
    /// For sending JSON-RPC requests to wallet.
    /// - Parameters:
    ///   - params: Parameters defining request and related session
    public func request(params: Request) async throws {
        do {
            try await signClient.request(params: params)
        } catch {
            Web3Modal.config.onError(error)
            throw error
        }
    }
    
    /// For a terminating a session
    ///
    /// Should Error:
    /// - When the session topic is not found
    /// - Parameters:
    ///   - topic: Session topic that you want to delete
    public func disconnect(topic: String) async throws {
        switch store.connectedWith {
        case .wc:
            do {
                try await signClient.disconnect(topic: topic)
                analyticsService.track(.DISCONNECT_SUCCESS)
            } catch {
                Web3Modal.config.onError(error)
                analyticsService.track(.DISCONNECT_ERROR)
                throw error
            }
        case .cb:
            if case let .failure(error) = CoinbaseWalletSDK.shared.resetSession() {
                analyticsService.track(.DISCONNECT_ERROR)
                throw error
            } else {
                analyticsService.track(.DISCONNECT_SUCCESS)
            }
        case .phantom:
            do {
                try await PhantomClient.shared?.disconnectWallet()
                analyticsService.track(.DISCONNECT_SUCCESS)
            } catch {
                analyticsService.track(.DISCONNECT_ERROR)
                throw error
            }
        case .metamask:
            do {
                try await MetaMaskSDK.sharedInstance?.disconnect()
                analyticsService.track(.DISCONNECT_SUCCESS)
            } catch {
                analyticsService.track(.DISCONNECT_ERROR)
                throw error
            }
            
        case .none:
            break
        }
    }
    
    /// Query sessions
    /// - Returns: All sessions
    public func getSessions() -> [Session] {
        signClient.getSessions()
    }
    
    /// Query pairings
    /// - Returns: All pairings
    public func getPairings() -> [Pairing] {
        pairingClient.getPairings()
    }
    
    /// Delete all stored data such as: pairings, sessions, keys
    ///
    /// - Note: Will unsubscribe from all topics
    public func cleanup() async throws {
        defer {
            DispatchQueue.main.async {
                self.store.session = nil
                self.store.account = nil
            }
        }
        do {
            try await signClient.cleanup()
        } catch {
            Web3Modal.config.onError(error)
            throw error
        }
    }
    
    public func getAddress() -> String? {
        guard let account = store.account else { return nil }
        
        return account.address
    }
    
    public func getSelectedChain() -> Chain? {
        guard let chain = store.selectedChain else {
            return nil
        }
        
        return chain
    }
    
    public func addChainPreset(_ chain: Chain) {
        ChainPresets.allChains.append(chain)
    }
    
    public func selectChain(_ chain: Chain) {
        store.selectedChain = chain
    }
    
    public func launchCurrentWallet() {
        guard
            let session = store.session,
            let urlString = session.peer.redirect?.native ?? session.peer.redirect?.universal,
            let url = URL(string: urlString)
        else {
            self.store.toast = .init(style: .error, message: "Invalid redirect URL")
            return
        }
        
        let isHttp: Bool = url.scheme?.lowercased().hasPrefix("http") == true
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [.universalLinksOnly: isHttp]) { result in
                if !result {
                    self.store.toast = .init(style: .error, message: "Failed to open wallet")
                }
            }
        }
    }
    
    @discardableResult
    public func handleDeeplink(_ url: URL) -> Bool {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
           queryItems.contains(where: { $0.name == "wc_ev" }) {
            do {
                print("Handle deeplink with Wallet Connect")
                try signClient.dispatchEnvelope(url.absoluteString)
                return true
            } catch {
                store.toast = .init(style: .error, message: error.localizedDescription)
                return false
            }
        }
        do {
            if Phantom.canHandle(url: url) {
                print("qqq handle with Phantom SDK")
                try PhantomClient.shared?.processDeeplink(url: url)
                return true
            }
            
            if URLComponents(url: url, resolvingAgainstBaseURL: true)?.host == "mmsdk" {
                print("Handle deeplink with MetaMask SDK")
                if MetaMaskSDK.sharedInstance == nil {
                    print("qqq Why is metamask nil?")
                }
                MetaMaskSDK.sharedInstance?.handleUrl(url)
                return true
            }
            
            print("Handle deeplink with Coinbase SDK")
            return try CoinbaseWalletSDK.shared.handleResponse(url)
        } catch {
            print("Handle deeplink with error \(error)")
            store.toast = .init(style: .error, message: error.localizedDescription)
            return false
        }
    }

    private func setUpConnectionEvents() {
        analyticsService.track(.MODAL_LOADED)

        signClient.sessionSettlePublisher.sink { [unowned self] session in
            self.analyticsService.track(.CONNECT_SUCCESS(method: analyticsService.method, name: session.peer.name))
        }.store(in: &disposeBag)


        signClient.sessionRejectionPublisher.sink { [unowned self] (_, reason) in
            self.analyticsService.track(.CONNECT_ERROR(message: reason.message))
        }.store(in: &disposeBag)
    }

    public func enableAnalytics() {
        analyticsService.enable()
    }

    public func disableAnalytics() {
        analyticsService.disable()
    }
}

extension Data {
    internal func prettyPrint() -> String {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8)
        else {
            return "| Unable to pretty print! |"
        }

        return prettyPrintedString
    }
}

extension Encodable {
    internal func prettyPrint() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "| Unable to pretty print! |"
        }
    }
}

import Foundation
import WalletConnectRelay
import Starscream

struct DefaultSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        let request = URLRequest(url: url)
        let socket = DefaultWebSocket(newRequest: request)
        let queue = DispatchQueue(label: "com.walletconnect.sdk.sockets", attributes: .concurrent)
        socket.callbackQueue = queue
        return socket
    }
}

class DefaultWebSocket: WebSocket, WebSocketConnecting {
    private var _isConnected = true
    
    public var isConnected: Bool {
        _isConnected
    }
    
    var onConnect: (() -> Void)?
    
    var onDisconnect: ((Error?) -> Void)?
    
    var onText: ((String) -> Void)?
    
    convenience init(newRequest: URLRequest) {
        self.init(request: newRequest, useCustomEngine: false)
        
        onEvent = { [weak self] event in
            guard let self else { return }
            
            switch event {
            case .connected:
                _isConnected = true
                onConnect?()
            case .disconnected(let reason, let code):
                _isConnected = false
                onDisconnect?(NSError(domain: reason, code: Int(code), userInfo: nil))
            case .text(let text):
                onText?(text)
            case .binary:
                break
            case .pong:
                break
            case .ping:
                break
            case .error(let error):
                onDisconnect?(error)
            case .viabilityChanged:
                break
            case .reconnectSuggested:
                reconnect()
            case .cancelled:
                _isConnected = false
            case .peerClosed:
                reconnect()
            @unknown default:
                break
            }
        }
    }
    
    func reconnect() {
        forceDisconnect()
        connect()
    }
}


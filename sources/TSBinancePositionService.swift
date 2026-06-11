import CryptoKit
import Foundation
import UIKit

private let TSBinancePositionServiceDidUpdateNotificationName = Notification.Name("TSBinancePositionServiceDidUpdateNotification")

private enum TSBinanceEnvironment: String, Equatable {
    case mainnet
    case testnet

    var restBaseURL: URL {
        switch self {
        case .mainnet:
            return URL(string: "https://fapi.binance.com")!
        case .testnet:
            return URL(string: "https://demo-fapi.binance.com")!
        }
    }

    var webSocketBaseURL: URL {
        switch self {
        case .mainnet:
            return URL(string: "wss://fstream.binance.com/private")!
        case .testnet:
            return URL(string: "wss://fstream.binancefuture.com/private")!
        }
    }

    var markPriceStreamURL: URL {
        switch self {
        case .mainnet:
            return URL(string: "wss://fstream.binance.com/market/ws/!markPrice@arr@1s")!
        case .testnet:
            return URL(string: "wss://fstream.binancefuture.com/market/ws/!markPrice@arr@1s")!
        }
    }
}

private enum TSBinanceConnectionState {
    case idle
    case connecting
    case connected
    case reconnecting
}

private enum TSBinanceSnapshotState {
    case notConfigured
    case loading
    case ready
    case failed(String)
}

private struct TSBinanceConfig: Equatable {
    let apiKey: String
    let secret: String
    let environment: TSBinanceEnvironment
}

private enum TSBinanceConfigLoadState {
    case configured(TSBinanceConfig)
    case missing
    case unavailable(message: String, detail: String)
}

private struct TSBinancePositionRisk: Decodable {
    let symbol: String
    let positionSide: String
    let positionAmt: String
    let entryPrice: String
    let markPrice: String
    let unRealizedProfit: String
    let notional: String
    let initialMargin: String
    let updateTime: Int64?
}

private struct TSBinanceAccountResponse: Decodable {
    let totalWalletBalance: String
    let totalUnrealizedProfit: String
    let totalMarginBalance: String
    let totalInitialMargin: String
}

private struct TSBinanceAccountSummary {
    let totalEquity: Decimal
    let totalWalletBalance: Decimal
    let totalUnrealizedProfit: Decimal
    let totalInitialMargin: Decimal
}

private struct TSBinanceListenKeyResponse: Decodable {
    let listenKey: String
}

private struct TSBinanceMarkPriceUpdate: Decodable {
    let symbol: String
    let markPrice: String

    enum CodingKeys: String, CodingKey {
        case symbol = "s"
        case markPrice = "p"
    }
}

private struct TSBinanceStreamEnvelope: Decodable {
    let eventType: String?
    let eventTime: Int64?

    enum CodingKeys: String, CodingKey {
        case eventType = "e"
        case eventTime = "E"
    }
}

private struct TSBinanceDisplayEntry {
    let rawSymbol: String
    let symbol: String
    let side: String
    let quantity: String
    let pnl: String
    let roe: String?
    let entryPrice: String
    let markPrice: String
    let sortValue: Decimal
}

private struct TSBinancePositionSnapshot {
    let rawSymbol: String
    let symbol: String
    let side: String
    let quantity: Decimal
    let entryPrice: Decimal
    let markPrice: Decimal
    let pnl: Decimal
    let notional: Decimal
    let initialMargin: Decimal?
}

private enum TSBinanceDisplayMode: String {
    case positions
    case summary
}

private struct TSBinanceDisplayOptions {
    let displayMode: TSBinanceDisplayMode
    let showSymbol: Bool
    let showSide: Bool
    let showQuantity: Bool
    let showCurrentPrice: Bool
    let showEntryPrice: Bool
    let showPnL: Bool
    let showRoe: Bool
    let showTotalEquity: Bool
    let showFloatingPnL: Bool
    let showFloatingPnLRate: Bool
    let showTotalROI: Bool
    let snapshotRefreshInterval: TimeInterval
    let focusSymbol: String
}

@objcMembers
final class TSBinancePositionService: NSObject {
    private static let sharedInstance = TSBinancePositionService()
    private static let defaultSnapshotRefreshInterval: TimeInterval = 5
    private static let keepAliveInterval: TimeInterval = 50 * 60
    private static let reconnectBaseDelay: TimeInterval = 3
    private static let maxReconnectDelay: TimeInterval = 30

    private let workQueue = DispatchQueue(label: "com.inighty.binancehud.binance.service")
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    private var snapshotState: TSBinanceSnapshotState = .notConfigured
    private var connectionState: TSBinanceConnectionState = .idle
    private var currentConfig: TSBinanceConfig?
    private var displayOptions = TSBinancePositionService.defaultDisplayOptions()
    private var positionSnapshots: [TSBinancePositionSnapshot] = []
    private var displayEntries: [TSBinanceDisplayEntry] = []
    private var accountSummary: TSBinanceAccountSummary?
    private var lastUpdatedAt: Date?
    private var latestErrorMessage: String?
    private var isStarted = false

    private var listenKey: String?
    private var webSocketTask: URLSessionWebSocketTask?
    private var markPriceWebSocketTask: URLSessionWebSocketTask?
    private var keepAliveTimer: DispatchSourceTimer?
    private var snapshotTimer: DispatchSourceTimer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var snapshotRefreshWorkItem: DispatchWorkItem?
    private var reconnectAttempt = 0

    @objc(sharedService)
    class func sharedService() -> TSBinancePositionService {
        sharedInstance
    }

    func start() {
        workQueue.async {
            self.isStarted = true
            self.configureAndStartIfNeeded(forceRestart: false)
        }
    }

    func stop() {
        workQueue.async {
            self.isStarted = false
            self.cancelReconnect()
            self.cancelSnapshotRefresh()
            self.stopTimers()
            self.disconnectCurrentWebSocket()
            self.disconnectMarkPriceWebSocket()
            self.listenKey = nil
            self.connectionState = .idle
        }
    }

    func reloadConfiguration() {
        workQueue.async {
            self.configureAndStartIfNeeded(forceRestart: true)
        }
    }

    @objc(notificationName)
    class func notificationName() -> String {
        TSBinancePositionServiceDidUpdateNotificationName.rawValue
    }

    func diagnosticsText() -> String {
        var lines: [String] = []

        workQueue.sync {
            lines.append("Binance position diagnostics:")
            if let config = currentConfig {
                lines.append("environment: \(config.environment.rawValue)")
            } else {
                lines.append("environment: notConfigured")
            }
            lines.append("displayMode: \(displayOptions.displayMode.rawValue)")
            lines.append("refreshInterval: \(Int(displayOptions.snapshotRefreshInterval))s")
            lines.append("focusSymbol: \(displayOptions.focusSymbol.isEmpty ? "<none>" : displayOptions.focusSymbol)")
            lines.append("snapshotState: \(diagnosticSnapshotStateText(snapshotState))")
            lines.append("connectionState: \(diagnosticConnectionStateText(connectionState))")
            lines.append("lastUpdatedAt: \(lastUpdatedAt?.description ?? "<never>")")
            if let latestErrorMessage, !latestErrorMessage.isEmpty {
                lines.append("latestError: \(latestErrorMessage)")
            }

            if let summary = accountSummary {
                lines.append("accountSummary:")
                lines.append("  totalEquity: \(trimDecimal(summary.totalEquity))")
                lines.append("  walletBalance: \(trimDecimal(summary.totalWalletBalance))")
                lines.append("  totalUnrealizedProfit: \(trimDecimal(summary.totalUnrealizedProfit))")
                lines.append("  totalInitialMargin: \(trimDecimal(summary.totalInitialMargin))")
            }

            lines.append("displayEntries: \(displayEntries.count)")
            for (index, entry) in displayEntries.enumerated() {
                lines.append([
                    "  display[\(index)]",
                    "raw=\(entry.rawSymbol)",
                    "symbol=\(entry.symbol)",
                    "side=\(entry.side)",
                    "qty=\(entry.quantity)",
                    "entry=\(entry.entryPrice)",
                    "mark=\(entry.markPrice)",
                    "pnl=\(entry.pnl)",
                    "roe=\(entry.roe ?? "<none>")"
                ].joined(separator: " "))
            }

            if displayOptions.focusSymbol.isEmpty, let first = displayEntries.first {
                lines.append("centeredDefault: \(first.rawSymbol) \(first.side) pnl=\(first.pnl)")
            }

            lines.append("positionSnapshots: \(positionSnapshots.count)")
            for (index, position) in positionSnapshots.enumerated() {
                lines.append([
                    "  position[\(index)]",
                    "raw=\(position.rawSymbol)",
                    "symbol=\(position.symbol)",
                    "side=\(position.side)",
                    "qty=\(trimDecimal(quantityMagnitude(from: position.quantity)))",
                    "signedQty=\(trimDecimal(position.quantity))",
                    "entry=\(trimDecimal(position.entryPrice))",
                    "mark=\(trimDecimal(position.markPrice))",
                    "pnl=\(trimDecimal(position.pnl))",
                    "notional=\(trimDecimal(position.notional))",
                    "initialMargin=\(position.initialMargin.map { trimDecimal($0) } ?? "<none>")"
                ].joined(separator: " "))
            }

            lines.append("notes:")
            lines.append("  pnl uses Binance /fapi/v3/positionRisk unRealizedProfit when present.")
            lines.append("  mark uses REST snapshot plus public mark-price stream updates.")
            lines.append("  centered HUD without focus shows display[0].")
        }

        return lines.joined(separator: "\n")
    }

    @objc(hudAttributedTextForCentered:focused:fontSize:fontWeight:)
    func hudAttributedText(forCentered centered: Bool, focused: Bool, fontSize: CGFloat, fontWeight: CGFloat) -> NSAttributedString {
        var state: TSBinanceSnapshotState = .notConfigured
        var entries: [TSBinanceDisplayEntry] = []
        var summary: TSBinanceAccountSummary?
        var options = Self.defaultDisplayOptions()
        var latestError: String?

        workQueue.sync {
            state = snapshotState
            entries = displayEntries
            summary = accountSummary
            options = displayOptions
            latestError = latestErrorMessage
        }

        let mainFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: UIFont.Weight(fontWeight))
        let detailFont = UIFont.monospacedDigitSystemFont(ofSize: max(fontSize - 1, 8), weight: UIFont.Weight(fontWeight))
        let mutedFont = UIFont.systemFont(ofSize: max(fontSize - 1, 8), weight: .medium)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: mainFont,
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: detailFont,
        ]
        let mutedAttributes: [NSAttributedString.Key: Any] = [
            .font: mutedFont,
        ]

        let attributed = NSMutableAttributedString()

        switch state {
        case .notConfigured:
            attributed.append(NSAttributedString(string: NSLocalizedString("Binance API not configured", comment: "TSBinancePositionService"), attributes: baseAttributes))
            attributed.append(NSAttributedString(string: "\n" + NSLocalizedString("Open Settings to add API Key and Secret", comment: "TSBinancePositionService"), attributes: mutedAttributes))
            return attributed
        case .loading:
            attributed.append(NSAttributedString(string: NSLocalizedString("Loading Binance positions...", comment: "TSBinancePositionService"), attributes: baseAttributes))
            return attributed
        case .failed(let message):
            attributed.append(NSAttributedString(string: message, attributes: baseAttributes))
            if let latestError, !latestError.isEmpty, latestError != message {
                attributed.append(NSAttributedString(string: "\n" + latestError, attributes: mutedAttributes))
            }
            return attributed
        case .ready:
            break
        }

        if options.displayMode == .summary {
            return summaryAttributedText(
                summary: summary,
                options: options,
                baseAttributes: baseAttributes,
                detailAttributes: detailAttributes,
                mutedAttributes: mutedAttributes
            )
        }

        let visibleEntries: [TSBinanceDisplayEntry]
        let remainingCount: Int
        let forceCentered: Bool

        if !options.focusSymbol.isEmpty {
            if entries.isEmpty {
                return NSAttributedString()
            }
            let match = entries.first { $0.rawSymbol.uppercased() == options.focusSymbol }
            visibleEntries = [match ?? entries[0]]
            remainingCount = 0
            forceCentered = true
        } else {
            guard !entries.isEmpty else {
                attributed.append(NSAttributedString(string: NSLocalizedString("No open futures positions", comment: "TSBinancePositionService"), attributes: baseAttributes))
                return attributed
            }
            let visibleCount = centered ? 1 : min(entries.count, focused ? 2 : 3)
            visibleEntries = Array(entries.prefix(visibleCount))
            remainingCount = entries.count - visibleEntries.count
            forceCentered = false
        }

        for (index, entry) in visibleEntries.enumerated() {
            if index > 0 {
                attributed.append(NSAttributedString(string: "\n", attributes: detailAttributes))
            }

            let mainLine = mainLineText(for: entry, options: options)
            attributed.append(NSAttributedString(string: mainLine, attributes: baseAttributes))
        }

        let primaryEntry = visibleEntries[0]

        if (focused || centered || forceCentered), let secondaryLine = secondaryLineText(for: primaryEntry, options: options) {
            attributed.append(NSAttributedString(string: "\n" + secondaryLine, attributes: detailAttributes))
        }

        if remainingCount > 0 {
            attributed.append(NSAttributedString(
                string: "\n+" + String(remainingCount) + " " + NSLocalizedString("more", comment: "TSBinancePositionService"),
                attributes: mutedAttributes
            ))
        }

        return attributed
    }

    private func summaryAttributedText(
        summary: TSBinanceAccountSummary?,
        options: TSBinanceDisplayOptions,
        baseAttributes: [NSAttributedString.Key: Any],
        detailAttributes: [NSAttributedString.Key: Any],
        mutedAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString()

        guard let summary else {
            attributed.append(NSAttributedString(string: NSLocalizedString("Loading Binance account...", comment: "TSBinancePositionService"), attributes: baseAttributes))
            return attributed
        }

        var mainComponents: [String] = []
        if options.showTotalEquity {
            mainComponents.append(trimDecimal(summary.totalEquity))
        }
        if options.showFloatingPnL {
            mainComponents.append(signedString(for: summary.totalUnrealizedProfit, suffix: ""))
        }

        var detailComponents: [String] = []
        if options.showFloatingPnLRate {
            let rate = floatingPnLRate(for: summary)
            detailComponents.append("PNL " + signedString(for: rate, suffix: "%"))
        }
        if options.showTotalROI {
            let roi = totalROI(for: summary)
            detailComponents.append("ROI " + signedString(for: roi, suffix: "%"))
        }

        if mainComponents.isEmpty && detailComponents.isEmpty {
            mainComponents.append(trimDecimal(summary.totalEquity))
        }

        if !mainComponents.isEmpty {
            attributed.append(NSAttributedString(string: mainComponents.joined(separator: " "), attributes: baseAttributes))
        }

        if !detailComponents.isEmpty {
            let prefix = mainComponents.isEmpty ? "" : "\n"
            attributed.append(NSAttributedString(string: prefix + detailComponents.joined(separator: "  "), attributes: detailAttributes))
        }

        return attributed
    }

    private func floatingPnLRate(for summary: TSBinanceAccountSummary) -> Decimal {
        let denominator = summary.totalInitialMargin != 0 ? summary.totalInitialMargin : summary.totalWalletBalance
        guard denominator != 0 else { return 0 }
        return (summary.totalUnrealizedProfit / denominator) * 100
    }

    private func totalROI(for summary: TSBinanceAccountSummary) -> Decimal {
        guard summary.totalWalletBalance != 0 else { return 0 }
        return (summary.totalUnrealizedProfit / summary.totalWalletBalance) * 100
    }

    private func configureAndStartIfNeeded(forceRestart: Bool) {
        let configState = loadConfig()
        displayOptions = loadDisplayOptions()

        let newConfig: TSBinanceConfig?
        switch configState {
        case .configured(let config):
            newConfig = config
        case .missing:
            newConfig = nil
        case .unavailable(let message, let detail):
            if let cachedConfig = currentConfig {
                newConfig = cachedConfig
                latestErrorMessage = detail
            } else {
                stopTimers()
                disconnectCurrentWebSocket()
                disconnectMarkPriceWebSocket()
                listenKey = nil
                connectionState = .idle
                updateState(snapshot: .failed(message), error: detail, entries: nil)
                return
            }
        }

        guard isStarted else {
            currentConfig = newConfig
            updateState(snapshot: newConfig == nil ? .notConfigured : .loading, error: nil, entries: nil)
            return
        }

        guard let newConfig else {
            currentConfig = nil
            stopTimers()
            disconnectCurrentWebSocket()
            disconnectMarkPriceWebSocket()
            listenKey = nil
            connectionState = .idle
            positionSnapshots = []
            displayEntries = []
            updateState(snapshot: .notConfigured, error: nil, entries: [])
            return
        }

        let shouldRestart = forceRestart || currentConfig != newConfig
        currentConfig = newConfig

        if !shouldRestart, webSocketTask != nil || connectionState == .connecting {
            return
        }

        stopTimers()
        disconnectCurrentWebSocket()
        disconnectMarkPriceWebSocket()
        listenKey = nil
        reconnectAttempt = 0
        connectionState = .idle
        latestErrorMessage = nil
        updateState(snapshot: .loading, error: nil, entries: nil)
        refreshSnapshot(reason: "startup")
        setupPeriodicSnapshotRefresh()
        connectUserStream()
    }

    private func loadConfig() -> TSBinanceConfigLoadState {
        let credentialStore = TSBinanceCredentialStore.sharedStore()
        switch credentialStore.credentialState() {
        case .configured(let apiKey, let secret):
            let useTestnet = GetStandardUserDefaults().bool(forKey: HUDUserDefaultsKeyBinanceUseTestnet)
            let environment: TSBinanceEnvironment = useTestnet ? .testnet : .mainnet
            return .configured(TSBinanceConfig(apiKey: apiKey, secret: secret, environment: environment))
        case .missing:
            return .missing
        case .temporarilyUnavailable(let error), .failed(let error):
            return .unavailable(
                message: NSLocalizedString("Binance credentials temporarily unavailable", comment: "TSBinancePositionService"),
                detail: error.localizedDescription
            )
        }
    }

    private func updateState(snapshot: TSBinanceSnapshotState, error: String?, entries: [TSBinanceDisplayEntry]?) {
        snapshotState = snapshot
        if let entries {
            displayEntries = entries
            persistLastKnownSymbols(from: entries)
        }
        latestErrorMessage = error
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: TSBinancePositionServiceDidUpdateNotificationName, object: nil)
        }
    }

    private func diagnosticSnapshotStateText(_ state: TSBinanceSnapshotState) -> String {
        switch state {
        case .notConfigured:
            return "notConfigured"
        case .loading:
            return "loading"
        case .ready:
            return "ready"
        case .failed(let message):
            return "failed(\(message))"
        }
    }

    private func diagnosticConnectionStateText(_ state: TSBinanceConnectionState) -> String {
        switch state {
        case .idle:
            return "idle"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .reconnecting:
            return "reconnecting"
        }
    }

    private func persistLastKnownSymbols(from entries: [TSBinanceDisplayEntry]) {
        var seen = Set<String>()
        let symbols = entries.compactMap { entry -> String? in
            let symbol = entry.rawSymbol
            if symbol.isEmpty || !seen.insert(symbol).inserted {
                return nil
            }
            return symbol
        }
        let defaults = GetStandardUserDefaults()
        let existing = (defaults.array(forKey: HUDUserDefaultsKeyBinanceLastKnownSymbols) as? [String]) ?? []
        if existing == symbols {
            return
        }
        defaults.set(symbols, forKey: HUDUserDefaultsKeyBinanceLastKnownSymbols)
    }

    private func refreshSnapshot(reason: String) {
        guard let config = currentConfig else {
            updateState(snapshot: .notConfigured, error: nil, entries: [])
            return
        }

        if displayOptions.displayMode == .summary {
            refreshAccountSummary(config: config)
        } else {
            refreshPositionRisk(config: config)
        }
    }

    private func refreshPositionRisk(config: TSBinanceConfig) {
        performSignedRequest(
            config: config,
            method: "GET",
            path: "/fapi/v3/positionRisk",
            securityType: .signed,
            queryItems: []
        ) { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard config == self.currentConfig else { return }

                switch result {
                case .success(let data):
                    do {
                        let positions = try JSONDecoder().decode([TSBinancePositionRisk].self, from: data)
                        let snapshots = self.makePositionSnapshots(from: positions)
                        let entries = self.makeDisplayEntries(from: snapshots)
                        self.positionSnapshots = snapshots
                        self.lastUpdatedAt = Date()
                        self.updateState(snapshot: .ready, error: nil, entries: entries)
                        self.startMarkPriceStreamIfNeeded(config: config)
                    } catch {
                        self.latestErrorMessage = error.localizedDescription
                        if self.displayEntries.isEmpty {
                            self.updateState(
                                snapshot: .failed(NSLocalizedString("Unable to decode Binance positions", comment: "TSBinancePositionService")),
                                error: error.localizedDescription,
                                entries: nil
                            )
                        } else {
                            self.postUpdateNotification()
                        }
                    }
                case .failure(let error):
                    self.latestErrorMessage = error.localizedDescription
                    if self.displayEntries.isEmpty {
                        self.updateState(snapshot: .failed(self.userFacingErrorMessage(from: error)), error: error.localizedDescription, entries: nil)
                    } else {
                        self.postUpdateNotification()
                    }
                }
            }
        }
    }

    private func refreshAccountSummary(config: TSBinanceConfig) {
        performSignedRequest(
            config: config,
            method: "GET",
            path: "/fapi/v2/account",
            securityType: .signed,
            queryItems: []
        ) { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard config == self.currentConfig else { return }

                switch result {
                case .success(let data):
                    do {
                        let response = try JSONDecoder().decode(TSBinanceAccountResponse.self, from: data)
                        let summary = TSBinanceAccountSummary(
                            totalEquity: self.decimal(from: response.totalMarginBalance) ?? 0,
                            totalWalletBalance: self.decimal(from: response.totalWalletBalance) ?? 0,
                            totalUnrealizedProfit: self.decimal(from: response.totalUnrealizedProfit) ?? 0,
                            totalInitialMargin: self.decimal(from: response.totalInitialMargin) ?? 0
                        )
                        self.lastUpdatedAt = Date()
                        self.accountSummary = summary
                        self.snapshotState = .ready
                        self.latestErrorMessage = nil
                        self.postUpdateNotification()
                    } catch {
                        self.latestErrorMessage = error.localizedDescription
                        if self.accountSummary == nil {
                            self.snapshotState = .failed(NSLocalizedString("Unable to decode Binance account", comment: "TSBinancePositionService"))
                            self.postUpdateNotification()
                        } else {
                            self.postUpdateNotification()
                        }
                    }
                case .failure(let error):
                    self.latestErrorMessage = error.localizedDescription
                    if self.accountSummary == nil {
                        self.snapshotState = .failed(self.userFacingErrorMessage(from: error))
                        self.postUpdateNotification()
                    } else {
                        self.postUpdateNotification()
                    }
                }
            }
        }
    }

    private func makePositionSnapshots(from positions: [TSBinancePositionRisk]) -> [TSBinancePositionSnapshot] {
        positions.compactMap { position in
            guard let quantity = decimal(from: position.positionAmt), quantity != 0 else {
                return nil
            }

            let side: String
            if position.positionSide == "LONG" {
                side = "L"
            } else if position.positionSide == "SHORT" {
                side = "S"
            } else {
                side = quantity >= 0 ? "L" : "S"
            }

            guard
                let entryPrice = decimal(from: position.entryPrice),
                let markPrice = decimal(from: position.markPrice)
            else {
                return nil
            }

            let calculatedPnL = unrealizedPnL(
                quantity: quantity,
                side: side,
                entryPrice: entryPrice,
                markPrice: markPrice
            )
            let apiPnL = decimal(from: position.unRealizedProfit)
            let pnl = apiPnL ?? calculatedPnL
            let notional = absDecimal(from: position.notional) ?? abs(quantity)
            let initialMargin = absDecimal(from: position.initialMargin)

            return TSBinancePositionSnapshot(
                rawSymbol: position.symbol,
                symbol: self.displaySymbol(for: position.symbol),
                side: side,
                quantity: quantity,
                entryPrice: entryPrice,
                markPrice: markPrice,
                pnl: pnl,
                notional: notional,
                initialMargin: initialMargin
            )
        }
    }

    private func makeDisplayEntries(from snapshots: [TSBinancePositionSnapshot]) -> [TSBinanceDisplayEntry] {
        snapshots.map { position in
            let roe: String?
            if let initialMargin = position.initialMargin, initialMargin != 0 {
                roe = signedString(for: (position.pnl / initialMargin) * 100, suffix: "%")
            } else {
                roe = nil
            }

            return TSBinanceDisplayEntry(
                rawSymbol: position.rawSymbol,
                symbol: position.symbol,
                side: position.side,
                quantity: self.trimDecimal(self.quantityMagnitude(from: position.quantity)),
                pnl: signedString(for: position.pnl, suffix: ""),
                roe: roe,
                entryPrice: trimDecimal(position.entryPrice),
                markPrice: trimDecimal(position.markPrice),
                sortValue: position.notional
            )
        }
        .sorted {
            if $0.symbol == $1.symbol {
                return $0.side < $1.side
            }
            return $0.symbol < $1.symbol
        }
    }

    private func unrealizedPnL(quantity: Decimal, side: String, entryPrice: Decimal, markPrice: Decimal) -> Decimal {
        let quantityMagnitude = abs(quantity)
        if side == "S" {
            return (entryPrice - markPrice) * quantityMagnitude
        }
        return (markPrice - entryPrice) * quantityMagnitude
    }

    private func connectUserStream() {
        guard let config = currentConfig else { return }
        connectionState = .connecting

        performSignedRequest(
            config: config,
            method: "POST",
            path: "/fapi/v1/listenKey",
            securityType: .apiKey,
            queryItems: []
        ) { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard config == self.currentConfig else { return }

                switch result {
                case .success(let data):
                    do {
                        let response = try JSONDecoder().decode(TSBinanceListenKeyResponse.self, from: data)
                        self.listenKey = response.listenKey
                        self.reconnectAttempt = 0
                        self.connectionState = .connected
                        self.openWebSocket(listenKey: response.listenKey, config: config)
                        self.setupKeepAliveTimer()
                    } catch {
                        self.handleConnectionFailure(error)
                    }
                case .failure(let error):
                    self.handleConnectionFailure(error)
                }
            }
        }
    }

    private func openWebSocket(listenKey: String, config: TSBinanceConfig) {
        let webSocketURL = config.environment.webSocketBaseURL.appendingPathComponent("ws").appendingPathComponent(listenKey)
        let task = session.webSocketTask(with: webSocketURL)
        webSocketTask = task
        task.resume()
        receiveNextMessage(for: task, config: config)
    }

    private func receiveNextMessage(for task: URLSessionWebSocketTask, config: TSBinanceConfig) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard task == self.webSocketTask, config == self.currentConfig else { return }

                switch result {
                case .success(let message):
                    self.handleWebSocketMessage(message, config: config)
                    self.receiveNextMessage(for: task, config: config)
                case .failure(let error):
                    self.handleConnectionFailure(error)
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message, config: TSBinanceConfig) {
        let data: Data
        switch message {
        case .data(let payload):
            data = payload
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        guard let envelope = try? JSONDecoder().decode(TSBinanceStreamEnvelope.self, from: data) else {
            return
        }

        switch envelope.eventType {
        case "ACCOUNT_UPDATE":
            scheduleSnapshotRefreshSoon()
        case "listenKeyExpired":
            reconnectUserStream()
        default:
            break
        }
    }

    private func startMarkPriceStreamIfNeeded(config: TSBinanceConfig) {
        guard !positionSnapshots.isEmpty else {
            disconnectMarkPriceWebSocket()
            return
        }
        guard markPriceWebSocketTask == nil else {
            return
        }

        let task = session.webSocketTask(with: config.environment.markPriceStreamURL)
        markPriceWebSocketTask = task
        task.resume()
        receiveNextMarkPriceMessage(for: task, config: config)
    }

    private func receiveNextMarkPriceMessage(for task: URLSessionWebSocketTask, config: TSBinanceConfig) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard task == self.markPriceWebSocketTask, config == self.currentConfig else { return }

                switch result {
                case .success(let message):
                    self.handleMarkPriceMessage(message)
                    self.receiveNextMarkPriceMessage(for: task, config: config)
                case .failure:
                    self.handleMarkPriceConnectionFailure(config: config)
                }
            }
        }
    }

    private func handleMarkPriceMessage(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let payload):
            data = payload
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        let updates: [TSBinanceMarkPriceUpdate]
        if let array = try? JSONDecoder().decode([TSBinanceMarkPriceUpdate].self, from: data) {
            updates = array
        } else if let single = try? JSONDecoder().decode(TSBinanceMarkPriceUpdate.self, from: data) {
            updates = [single]
        } else {
            return
        }

        var priceBySymbol: [String: Decimal] = [:]
        for update in updates {
            guard let price = decimal(from: update.markPrice) else { continue }
            priceBySymbol[update.symbol] = price
        }
        guard !priceBySymbol.isEmpty else { return }

        var changed = false
        positionSnapshots = positionSnapshots.map { position in
            guard let markPrice = priceBySymbol[position.rawSymbol], markPrice != position.markPrice else {
                return position
            }

            changed = true
            return TSBinancePositionSnapshot(
                rawSymbol: position.rawSymbol,
                symbol: position.symbol,
                side: position.side,
                quantity: position.quantity,
                entryPrice: position.entryPrice,
                markPrice: markPrice,
                pnl: position.pnl,
                notional: position.notional,
                initialMargin: position.initialMargin
            )
        }

        guard changed else { return }
        displayEntries = makeDisplayEntries(from: positionSnapshots)
        lastUpdatedAt = Date()
        postUpdateNotification()
    }

    private func handleMarkPriceConnectionFailure(config: TSBinanceConfig) {
        markPriceWebSocketTask = nil
        guard isStarted, config == currentConfig, !positionSnapshots.isEmpty else {
            return
        }
        workQueue.asyncAfter(deadline: .now() + Self.reconnectBaseDelay) { [weak self] in
            guard let self else { return }
            self.startMarkPriceStreamIfNeeded(config: config)
        }
    }

    private func setupKeepAliveTimer() {
        keepAliveTimer?.cancel()
        guard let config = currentConfig else { return }

        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + Self.keepAliveInterval, repeating: Self.keepAliveInterval)
        timer.setEventHandler { [weak self] in
            self?.keepAliveListenKey(using: config)
        }
        keepAliveTimer = timer
        timer.resume()
    }

    private func setupPeriodicSnapshotRefresh() {
        snapshotTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        let refreshInterval = max(displayOptions.snapshotRefreshInterval, 1)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in
            self?.refreshSnapshot(reason: "periodic")
        }
        snapshotTimer = timer
        timer.resume()
    }

    private func keepAliveListenKey(using config: TSBinanceConfig) {
        guard let listenKey else {
            connectUserStream()
            return
        }

        performSignedRequest(
            config: config,
            method: "PUT",
            path: "/fapi/v1/listenKey",
            securityType: .apiKey,
            queryItems: [URLQueryItem(name: "listenKey", value: listenKey)]
        ) { [weak self] result in
            guard let self else { return }
            self.workQueue.async {
                guard config == self.currentConfig else { return }
                if case .failure = result {
                    self.reconnectUserStream()
                }
            }
        }
    }

    private func scheduleSnapshotRefreshSoon() {
        cancelSnapshotRefresh()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshSnapshot(reason: "account-update")
        }
        snapshotRefreshWorkItem = workItem
        workQueue.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cancelSnapshotRefresh() {
        snapshotRefreshWorkItem?.cancel()
        snapshotRefreshWorkItem = nil
    }

    private func reconnectUserStream() {
        guard isStarted, currentConfig != nil else { return }
        connectionState = .reconnecting
        stopTimers()
        disconnectCurrentWebSocket()
        listenKey = nil
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        cancelReconnect()
        reconnectAttempt += 1
        let delay = min(Self.reconnectBaseDelay * Double(reconnectAttempt), Self.maxReconnectDelay)
        let workItem = DispatchWorkItem { [weak self] in
            self?.configureAndStartIfNeeded(forceRestart: true)
        }
        reconnectWorkItem = workItem
        workQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    private func handleConnectionFailure(_ error: Error) {
        latestErrorMessage = error.localizedDescription
        reconnectUserStream()
        postUpdateNotification()
    }

    private func stopTimers() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        snapshotTimer?.cancel()
        snapshotTimer = nil
    }

    private func disconnectCurrentWebSocket() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    private func disconnectMarkPriceWebSocket() {
        markPriceWebSocketTask?.cancel(with: .normalClosure, reason: nil)
        markPriceWebSocketTask = nil
    }

    private func postUpdateNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: TSBinancePositionServiceDidUpdateNotificationName, object: nil)
        }
    }

    private enum TSBinanceSecurityType: Equatable {
        case none
        case apiKey
        case signed
    }

    private func performSignedRequest(
        config: TSBinanceConfig,
        method: String,
        path: String,
        securityType: TSBinanceSecurityType,
        queryItems: [URLQueryItem],
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var items = queryItems

        if securityType == .signed {
            items.append(URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000))))
            items.append(URLQueryItem(name: "recvWindow", value: "5000"))
            let query = queryString(from: items)
            let signature = sign(query: query, secret: config.secret)
            items.append(URLQueryItem(name: "signature", value: signature))
        }

        var components = URLComponents(url: config.environment.restBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = queryString(from: items)

        guard let url = components.url else {
            completion(.failure(NSError(domain: "TSBinancePositionService", code: 100, userInfo: [NSLocalizedDescriptionKey: "Invalid Binance URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if securityType == .apiKey || securityType == .signed {
            request.setValue(config.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                let data
            else {
                completion(.failure(NSError(domain: "TSBinancePositionService", code: 101, userInfo: [NSLocalizedDescriptionKey: "Missing Binance response"])))
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                completion(.failure(self.binanceAPIError(from: data, statusCode: httpResponse.statusCode)))
                return
            }

            completion(.success(data))
        }.resume()
    }

    private func binanceAPIError(from data: Data, statusCode: Int) -> NSError {
        if
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["msg"] as? String
        {
            return NSError(
                domain: "TSBinanceAPI",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        return NSError(
            domain: "TSBinanceAPI",
            code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"]
        )
    }

    private func userFacingErrorMessage(from error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("api-key") || message.contains("signature") || message.contains("permission") {
            return NSLocalizedString("Binance authentication failed", comment: "TSBinancePositionService")
        }
        if message.contains("timed out") || message.contains("offline") || message.contains("network") {
            return NSLocalizedString("Binance network unavailable", comment: "TSBinancePositionService")
        }
        return NSLocalizedString("Unable to load Binance positions", comment: "TSBinancePositionService")
    }

    private func queryString(from items: [URLQueryItem]) -> String {
        items
            .map {
                let value = $0.value ?? ""
                return "\($0.name)=\(percentEncode(value))"
            }
            .joined(separator: "&")
    }

    private func percentEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func sign(query: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(query.utf8), using: key)
        return signature.map { String(format: "%02x", $0) }.joined()
    }

    private func loadDisplayOptions() -> TSBinanceDisplayOptions {
        let defaults = GetStandardUserDefaults()
        let refreshInterval = defaults.double(forKey: HUDUserDefaultsKeyBinanceRefreshInterval)
        let focusRaw = (defaults.string(forKey: HUDUserDefaultsKeyBinanceFocusSymbol) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let modeRaw = (defaults.string(forKey: HUDUserDefaultsKeyBinanceDisplayMode) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let mode = TSBinanceDisplayMode(rawValue: modeRaw) ?? .positions
        return TSBinanceDisplayOptions(
            displayMode: mode,
            showSymbol: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowSymbol),
            showSide: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowSide),
            showQuantity: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowQuantity),
            showCurrentPrice: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowCurrentPrice),
            showEntryPrice: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowEntryPrice),
            showPnL: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowPnL),
            showRoe: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowROE),
            showTotalEquity: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowTotalEquity),
            showFloatingPnL: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowFloatingPnL),
            showFloatingPnLRate: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowFloatingPnLRate),
            showTotalROI: defaults.bool(forKey: HUDUserDefaultsKeyBinanceShowTotalROI),
            snapshotRefreshInterval: refreshInterval > 0 ? refreshInterval : Self.defaultSnapshotRefreshInterval,
            focusSymbol: focusRaw
        )
    }

    private static func defaultDisplayOptions() -> TSBinanceDisplayOptions {
        TSBinanceDisplayOptions(
            displayMode: .positions,
            showSymbol: true,
            showSide: true,
            showQuantity: false,
            showCurrentPrice: true,
            showEntryPrice: false,
            showPnL: true,
            showRoe: false,
            showTotalEquity: true,
            showFloatingPnL: true,
            showFloatingPnLRate: false,
            showTotalROI: false,
            snapshotRefreshInterval: defaultSnapshotRefreshInterval,
            focusSymbol: ""
        )
    }

    private func mainLineText(for entry: TSBinanceDisplayEntry, options: TSBinanceDisplayOptions) -> String {
        var components: [String] = []

        if options.showSymbol {
            components.append(entry.symbol)
        }
        if options.showSide {
            components.append(entry.side)
        }
        if options.showQuantity {
            components.append("Q\(entry.quantity)")
        }
        if options.showCurrentPrice {
            components.append("P\(entry.markPrice)")
        }
        if options.showPnL {
            components.append(entry.pnl)
        }

        if components.isEmpty {
            components.append(entry.symbol)
        }

        return components.joined(separator: " ")
    }

    private func secondaryLineText(for entry: TSBinanceDisplayEntry, options: TSBinanceDisplayOptions) -> String? {
        var components: [String] = []

        if options.showEntryPrice {
            components.append("E \(entry.entryPrice)")
        }
        if options.showRoe, let roe = entry.roe {
            components.append("ROE \(roe)")
        }

        guard !components.isEmpty else {
            return nil
        }

        return components.joined(separator: "  ")
    }

    private func decimal(from string: String) -> Decimal? {
        Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func absDecimal(from string: String) -> Decimal? {
        guard let value = decimal(from: string) else {
            return nil
        }
        return abs(value)
    }

    private func trimDecimalString(_ string: String) -> String {
        guard let value = decimal(from: string) else {
            return string
        }
        return trimDecimal(value)
    }

    private func trimDecimal(_ decimalValue: Decimal) -> String {
        var value = decimalValue
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 6, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        if number == NSDecimalNumber.notANumber {
            return "--"
        }
        return number.stringValue
    }

    private func signedString(for decimal: Decimal, suffix: String) -> String {
        var value = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let number = NSDecimalNumber(decimal: rounded)
        if number == NSDecimalNumber.notANumber {
            return "--"
        }
        let prefix = number.compare(NSDecimalNumber.zero) == .orderedAscending ? "" : "+"
        return prefix + number.stringValue + suffix
    }

    private func quantityMagnitude(from value: Decimal) -> Decimal {
        value < 0 ? (0 - value) : value
    }

    private func displaySymbol(for symbol: String) -> String {
        if symbol.hasSuffix("USDT") {
            return String(symbol.dropLast(4))
        }
        return symbol
    }
}

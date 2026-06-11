import Foundation

@objc public enum TSSettingItemKind: Int {
    case toggle
    case value
}

enum TSSettingsIndex: Int, CaseIterable {
    case binanceAccount = 0
    case binanceUseTestnet
    case binanceRefreshInterval
    case binanceDisplayMode
    case binanceFocusSymbol
    case binanceShowSymbol
    case binanceShowSide
    case binanceShowQuantity
    case binanceShowCurrentPrice
    case binanceShowEntryPrice
    case binanceShowPnL
    case binanceShowROE
    case binanceShowTotalEquity
    case binanceShowFloatingPnL
    case binanceShowFloatingPnLRate
    case binanceShowTotalROI
    case passthroughMode
    case keepInPlace
    case hideAtSnapshot
    case usesInvertedColor
    case usesRotation
    case usesLargeFont

    var key: String {
        switch self {
        case .binanceAccount:
            return HUDUserDefaultsKeyBinanceAccount
        case .binanceUseTestnet:
            return HUDUserDefaultsKeyBinanceUseTestnet
        case .binanceRefreshInterval:
            return HUDUserDefaultsKeyBinanceRefreshInterval
        case .binanceDisplayMode:
            return HUDUserDefaultsKeyBinanceDisplayMode
        case .binanceFocusSymbol:
            return HUDUserDefaultsKeyBinanceFocusSymbol
        case .binanceShowSymbol:
            return HUDUserDefaultsKeyBinanceShowSymbol
        case .binanceShowSide:
            return HUDUserDefaultsKeyBinanceShowSide
        case .binanceShowQuantity:
            return HUDUserDefaultsKeyBinanceShowQuantity
        case .binanceShowCurrentPrice:
            return HUDUserDefaultsKeyBinanceShowCurrentPrice
        case .binanceShowEntryPrice:
            return HUDUserDefaultsKeyBinanceShowEntryPrice
        case .binanceShowPnL:
            return HUDUserDefaultsKeyBinanceShowPnL
        case .binanceShowROE:
            return HUDUserDefaultsKeyBinanceShowROE
        case .binanceShowTotalEquity:
            return HUDUserDefaultsKeyBinanceShowTotalEquity
        case .binanceShowFloatingPnL:
            return HUDUserDefaultsKeyBinanceShowFloatingPnL
        case .binanceShowFloatingPnLRate:
            return HUDUserDefaultsKeyBinanceShowFloatingPnLRate
        case .binanceShowTotalROI:
            return HUDUserDefaultsKeyBinanceShowTotalROI
        case .passthroughMode:
            return HUDUserDefaultsKeyPassthroughMode
        case .keepInPlace:
            return HUDUserDefaultsKeyKeepInPlace
        case .hideAtSnapshot:
            return HUDUserDefaultsKeyHideAtSnapshot
        case .usesInvertedColor:
            return HUDUserDefaultsKeyUsesInvertedColor
        case .usesRotation:
            return HUDUserDefaultsKeyUsesRotation
        case .usesLargeFont:
            return HUDUserDefaultsKeyUsesLargeFont
        }
    }

    var title: String {
        switch self {
        case .binanceAccount:
            return NSLocalizedString("Binance Account", comment: "TSSettingsIndex")
        case .binanceUseTestnet:
            return NSLocalizedString("Binance Environment", comment: "TSSettingsIndex")
        case .binanceRefreshInterval:
            return NSLocalizedString("Refresh Interval", comment: "TSSettingsIndex")
        case .binanceDisplayMode:
            return NSLocalizedString("Display Mode", comment: "TSSettingsIndex")
        case .binanceFocusSymbol:
            return NSLocalizedString("Display Symbol", comment: "TSSettingsIndex")
        case .binanceShowSymbol:
            return NSLocalizedString("Show Symbol", comment: "TSSettingsIndex")
        case .binanceShowSide:
            return NSLocalizedString("Show Side", comment: "TSSettingsIndex")
        case .binanceShowQuantity:
            return NSLocalizedString("Show Quantity", comment: "TSSettingsIndex")
        case .binanceShowCurrentPrice:
            return NSLocalizedString("Show Current Price", comment: "TSSettingsIndex")
        case .binanceShowEntryPrice:
            return NSLocalizedString("Show Entry Price", comment: "TSSettingsIndex")
        case .binanceShowPnL:
            return NSLocalizedString("Show PnL", comment: "TSSettingsIndex")
        case .binanceShowROE:
            return NSLocalizedString("Show ROE", comment: "TSSettingsIndex")
        case .binanceShowTotalEquity:
            return NSLocalizedString("Show Total Equity", comment: "TSSettingsIndex")
        case .binanceShowFloatingPnL:
            return NSLocalizedString("Show Floating PnL", comment: "TSSettingsIndex")
        case .binanceShowFloatingPnLRate:
            return NSLocalizedString("Show Floating PnL Rate", comment: "TSSettingsIndex")
        case .binanceShowTotalROI:
            return NSLocalizedString("Show Total ROI", comment: "TSSettingsIndex")
        case .passthroughMode:
            return NSLocalizedString("Pass-through", comment: "TSSettingsIndex")
        case .keepInPlace:
            return NSLocalizedString("Keep In-place", comment: "TSSettingsIndex")
        case .hideAtSnapshot:
            return NSLocalizedString("Hide @snapshot", comment: "TSSettingsIndex")
        case .usesInvertedColor:
            return NSLocalizedString("Appearance", comment: "TSSettingsIndex")
        case .usesRotation:
            return NSLocalizedString("Landscape", comment: "TSSettingsIndex")
        case .usesLargeFont:
            return NSLocalizedString("Size", comment: "TSSettingsIndex")
        }
    }

    var kind: TSSettingItemKind {
        switch self {
        case .binanceAccount, .binanceUseTestnet, .binanceRefreshInterval, .binanceDisplayMode, .binanceFocusSymbol,
             .usesInvertedColor, .usesRotation, .usesLargeFont:
            return .value
        default:
            return .toggle
        }
    }

    func subtitle(highlighted: Bool, restartRequired: Bool) -> String {
        switch self {
        case .binanceAccount:
            return highlighted ? NSLocalizedString("Configured", comment: "TSSettingsIndex") : NSLocalizedString("Not Configured", comment: "TSSettingsIndex")
        case .binanceUseTestnet:
            return highlighted ? NSLocalizedString("Testnet", comment: "TSSettingsIndex") : NSLocalizedString("Mainnet", comment: "TSSettingsIndex")
        case .binanceRefreshInterval:
            return TSSettingsIndex.binanceRefreshIntervalSubtitle()
        case .binanceDisplayMode:
            return highlighted ? NSLocalizedString("Summary", comment: "TSSettingsIndex") : NSLocalizedString("Positions", comment: "TSSettingsIndex")
        case .binanceFocusSymbol:
            return TSSettingsIndex.binanceFocusSymbolSubtitle()
        case .binanceShowSymbol, .binanceShowSide, .binanceShowQuantity, .binanceShowCurrentPrice, .binanceShowEntryPrice, .binanceShowPnL, .binanceShowROE,
             .binanceShowTotalEquity, .binanceShowFloatingPnL, .binanceShowFloatingPnLRate, .binanceShowTotalROI:
            return highlighted ? NSLocalizedString("ON", comment: "TSSettingsIndex") : NSLocalizedString("OFF", comment: "TSSettingsIndex")
        case .passthroughMode:
            if restartRequired {
                return NSLocalizedString("Re-open to apply", comment: "TSSettingsIndex")
            }
            return highlighted ? NSLocalizedString("ON", comment: "TSSettingsIndex") : NSLocalizedString("OFF", comment: "TSSettingsIndex")
        case .keepInPlace, .hideAtSnapshot:
            return highlighted ? NSLocalizedString("ON", comment: "TSSettingsIndex") : NSLocalizedString("OFF", comment: "TSSettingsIndex")
        case .usesInvertedColor:
            return highlighted ? NSLocalizedString("Inverted", comment: "TSSettingsIndex") : NSLocalizedString("Classic", comment: "TSSettingsIndex")
        case .usesRotation:
            return highlighted ? NSLocalizedString("Follow", comment: "TSSettingsIndex") : NSLocalizedString("Hide", comment: "TSSettingsIndex")
        case .usesLargeFont:
            return highlighted ? NSLocalizedString("Large", comment: "TSSettingsIndex") : NSLocalizedString("Standard", comment: "TSSettingsIndex")
        }
    }

    private static func binanceRefreshIntervalSubtitle() -> String {
        let defaults = GetStandardUserDefaults()
        let interval = defaults.integer(forKey: HUDUserDefaultsKeyBinanceRefreshInterval)
        let resolvedInterval = interval > 0 ? interval : 5
        return String(format: NSLocalizedString("%ds", comment: "TSSettingsIndex"), resolvedInterval)
    }

    private static func binanceFocusSymbolSubtitle() -> String {
        let raw = (GetStandardUserDefaults().string(forKey: HUDUserDefaultsKeyBinanceFocusSymbol) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return NSLocalizedString("All", comment: "TSSettingsIndex")
        }
        if raw.hasSuffix("USDT") {
            return String(raw.dropLast(4))
        }
        return raw
    }
}

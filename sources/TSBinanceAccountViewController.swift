import UIKit

@objc protocol TSBinanceAccountViewControllerDelegate: AnyObject {
    func binanceAccountViewControllerDidUpdateCredentials(_ controller: TSBinanceAccountViewController)
}

@objcMembers
final class TSBinanceAccountViewController: UIViewController, UIGestureRecognizerDelegate {
    weak var delegate: TSBinanceAccountViewControllerDelegate?

    private let store = TSBinanceCredentialStore.sharedStore()

    private lazy var scrollView: UIScrollView = {
        let view = UIScrollView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.keyboardDismissMode = .interactive
        return view
    }()

    private lazy var contentStack: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 18
        return stackView
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.text = NSLocalizedString("Enter a read-only USD-M Futures API Key and Secret. Use the buttons below to paste directly from the clipboard.", comment: "TSBinanceAccountViewController")
        return label
    }()

    private lazy var apiKeyField: UITextField = makeTextField(
        placeholder: NSLocalizedString("API Key", comment: "TSBinanceAccountViewController"),
        secure: false
    )

    private lazy var secretField: UITextField = makeTextField(
        placeholder: NSLocalizedString("API Secret", comment: "TSBinanceAccountViewController"),
        secure: false
    )

    private lazy var apiKeyPasteControl: UIView = makePasteControl(
        for: apiKeyField,
        title: NSLocalizedString("Paste API Key", comment: "TSBinanceAccountViewController"),
        action: #selector(pasteAPIKey)
    )

    private lazy var secretPasteControl: UIView = makePasteControl(
        for: secretField,
        title: NSLocalizedString("Paste API Secret", comment: "TSBinanceAccountViewController"),
        action: #selector(pasteSecret)
    )

    private lazy var secretVisibilityButton: UIButton = makeActionButton(
        title: NSLocalizedString("Hide Secret", comment: "TSBinanceAccountViewController"),
        tintColor: view.tintColor,
        action: #selector(toggleSecretVisibility)
    )

    private lazy var clearCredentialsButton: UIButton = makeActionButton(
        title: NSLocalizedString("Clear Saved Credentials", comment: "TSBinanceAccountViewController"),
        tintColor: .systemRed,
        action: #selector(clearSavedCredentials)
    )

    private var hasStoredCredentials: Bool {
        store.hasCredentials()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Binance Account", comment: "TSBinanceAccountViewController")
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(closeEditor)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Save", comment: "TSBinanceAccountViewController"),
            style: .done,
            target: self,
            action: #selector(saveCredentials)
        )

        apiKeyField.pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        secretField.pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)

        apiKeyField.text = store.currentAPIKey()
        if hasStoredCredentials {
            secretField.placeholder = NSLocalizedString("Leave blank to keep current secret", comment: "TSBinanceAccountViewController")
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])

        contentStack.addArrangedSubview(descriptionLabel)
        contentStack.addArrangedSubview(makeFieldSection(
            title: NSLocalizedString("API Key", comment: "TSBinanceAccountViewController"),
            textField: apiKeyField,
            buttons: [apiKeyPasteControl]
        ))
        contentStack.addArrangedSubview(makeFieldSection(
            title: NSLocalizedString("API Secret", comment: "TSBinanceAccountViewController"),
            textField: secretField,
            buttons: [secretPasteControl, secretVisibilityButton]
        ))
        if hasStoredCredentials {
            contentStack.addArrangedSubview(clearCredentialsButton)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if apiKeyField.text?.isEmpty ?? true {
            apiKeyField.becomeFirstResponder()
        } else {
            secretField.becomeFirstResponder()
        }
    }

    private func makeFieldSection(title: String, textField: UITextField, buttons: [UIView]) -> UIView {
        let sectionView = UIView()
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 10

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .label

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(textField)

        let buttonRow = UIStackView(arrangedSubviews: buttons)
        buttonRow.axis = .horizontal
        buttonRow.spacing = 10
        buttonRow.distribution = .fillEqually
        stackView.addArrangedSubview(buttonRow)

        sectionView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: sectionView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: sectionView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: sectionView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: sectionView.bottomAnchor),
        ])
        return sectionView
    }

    private func makeTextField(placeholder: String, secure: Bool) -> UITextField {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.clearButtonMode = .whileEditing
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.keyboardType = .asciiCapable
        textField.textContentType = .oneTimeCode
        textField.isSecureTextEntry = secure
        textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return textField
    }

    private func makeActionButton(title: String, tintColor: UIColor, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(tintColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = tintColor.withAlphaComponent(0.35).cgColor
        button.backgroundColor = tintColor.withAlphaComponent(0.08)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makePasteControl(for textField: UITextField, title: String, action: Selector) -> UIView {
        if #available(iOS 16.0, *) {
            var configuration = UIPasteControl.Configuration()
            configuration.baseBackgroundColor = view.tintColor.withAlphaComponent(0.08)
            configuration.baseForegroundColor = view.tintColor
            configuration.cornerStyle = .large
            configuration.displayMode = .iconAndLabel

            let pasteControl = UIPasteControl(configuration: configuration)
            pasteControl.translatesAutoresizingMaskIntoConstraints = false
            pasteControl.target = textField
            pasteControl.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return pasteControl
        }

        return makeActionButton(title: title, tintColor: view.tintColor, action: action)
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView: UIView? = touch.view
        while let currentView = touchedView {
            if currentView is UIControl || currentView is UITextView {
                return false
            }
            if currentView === apiKeyField || currentView === secretField {
                return false
            }
            touchedView = currentView.superview
        }
        return true
    }

    @objc
    private func closeEditor() {
        dismiss(animated: true)
    }

    @objc
    private func saveCredentials() {
        let apiKey = apiKeyField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secretInput = secretField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let secret = secretInput.isEmpty ? (store.currentSecret() ?? "") : secretInput

        do {
            try store.save(apiKey: apiKey, secret: secret)
            delegate?.binanceAccountViewControllerDidUpdateCredentials(self)
            dismiss(animated: true)
        } catch {
            presentError(error)
        }
    }

    @objc
    private func pasteAPIKey() {
        pasteClipboardText(into: apiKeyField)
    }

    @objc
    private func pasteSecret() {
        pasteClipboardText(into: secretField)
    }

    @objc
    private func toggleSecretVisibility() {
        secretField.isSecureTextEntry.toggle()
        let title = secretField.isSecureTextEntry
            ? NSLocalizedString("Show Secret", comment: "TSBinanceAccountViewController")
            : NSLocalizedString("Hide Secret", comment: "TSBinanceAccountViewController")
        secretVisibilityButton.setTitle(title, for: .normal)
    }

    @objc
    private func clearSavedCredentials() {
        let alertController = UIAlertController(
            title: NSLocalizedString("Clear API Credentials", comment: "TSBinanceAccountViewController"),
            message: NSLocalizedString("This will remove the saved Binance API Key and Secret from the device.", comment: "TSBinanceAccountViewController"),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "TSBinanceAccountViewController"),
            style: .cancel
        ))
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Clear", comment: "TSBinanceAccountViewController"),
            style: .destructive,
            handler: { [weak self] _ in
                self?.performClearCredentials()
            }
        ))
        present(alertController, animated: true)
    }

    private func performClearCredentials() {
        var error: NSError?
        let success = store.clearCredentials(&error)
        guard success else {
            presentError(error ?? NSError(domain: "TSBinanceAccountViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Unable to clear saved credentials.", comment: "TSBinanceAccountViewController")]))
            return
        }

        delegate?.binanceAccountViewControllerDidUpdateCredentials(self)
        dismiss(animated: true)
    }

    private func pasteClipboardText(into textField: UITextField) {
        let wasSecure = textField.isSecureTextEntry
        if wasSecure {
            textField.isSecureTextEntry = false
        }

        if let clipboardText = readPlainTextFromPasteboard() {
            textField.text = clipboardText
            textField.becomeFirstResponder()
            if wasSecure {
                DispatchQueue.main.async {
                    textField.isSecureTextEntry = true
                }
            }
            return
        }

        let previousText = textField.text
        textField.becomeFirstResponder()
        textField.selectAll(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak textField] in
            guard let self = self, let textField = textField else { return }

            let didSendPasteAction = UIApplication.shared.sendAction(
                #selector(UIResponderStandardEditActions.paste(_:)),
                to: textField,
                from: self,
                for: nil
            )

            if wasSecure {
                DispatchQueue.main.async {
                    textField.isSecureTextEntry = true
                }
            }

            guard didSendPasteAction else {
                self.presentPasteAccessError()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak textField] in
                guard let self = self, let textField = textField else { return }
                guard textField.text == previousText || textField.text?.isEmpty == true else { return }
                self.presentPasteAccessError()
            }
        }
    }

    private func readPlainTextFromPasteboard() -> String? {
        let pasteboard = UIPasteboard.general
        let candidateTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "NSStringPboardType",
            "com.apple.traditional-mac-plain-text"
        ]

        var candidates: [String] = []
        if let string = pasteboard.string {
            candidates.append(string)
        }
        if let strings = pasteboard.strings {
            candidates.append(contentsOf: strings)
        }

        for type in candidateTypes {
            if let string = pasteboard.value(forPasteboardType: type) as? String {
                candidates.append(string)
            } else if let data = pasteboard.data(forPasteboardType: type), let string = String(data: data, encoding: .utf8) {
                candidates.append(string)
            }

            let itemSet = IndexSet(integersIn: 0..<max(pasteboard.numberOfItems, 1))
            if let values = pasteboard.values(forPasteboardType: type, inItemSet: itemSet) {
                candidates.append(contentsOf: values.compactMap { pasteboardValueToString($0) })
            }
            if let dataValues = pasteboard.data(forPasteboardType: type, inItemSet: itemSet) {
                candidates.append(contentsOf: dataValues.compactMap { decodePasteboardData($0) })
            }
        }

        for item in pasteboard.items {
            for value in item.values {
                if let string = pasteboardValueToString(value) {
                    candidates.append(string)
                }
            }
        }

        return candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func pasteboardValueToString(_ value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let nsString = value as? NSString {
            return nsString as String
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        if let data = value as? Data {
            return decodePasteboardData(data)
        }
        return nil
    }

    private func decodePasteboardData(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .ascii]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
        }
        return nil
    }

    private func presentError(_ error: Error) {
        let nsError = error as NSError
        let alertController = UIAlertController(
            title: NSLocalizedString("Binance Settings Error", comment: "TSBinanceAccountViewController"),
            message: nsError.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Dismiss", comment: "TSBinanceAccountViewController"),
            style: .cancel
        ))
        present(alertController, animated: true)
    }

    private func presentPasteAccessError() {
        let diagnostics = pasteboardDiagnosticSummary()
        let message = [
            NSLocalizedString("Unable to paste. In iOS Settings, open BinanceHUD and set Paste from Other Apps to Ask or Allow.", comment: "TSBinanceAccountViewController"),
            diagnostics
        ].joined(separator: "\n\n")

        let alertController = UIAlertController(
            title: NSLocalizedString("Binance Settings Error", comment: "TSBinanceAccountViewController"),
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Dismiss", comment: "TSBinanceAccountViewController"),
            style: .cancel
        ))
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Open Settings", comment: "TSBinanceAccountViewController"),
            style: .default,
            handler: { _ in
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(settingsURL, options: [:])
            }
        ))
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Show Diagnostics", comment: "TSBinanceAccountViewController"),
            style: .default,
            handler: { [weak self] _ in
                self?.presentPasteDiagnostics(diagnostics)
            }
        ))
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Copy Diagnostics", comment: "TSBinanceAccountViewController"),
            style: .default,
            handler: { _ in
                UIPasteboard.general.string = diagnostics
            }
        ))
        present(alertController, animated: true)
    }

    private func pasteboardDiagnosticSummary() -> String {
        let pasteboard = UIPasteboard.general
        let items = pasteboard.items
        var lines = [
            "Pasteboard diagnostics:",
            "hasStrings: \(pasteboard.hasStrings)",
            "stringVisible: \(pasteboard.string != nil)",
            "stringsVisible: \(pasteboard.strings?.count ?? -1)",
            "numberOfItems: \(pasteboard.numberOfItems)",
            "items: \(items.count)"
        ]

        let candidateTypes = [
            "public.utf8-plain-text",
            "public.plain-text",
            "NSStringPboardType",
            "com.apple.traditional-mac-plain-text"
        ]
        let itemSet = IndexSet(integersIn: 0..<max(pasteboard.numberOfItems, 1))
        for type in candidateTypes {
            let valueCount = pasteboard.values(forPasteboardType: type, inItemSet: itemSet)?.count ?? 0
            let dataCount = pasteboard.data(forPasteboardType: type, inItemSet: itemSet)?.count ?? 0
            lines.append("\(type): values=\(valueCount), data=\(dataCount)")
        }

        for (index, item) in items.prefix(3).enumerated() {
            let details = item
                .keys
                .sorted()
                .map { key -> String in
                    guard let value = item[key] else {
                        return "\(key)=nil"
                    }
                    if let data = value as? Data {
                        return "\(key)=Data(\(data.count))"
                    }
                    if let string = value as? String {
                        return "\(key)=String(\(string.count))"
                    }
                    if let nsString = value as? NSString {
                        return "\(key)=NSString(\(nsString.length))"
                    }
                    return "\(key)=\(String(describing: type(of: value)))"
                }
                .joined(separator: ", ")
            lines.append("item[\(index)]: \(details)")
        }

        return lines.joined(separator: "\n")
    }

    private func presentPasteDiagnostics(_ diagnostics: String) {
        let diagnosticsViewController = PasteDiagnosticsViewController(text: diagnostics)
        let navigationController = UINavigationController(rootViewController: diagnosticsViewController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }
}

private final class PasteDiagnosticsViewController: UIViewController {
    private let text: String
    private let textView = UITextView()

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.text = ""
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Pasteboard Diagnostics", comment: "PasteDiagnosticsViewController")
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Copy Diagnostics", comment: "PasteDiagnosticsViewController"),
            style: .plain,
            target: self,
            action: #selector(copyDiagnostics)
        )

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.text = text
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .secondarySystemBackground
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @objc
    private func close() {
        dismiss(animated: true)
    }

    @objc
    private func copyDiagnostics() {
        UIPasteboard.general.string = text
    }
}

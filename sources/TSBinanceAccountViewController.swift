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
        label.text = NSLocalizedString("Enter a read-only USD-M Futures API Key and Secret. Tap Paste to fill each field from the clipboard.", comment: "TSBinanceAccountViewController")
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

    // UIPasteControl performs a privileged, one-time paste granted by the user's tap on the
    // control itself. This bypasses the per-app "Paste from Other Apps" policy (which this
    // unsandboxed build is treated as denying), so it works even though the standard edit-menu
    // "Paste" reads back empty. The targets must be retained here because UIPasteControl.target
    // is a weak reference.
    private lazy var apiKeyPasteTarget: CredentialPasteTarget = makePasteTarget(for: apiKeyField)
    private lazy var secretPasteTarget: CredentialPasteTarget = makePasteTarget(for: secretField)

    private lazy var apiKeyPasteView: UIView = makePasteView(
        target: apiKeyPasteTarget,
        manualAction: #selector(pasteAPIKeyManually)
    )
    private lazy var secretPasteView: UIView = makePasteView(
        target: secretPasteTarget,
        manualAction: #selector(pasteSecretManually)
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

    private lazy var positionDiagnosticsButton: UIButton = makeActionButton(
        title: NSLocalizedString("Show Position Diagnostics", comment: "TSBinanceAccountViewController"),
        tintColor: view.tintColor,
        action: #selector(showPositionDiagnostics)
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
            buttons: [apiKeyPasteView]
        ))
        contentStack.addArrangedSubview(makeFieldSection(
            title: NSLocalizedString("API Secret", comment: "TSBinanceAccountViewController"),
            textField: secretField,
            buttons: [secretPasteView, secretVisibilityButton]
        ))
        if hasStoredCredentials {
            contentStack.addArrangedSubview(positionDiagnosticsButton)
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

    private func makeFieldSection(title: String, textField: UITextField, buttons: [UIView] = []) -> UIView {
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

        if !buttons.isEmpty {
            let buttonRow = UIStackView(arrangedSubviews: buttons)
            buttonRow.axis = .horizontal
            buttonRow.spacing = 10
            buttonRow.distribution = .fillEqually
            stackView.addArrangedSubview(buttonRow)
        }

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

    private func makePasteTarget(for field: UITextField) -> CredentialPasteTarget {
        let target = CredentialPasteTarget()
        target.textField = field
        target.onFailure = { [weak self] in self?.presentPasteFailure() }
        return target
    }

    private func makePasteView(target: CredentialPasteTarget, manualAction: Selector) -> UIView {
        if #available(iOS 16.0, *) {
            let configuration = UIPasteControl.Configuration()
            configuration.baseBackgroundColor = view.tintColor.withAlphaComponent(0.08)
            configuration.baseForegroundColor = view.tintColor
            configuration.cornerStyle = .large
            configuration.displayMode = .iconAndLabel

            let pasteControl = UIPasteControl(configuration: configuration)
            pasteControl.translatesAutoresizingMaskIntoConstraints = false
            pasteControl.target = target
            pasteControl.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return pasteControl
        }

        // iOS 15 and earlier predate UIPasteControl and the cross-app paste policy, so a
        // plain button reading the general pasteboard is sufficient there.
        return makeActionButton(
            title: NSLocalizedString("Paste", comment: "TSBinanceAccountViewController"),
            tintColor: view.tintColor,
            action: manualAction
        )
    }

    @objc
    private func pasteAPIKeyManually() {
        manualPaste(into: apiKeyField)
    }

    @objc
    private func pasteSecretManually() {
        manualPaste(into: secretField)
    }

    private func manualPaste(into field: UITextField) {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            presentPasteFailure()
            return
        }
        field.text = text
        field.sendActions(for: .editingChanged)
    }

    private func presentPasteFailure() {
        let alertController = UIAlertController(
            title: NSLocalizedString("Nothing to Paste", comment: "TSBinanceAccountViewController"),
            message: NSLocalizedString("The clipboard is empty or its contents could not be read. Copy your API Key or Secret again, then tap Paste.", comment: "TSBinanceAccountViewController"),
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(
            title: NSLocalizedString("Dismiss", comment: "TSBinanceAccountViewController"),
            style: .cancel
        ))
        present(alertController, animated: true)
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

    @objc
    private func showPositionDiagnostics() {
        let diagnostics = TSBinancePositionService.sharedService().diagnosticsText()
        presentDiagnostics(
            diagnostics,
            title: NSLocalizedString("Binance Diagnostics", comment: "TSBinanceAccountViewController")
        )
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

    private func presentDiagnostics(_ diagnostics: String, title: String) {
        let diagnosticsViewController = DiagnosticsViewController(text: diagnostics, title: title)
        let navigationController = UINavigationController(rootViewController: diagnosticsViewController)
        navigationController.modalPresentationStyle = .formSheet
        present(navigationController, animated: true)
    }
}

private final class CredentialPasteTarget: UIResponder {
    weak var textField: UITextField?
    var onFailure: (() -> Void)?

    override init() {
        super.init()
        // Declaring an accepting configuration is what enables the UIPasteControl whenever the
        // clipboard holds text, and it scopes the privileged paste to plain strings.
        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
    }

    override func paste(itemProviders: [NSItemProvider]) {
        guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            DispatchQueue.main.async { [weak self] in self?.onFailure?() }
            return
        }

        provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let text = (object as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                    self.onFailure?()
                    return
                }
                self.textField?.text = text
                self.textField?.sendActions(for: .editingChanged)
            }
        }
    }
}

private final class DiagnosticsViewController: UIViewController {
    private let text: String
    private let displayTitle: String
    private let textView = UITextView()

    init(text: String, title: String) {
        self.text = text
        self.displayTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.text = ""
        self.displayTitle = ""
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = displayTitle
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

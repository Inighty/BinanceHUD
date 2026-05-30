import UIKit

@objc protocol TSBinanceAccountViewControllerDelegate: AnyObject {
    func binanceAccountViewControllerDidUpdateCredentials(_ controller: TSBinanceAccountViewController)
}

@objcMembers
final class TSBinanceAccountViewController: UIViewController {
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
        secure: true
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
        title: NSLocalizedString("Show Secret", comment: "TSBinanceAccountViewController"),
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
        textField.textContentType = nil
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

    private func makePasteControl(for _: UITextField, title: String, action: Selector) -> UIView {
        return makeActionButton(title: title, tintColor: view.tintColor, action: action)
    }

    @objc
    private func dismissKeyboard() {
        view.endEditing(true)
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
        dismissKeyboard()

        guard let clipboardText = UIPasteboard.general.string, !clipboardText.isEmpty else {
            presentError(NSError(
                domain: "TSBinanceAccountViewController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("Clipboard is empty or paste access was denied.", comment: "TSBinanceAccountViewController")]
            ))
            return
        }

        textField.text = clipboardText
        textField.becomeFirstResponder()
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
}

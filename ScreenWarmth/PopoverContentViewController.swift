import AppKit

final class PopoverContentViewController: NSViewController {

    private let gammaController: GammaController
    private var onQuit: (() -> Void)?

    private let brightnessLabel = NSTextField(labelWithString: "Brightness")
    private let brightnessSlider = NSSlider(value: 70, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let blueLightLabel = NSTextField(labelWithString: "Blue light (Normal ← → Red)")
    private let blueLightSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let enableCheckbox = NSButton(checkboxWithTitle: "Enable", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    init(gammaController: GammaController, onQuit: (() -> Void)?) {
        self.gammaController = gammaController
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadFromController()
    }

    private func setupUI() {
        brightnessLabel.translatesAutoresizingMaskIntoConstraints = false
        brightnessSlider.translatesAutoresizingMaskIntoConstraints = false
        blueLightLabel.translatesAutoresizingMaskIntoConstraints = false
        blueLightSlider.translatesAutoresizingMaskIntoConstraints = false
        enableCheckbox.translatesAutoresizingMaskIntoConstraints = false
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        blueLightSlider.target = self
        blueLightSlider.action = #selector(blueLightChanged)
        enableCheckbox.target = self
        enableCheckbox.action = #selector(enableChanged)
        quitButton.target = self
        quitButton.action = #selector(quitTapped)

        view.addSubview(brightnessLabel)
        view.addSubview(brightnessSlider)
        view.addSubview(blueLightLabel)
        view.addSubview(blueLightSlider)
        view.addSubview(enableCheckbox)
        view.addSubview(quitButton)

        NSLayoutConstraint.activate([
            brightnessLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            brightnessLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            brightnessSlider.topAnchor.constraint(equalTo: brightnessLabel.bottomAnchor, constant: 4),
            brightnessSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            brightnessSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            blueLightLabel.topAnchor.constraint(equalTo: brightnessSlider.bottomAnchor, constant: 12),
            blueLightLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            blueLightSlider.topAnchor.constraint(equalTo: blueLightLabel.bottomAnchor, constant: 4),
            blueLightSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            blueLightSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            enableCheckbox.topAnchor.constraint(equalTo: blueLightSlider.bottomAnchor, constant: 14),
            enableCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            quitButton.topAnchor.constraint(equalTo: enableCheckbox.bottomAnchor, constant: 12),
            quitButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            quitButton.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ])
    }

    private func loadFromController() {
        brightnessSlider.doubleValue = gammaController.brightness * 100
        blueLightSlider.doubleValue = gammaController.blueLightReduction * 100
        enableCheckbox.state = gammaController.isEnabled ? .on : .off
    }

    @objc private func brightnessChanged() {
        gammaController.brightness = brightnessSlider.doubleValue / 100
        if gammaController.isEnabled {
            gammaController.applyToAllDisplays()
        }
    }

    @objc private func blueLightChanged() {
        gammaController.blueLightReduction = blueLightSlider.doubleValue / 100
        if gammaController.isEnabled {
            gammaController.applyToAllDisplays()
        }
    }

    @objc private func enableChanged() {
        let enable = enableCheckbox.state == .on
        if enable {
            gammaController.saveOriginalsForAllCurrentDisplays()
            gammaController.isEnabled = true
            gammaController.applyToAllDisplays()
        } else {
            gammaController.isEnabled = false
            gammaController.restoreAllDisplays()
        }
    }

    @objc private func quitTapped() {
        onQuit?()
    }
}

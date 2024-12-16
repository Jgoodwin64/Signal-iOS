//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MultipeerConnectivity
import SignalServiceKit
import SignalUI

class ProvisioningTransferQRCodeViewController: ProvisioningBaseViewController {

    private var qrCodeWrapperView: UIView!
    private var qrCodeWrapperViewSizeConstraints: [NSLayoutConstraint]!
    private var qrCodeView: QRCodeView!

    // MARK: -

    private func populateViewContents() {
        // MARK: Views

        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: OWSLocalizedString(
            "DEVICE_TRANSFER_QRCODE_TITLE",
            comment: "The title for the device transfer qr code view"
        ))

        let explanationLabel = self.createExplanationLabel(explanationText: OWSLocalizedString(
            "DEVICE_TRANSFER_QRCODE_EXPLANATION",
            comment: "The explanation for the device transfer qr code view"
        ))
        explanationLabel.font = .dynamicTypeBody
        explanationLabel.numberOfLines = 0

        qrCodeWrapperView = UIView()
        qrCodeWrapperView.backgroundColor = .ows_gray02
        qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 48)
        qrCodeWrapperView.layer.cornerRadius = 24

        qrCodeView = QRCodeView()

        let explanationLabel2 = self.createExplanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_QRCODE_EXPLANATION2",
            comment: "The second explanation for the device transfer qr code view")
        )
        explanationLabel2.font = .dynamicTypeBody
        explanationLabel2.numberOfLines = 0

        let helpButton = self.linkButton(
            title: OWSLocalizedString(
                "DEVICE_TRANSFER_QRCODE_NOT_SEEING",
                comment: "A prompt to provide further explanation if the user is not seeing the transfer on both devices."
            ),
            selector: #selector(didTapHelp)
        )
        helpButton.button.titleLabel?.textAlignment = .center
        helpButton.button.titleLabel?.numberOfLines = 0
        helpButton.button.titleLabel?.lineBreakMode = .byWordWrapping

        let cancelButton = self.linkButton(
            title: CommonStrings.cancelButton,
            selector: #selector(didTapCancel)
        )

        // MARK: Layout

        qrCodeWrapperView.addSubview(qrCodeView)
        qrCodeView.autoPinEdgesToSuperviewMargins()

        let qrCodeTopSpacer = UIView()
        let qrCodeBottomSpacer = UIView()

        let contentStack = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            qrCodeTopSpacer,
            qrCodeWrapperView,
            UIView.spacer(withHeight: 18),
            explanationLabel2,
            qrCodeBottomSpacer,
            helpButton,
            cancelButton
        ])

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = 12

        primaryView.addSubview(contentStack)
        contentStack.autoPinEdgesToSuperviewMargins()

        qrCodeTopSpacer.autoMatch(.height, to: .height, of: qrCodeBottomSpacer, withMultiplier: 0.33)

        /// Constraint constants managed by `adjustLayoutForCurrentOrientation`.
        qrCodeWrapperViewSizeConstraints = [
            qrCodeWrapperView.autoSetDimension(.height, toSize: 0),
            qrCodeWrapperView.autoSetDimension(.width, toSize: 0),
        ]

        adjustLayoutForCurrentOrientation()
    }

    @objc
    private func adjustLayoutForCurrentOrientation() {
        if UIDevice.current.orientation.isPortrait {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 48)
            qrCodeWrapperViewSizeConstraints.forEach { $0.constant = 352 }
        } else {
            qrCodeWrapperView.layoutMargins = UIEdgeInsets(margin: 24)
            qrCodeWrapperViewSizeConstraints.forEach { $0.constant = 220 }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        populateViewContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adjustLayoutForCurrentOrientation),
            name: UIDevice.orientationDidChangeNotification,
            object: UIDevice.current
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.addObserver(self)

        Task { @MainActor in
            do {
                let url = try AppEnvironment.shared.deviceTransferServiceRef.startAcceptingTransfersFromOldDevices(
                    mode: .linked // TODO: .primary
                )

                qrCodeView.setQRCode(url: url)
            } catch {
                owsFailDebug("error \(error)")
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        AppEnvironment.shared.deviceTransferServiceRef.removeObserver(self)
        AppEnvironment.shared.deviceTransferServiceRef.stopAcceptingTransfersFromOldDevices()
    }

    // MARK: - Events

    weak var permissionActionSheetController: ActionSheetController?

    @objc
    private func didTapHelp() {
        let turnOnView = TurnOnPermissionView(
            title: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_TITLE",
                comment: "Title for local network permission action sheet"
            ),
            message: OWSLocalizedString(
                "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_BODY",
                comment: "Body for local network permission action sheet"
            ),
            steps: [
                .init(
                    icon: #imageLiteral(resourceName: "settings-app-icon-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_ONE",
                        comment: "First step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: UIImage(resource: UIApplication.shared.currentAppIcon.previewImageResource),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_TWO",
                        comment: "Second step for local network permission action sheet"
                    )
                ),
                .init(
                    icon: UIImage(imageLiteralResourceName: "toggle-32"),
                    text: OWSLocalizedString(
                        "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_STEP_THREE",
                        comment: "Third step for local network permission action sheet"
                    )
                )
            ],
            button: primaryButton(
                title: OWSLocalizedString(
                    "LOCAL_NETWORK_PERMISSION_ACTION_SHEET_NEED_HELP",
                    comment: "A button asking the user if they need further help getting their transfer working."
                ),
                selector: #selector(didTapContactSupport)
            )
        )

        let actionSheetController = ActionSheetController()
        permissionActionSheetController = actionSheetController
        actionSheetController.customHeader = turnOnView
        actionSheetController.isCancelable = true
        presentActionSheet(actionSheetController)
    }

    @objc
    private func didTapCancel() {
        Logger.info("")

        guard let navigationController = navigationController else {
            return owsFailDebug("unexpectedly missing nav controller")
        }

        provisioningController.pushTransferChoiceView(onto: navigationController)
    }

    @objc
    private func didTapContactSupport() {
        Logger.info("")

        permissionActionSheetController?.dismiss(animated: true)
        permissionActionSheetController = nil

        ContactSupportAlert.presentStep2(
            emailSupportFilter: "Signal iOS Transfer",
            fromViewController: self
        )
    }

    override func shouldShowBackButton() -> Bool {
        // Never show the back button here
        return false
    }
}

extension ProvisioningTransferQRCodeViewController: DeviceTransferServiceObserver {
    func deviceTransferServiceDiscoveredNewDevice(peerId: MCPeerID, discoveryInfo: [String: String]?) {}

    func deviceTransferServiceDidStartTransfer(progress: Progress) {
        provisioningController.accountTransferInProgress(fromViewController: self, progress: progress)
    }

    func deviceTransferServiceDidEndTransfer(error: DeviceTransferService.Error?) {
        if let error = error {
            owsFailDebug("unexpected error while rendering QR code \(error)")
        }
    }

    func deviceTransferServiceDidRequestAppRelaunch() {
        owsFail("Relaunch not supported for provisioning; only on the receiving device during transfer")
    }
}

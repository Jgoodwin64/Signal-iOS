//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupThreadMergeChatUpdateArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let interactionStore: any InteractionStore

    init(interactionStore: any InteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archive(
        infoMessage: TSInfoMessage,
        thread: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: any DBReadTransaction
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ errorType: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                errorType,
                infoMessage.uniqueInteractionId,
                line: line
            )])
        }

        guard
            let threadMergePhoneNumberString = infoMessage.threadMergePhoneNumber,
            let threadMergePhoneNumber = E164(threadMergePhoneNumberString)
        else {
            return .skippableChatUpdate(.legacyInfoMessage(.threadMergeWithoutPhoneNumber))
        }

        guard let mergedContactAddress = (thread as? TSContactThread)?.contactAddress.asSingleServiceIdBackupAddress() else {
            return messageFailure(.threadMergeUpdateMissingAuthor)
        }

        guard let threadRecipientId = context.recipientContext[.contact(mergedContactAddress)] else {
            return messageFailure(.referencedRecipientIdMissing(.contact(mergedContactAddress)))
        }

        var chatUpdateMessage = BackupProto.ChatUpdateMessage()
        chatUpdateMessage.update = .threadMerge(BackupProto.ThreadMergeChatUpdate(
            previousE164: threadMergePhoneNumber.uint64Value
        ))

        let interactionArchiveDetails = Details(
            author: threadRecipientId,
            directionalDetails: .directionless(BackupProto.ChatItem.DirectionlessMessageDetails()),
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage)
        )

        return .success(interactionArchiveDetails)
    }

    // MARK: -

    func restoreThreadMergeChatUpdate(
        _ threadMergeUpdateProto: BackupProto.ThreadMergeChatUpdate,
        chatItem: BackupProto.ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: any DBWriteTransaction
    ) -> RestoreChatUpdateMessageResult {
        func invalidProtoData(
            _ error: RestoreFrameError.ErrorType.InvalidProtoDataError,
            line: UInt = #line
        ) -> RestoreChatUpdateMessageResult {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(error),
                chatItem.id,
                line: line
            )])
        }

        guard let previousE164 = E164(threadMergeUpdateProto.previousE164) else {
            return invalidProtoData(.invalidE164(protoClass: BackupProto.ThreadMergeChatUpdate.self))
        }

        guard case .contact(let mergedThread) = chatThread.threadType else {
            return invalidProtoData(.threadMergeUpdateNotFromContact)
        }

        let threadMergeInfoMessage: TSInfoMessage = .makeForThreadMerge(
            mergedThread: mergedThread,
            previousE164: previousE164.stringValue
        )
        interactionStore.insertInteraction(threadMergeInfoMessage, tx: tx)

        return .success(())
    }
}

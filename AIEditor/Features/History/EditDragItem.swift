import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Объявлен в `project.yml` (`UTExportedTypeDeclarations`).
    static let editReference = UTType(exportedAs: "com.example.aieditor.edit-reference")
}

/// Что переносится при перетаскивании правки: только id, не содержимое.
/// Свой тип, а не `UUID`/`String`: в сайдбар не упадёт случайный текст из другого
/// приложения, а другое приложение не примет перенос как текст.
struct EditDragItem: Codable, Hashable, Sendable, Transferable {
    let editId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .editReference)
    }
}

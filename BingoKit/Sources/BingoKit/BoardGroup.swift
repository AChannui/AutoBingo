import Foundation

/// A named set of saved boards that can be put into play together (e.g. "Tuesday night").
/// A board can belong to any number of groups.
public struct BoardGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// In the order the boards were added to the group.
    public var boardIDs: [UUID]

    public init(id: UUID = UUID(), name: String, boardIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.boardIDs = boardIDs
    }

    public func contains(_ boardID: UUID) -> Bool { boardIDs.contains(boardID) }
}

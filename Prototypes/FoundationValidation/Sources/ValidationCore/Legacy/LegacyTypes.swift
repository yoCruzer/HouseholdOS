import Foundation
// Raw representations match the accepted baseline; these are not candidate schema changes.
enum CaptureSource: String { case manual, photoLibrary, camera }
enum ItemStatus: String { case active, archived }
enum MediaOwnerKind: String { case draft, item }
enum DefaultHousehold {
    static let id = UUID(uuidString: "9D723A56-C65F-4BB4-BF65-1C99C565204D")!
}

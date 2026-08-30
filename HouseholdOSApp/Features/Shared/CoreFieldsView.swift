import SwiftUI

struct CoreFieldsView: View {
    @Binding var name: String
    @Binding var categoryID: UUID?
    @Binding var locationID: UUID?
    @Binding var note: String
    @Binding var newLocationName: String

    let nameIsRequired: Bool
    let addLocation: () -> Void

    @EnvironmentObject private var library: ItemLibraryService

    var body: some View {
        Section("Basics") {
            TextField(nameIsRequired ? "Name (required)" : "Name", text: $name)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("record.name")

            Picker("Category", selection: $categoryID) {
                Text("Uncategorized").tag(UUID?.none)
                ForEach(library.displayCategories, id: \.id) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
            .accessibilityIdentifier("record.category")

            Picker("Location", selection: $locationID) {
                Text("No location").tag(UUID?.none)
                ForEach(library.displayLocations, id: \.id) { location in
                    Text(location.name).tag(Optional(location.id))
                }
            }
            .accessibilityIdentifier("record.location")
        }

        Section("Add a location") {
            HStack {
                TextField("e.g. Hall closet", text: $newLocationName)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("record.newLocation")
                Button("Add", action: addLocation)
                    .disabled(
                        newLocationName
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                    .accessibilityIdentifier("record.addLocation")
            }
        }

        Section("Notes") {
            TextField("Optional notes", text: $note, axis: .vertical)
                .lineLimit(3 ... 8)
                .accessibilityIdentifier("record.note")
        }
    }
}

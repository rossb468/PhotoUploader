import AppKit
import SwiftUI

struct MetadataFormView: View {
    @Binding var item: LibraryItem
    let index: Int
    let total: Int
    let isFirst: Bool
    let isLast: Bool
    let onLoadExif: () -> Void
    let onPrev: () -> Void
    let onNext: () -> Void
    let onSave: () -> Void
    let onPublish: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    /// Groups render in this order; any group name not listed here (there
    /// shouldn't be one, but metadata is open-ended) falls in afterward.
    private static let groupOrder = ["Camera", "Exposure", "Date", "Location"]
    private static let groupIcons: [String: String] = [
        "Camera": "camera", "Exposure": "dial.medium", "Date": "calendar", "Location": "location",
    ]

    var body: some View {
        VStack(spacing: 0) {
            preview

            Form {
                Section {
                    TextField("Title", text: $item.title)
                        .textFieldStyle(.roundedBorder)
                    TextField("Caption", text: $item.caption, axis: .vertical)
                        .lineLimit(2...5)
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                    DatePicker("Post Date", selection: $item.date, displayedComponents: .date)
                } header: {
                    Label("Description", systemImage: "text.alignleft")
                }

                ForEach(orderedGroups, id: \.self) { group in
                    Section {
                        ForEach(fields(in: group)) { field in
                            MetadataCheckRow(label: field.label, value: field.value, isPublished: publishBinding(for: field.key))
                        }
                    } header: {
                        Label(group, systemImage: Self.groupIcons[group] ?? "tag")
                    } footer: {
                        if group == "Location" && fields(in: group).contains(where: { $0.key == "location" }) {
                            Text("Published on the photo's page unless you uncheck it — worth knowing if you'd rather not share where it was taken.")
                        }
                    }
                }

                if !item.metadataFields.isEmpty {
                    Text("Extracted automatically and read-only. Check a field to publish it on the photo's page — only what the site showed before is checked by default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !fileInfoFields.isEmpty {
                    Section {
                        ForEach(fileInfoFields) { field in
                            LabeledContent(field.label, value: field.value)
                                .textSelection(.enabled)
                        }
                    } header: {
                        Label("File Info", systemImage: "info.circle")
                    } footer: {
                        Text("For your reference only — never published.")
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            stepControls
        }
        .onAppear {
            if !item.exifLoaded {
                onLoadExif()
            }
        }
        .confirmationDialog(
            "Delete this photo from the site?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes its page and images from photography/. This can't be undone from within the app.")
        }
    }

    // MARK: - Grouping

    private var orderedGroups: [String] {
        let present = Set(item.metadataFields.map(\.group))
        let known = Self.groupOrder.filter { present.contains($0) }
        let unknown = present.subtracting(Self.groupOrder).sorted()
        return known + unknown
    }

    private func fields(in group: String) -> [MetadataField] {
        item.metadataFields.filter { $0.group == group }
    }

    private func publishBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { item.publishedKeys.contains(key) },
            set: { newValue in
                if newValue {
                    item.publishedKeys.insert(key)
                } else {
                    item.publishedKeys.remove(key)
                }
            }
        )
    }

    // MARK: - File Info (local only, never published)

    private var fileInfoFields: [MetadataField] {
        guard let url = item.fileInfoURL else { return [] }
        return FileInfoReader.read(url: url, width: item.width, height: item.height)
    }

    private var preview: some View {
        Group {
            if let url = item.previewURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.06))
    }

    private var stepControls: some View {
        HStack {
            Button {
                onPrev()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(isFirst)

            Spacer()

            if item.isExisting {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    onSave()
                } label: {
                    Label("Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!item.isDirty)
            } else {
                Button {
                    onPublish()
                } label: {
                    Label("Publish This Photo", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            Button {
                onNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(isLast)
        }
        .padding(12)
    }
}

/// One read-only extracted metadata value with a checkbox controlling
/// whether it publishes.
private struct MetadataCheckRow: View {
    let label: String
    let value: String
    @Binding var isPublished: Bool

    var body: some View {
        Toggle(isOn: $isPublished) {
            HStack {
                Text(label)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
            }
        }
        .toggleStyle(.checkbox)
    }
}

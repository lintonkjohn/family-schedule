import SwiftUI
import SwiftData
import PhotosUI

/// Edit a person's name, color and photo.
struct MemberEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let member: Member

    @State private var name: String
    @State private var colorHex: String
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmDelete = false

    init(member: Member) {
        self.member = member
        _name = State(initialValue: member.name)
        _colorHex = State(initialValue: member.colorHex)
        _photoData = State(initialValue: member.photoData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        MemberAvatar(name: name.isEmpty ? "?" : name, colorHex: colorHex, photoData: photoData, size: 110)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
                    }
                    if photoData != nil {
                        Button("Remove photo", systemImage: "trash", role: .destructive) { photoData = nil }
                    }
                }

                Section("Name") {
                    TextField("Name", text: $name)
                }

                Section("Color") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(ActivityDraft.palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: colorHex == hex ? 3 : 0))
                                    .onTapGesture { colorHex = hex }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button("Delete person", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Their activities are kept and moved to \"No person\".")
                }
            }
            .navigationTitle("Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        photoData = FamilyPhotoStore.downsized(data, maxSide: 400)
                    }
                }
            }
            .confirmationDialog("Delete \(member.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    let uid = member.uid
                    let acts = member.activities
                    context.delete(member)
                    try? context.save()
                    FamilySync.shared.delete(uids: [uid], thenPush: acts)
                    dismiss()
                }
            }
        }
    }

    private func save() {
        member.name = name.trimmingCharacters(in: .whitespaces)
        member.colorHex = colorHex
        member.photoData = photoData
        try? context.save()
        FamilySync.shared.push(member: member)
        Task { await NotificationScheduler.reschedule(context: context) }
        dismiss()
    }
}

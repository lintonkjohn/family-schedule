import SwiftUI
import PhotosUI

/// Dashboard hero: family photo, greeting and this week's count.
struct FamilyHeader: View {
    let weekCount: Int
    let members: [Member]

    @AppStorage("familyTitle") private var title = "Linton's Family"
    @State private var photo: UIImage? = FamilyPhotoStore.load() ?? UIImage(named: "FamilyPhoto")
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        Color.clear
            .frame(height: 240)
            .overlay {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: "#2563EB"), Color(hex: "#9333EA")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image(systemName: "figure.2.and.child.holdinghands")
                                .font(.system(size: 80))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                        Text(title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("\(Date.now, format: .dateTime.weekday(.wide).month().day()) · \(weekCount) this week")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    HStack(spacing: -10) {
                        ForEach(members.prefix(4)) { MemberAvatar(member: $0, size: 36) }
                    }
                }
                .padding(20)
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    Button("Choose family photo", systemImage: "photo") { showPicker = true }
                    if photo != nil {
                        Button("Use default photo", systemImage: "arrow.uturn.backward", role: .destructive) {
                            FamilyPhotoStore.remove()
                            photo = UIImage(named: "FamilyPhoto")
                        }
                    }
                    Button("Rename", systemImage: "pencil") {
                        newTitle = title
                        renaming = true
                    }
                } label: {
                    Image(systemName: photo == nil ? "camera.fill" : "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        FamilyPhotoStore.save(data)
                        photo = FamilyPhotoStore.load() ?? UIImage(named: "FamilyPhoto")
                    }
                    pickerItem = nil
                }
            }
            .alert("Family name", isPresented: $renaming) {
                TextField("e.g. The Johns", text: $newTitle)
                Button("Save") {
                    let t = newTitle.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { title = t }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

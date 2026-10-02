import SwiftUI
import UIKit

// Shared file — family photo storage and member avatars.

enum FamilyPhotoStore {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("family.jpg")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ data: Data) {
        guard let url, let small = downsized(data, maxSide: 1600) else { return }
        try? small.write(to: url, options: .atomic)
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Resizes an image so its longest side is at most `maxSide` pixels and returns JPEG data.
    static func downsized(_ data: Data, maxSide: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

struct MemberAvatar: View {
    let name: String
    let colorHex: String
    let photoData: Data?
    var size: CGFloat = 32

    init(name: String, colorHex: String, photoData: Data?, size: CGFloat = 32) {
        self.name = name
        self.colorHex = colorHex
        self.photoData = photoData
        self.size = size
    }

    init(member: Member, size: CGFloat = 32) {
        self.init(name: member.name, colorHex: member.colorHex, photoData: member.photoData, size: size)
    }

    var body: some View {
        Group {
            if let photoData, let ui = UIImage(data: photoData) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(hex: colorHex)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: size > 40 ? 3 : 1.5))
    }
}

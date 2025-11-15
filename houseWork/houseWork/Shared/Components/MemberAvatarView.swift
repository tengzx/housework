//
//  MemberAvatarView.swift
//  houseWork
//
//  Renders a household member avatar, prioritizing remote images when available.
//

import SwiftUI

@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private var storage: [UUID: Image] = [:]
    
    func image(for id: UUID) -> Image? {
        storage[id]
    }
    
    func set(_ image: Image, for id: UUID) {
        storage[id] = image
    }
}

struct MemberAvatarView: View {
    let member: HouseholdMember
    var size: CGFloat = 36
    @State private var cachedImage: Image?
    
    var body: some View {
        ZStack {
            Circle()
                .fill(member.avatarColor)
            avatarContent
        }
        .frame(width: size, height: size)
    }
    
    @ViewBuilder
    private var avatarContent: some View {
        if #available(iOS 15.0, *), let url = member.avatarURL {
            AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .onAppear {
                            cachedImage = image
                            AvatarImageCache.shared.set(image, for: member.id)
                        }
                case .failure:
                    cachedImageView
                case .empty:
                    cachedImageView
                @unknown default:
                    cachedImageView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsView
        }
    }
    
    @ViewBuilder
    private var cachedImageView: some View {
        if let cachedImage {
            cachedImage
                .resizable()
                .scaledToFill()
        } else if let image = AvatarImageCache.shared.image(for: member.id) {
            image
                .resizable()
                .scaledToFill()
                .onAppear {
                    cachedImage = image
                }
        } else {
            initialsView
        }
    }
    
    private var initialsView: some View {
        Text(member.initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundColor(.white)
    }
}

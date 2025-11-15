//
//  MemberAvatarView.swift
//  houseWork
//
//  Renders a household member avatar, prioritizing remote images when available.
//

import SwiftUI

struct MemberAvatarView: View {
    let member: HouseholdMember
    var size: CGFloat = 36
    
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
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    initialsView
                case .empty:
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                @unknown default:
                    initialsView
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
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

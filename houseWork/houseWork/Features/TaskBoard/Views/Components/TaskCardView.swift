//
//  TaskCardView.swift
//  houseWork
//
//  Card UI used inside Task Board lists.
//

import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    var primaryButton: TaskCardButton?
    var secondaryButton: TaskCardButton?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                    Text(task.details)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ScoreBadge(score: task.score)
            }
            
            HStack {
                Label(task.roomTag, systemImage: "tag.fill")
                    .font(.caption)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                Text(task.dueDate, style: .time)
                    .font(.caption)
                    .foregroundStyle(task.dueDate < Date() && task.status != .completed ? Color.red : .secondary)
            }
            
            MemberAvatarStack(members: task.assignedMembers)
            
            if primaryButton != nil || secondaryButton != nil {
                HStack {
                    if let button = primaryButton {
                        TaskCardButtonView(configuration: button)
                    }
                    if let button = secondaryButton {
                        TaskCardButtonView(configuration: button)
                    }
                }
            }
        }
        .padding()
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

struct TaskCardButton {
    enum Style {
        case borderedProminent
        case bordered
    }
    
    let title: String
    let systemImage: String
    let style: Style
    let action: () -> Void
}

private struct TaskCardButtonView: View {
    let configuration: TaskCardButton
    
    var body: some View {
        Button(action: configuration.action) {
            Label(configuration.title, systemImage: configuration.systemImage)
                .font(.subheadline.bold())
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(buttonStyle)
    }
    
    private var buttonStyle: some ButtonStyle {
        switch configuration.style {
        case .borderedProminent:
            return CapsuleButtonStyle(isProminent: true)
        case .bordered:
            return CapsuleButtonStyle(isProminent: false)
        }
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    var isProminent: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isProminent ? Color.accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isProminent ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct MemberAvatarStack: View {
    var members: [HouseholdMember]
    
    var body: some View {
        HStack(spacing: -8) {
            if members.isEmpty {
                Text("Unassigned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(members.prefix(3)).indices, id: \.self) { index in
                    let member = members[index]
                    Text(member.initials)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(member.accentColor, in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .zIndex(Double(members.count - index))
                }
                if members.count > 3 {
                    Text("+\(members.count - 3)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.1), in: Circle())
                }
            }
            Spacer()
        }
    }
}

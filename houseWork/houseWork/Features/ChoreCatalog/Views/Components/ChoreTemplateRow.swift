//
//  ChoreTemplateRow.swift
//  houseWork
//
//  Displays a single chore template with metadata and score badge.
//

import SwiftUI

struct ChoreTemplateRow: View {
    let template: ChoreTemplate
    var onAddToBoard: () -> Void
    var onEdit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(template.title)
                    .font(.headline)
                Spacer()
                ScoreBadge(score: template.baseScore)
            }
            Text(template.details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(template.estimatedMinutes) min", systemImage: "timer")
                Label(template.frequency.label, systemImage: template.frequency.iconName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !template.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(template.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            HStack(spacing: 8) {
                Button(action: onAddToBoard) {
                    Label("Add to Board", systemImage: "plus.circle")
                        .font(.caption.bold())
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.secondary.opacity(0.15))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption.bold())
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.secondary.opacity(0.1))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }
}

struct ScoreBadge: View {
    let score: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
            Text("\(score) pts")
                .font(.caption.bold())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}

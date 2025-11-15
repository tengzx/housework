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
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(template.title)
                    .font(.headline)
                Text(template.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(minutesText, systemImage: "timer")
                    Label(template.frequency.localizedLabel, systemImage: template.frequency.iconName)
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
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 10) {
                ScoreBadge(score: template.baseScore)
                Button {
                    Haptics.impact()
                    onAddToBoard()
                } label: {
                    Label(LocalizedStringKey("catalog.action.addToBoard"), systemImage: "plus.circle.fill")
                        .font(.footnote.bold())
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 120)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScoreBadge: View {
    let score: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
            Text(pointsText)
                .font(.caption.bold())
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(Color.accentColor)
        .clipShape(Capsule())
    }
}

private extension ChoreTemplateRow {
    var minutesText: String {
        let format = String(localized: "catalog.row.minutes")
        return String(format: format, template.estimatedMinutes)
    }
}

private extension ScoreBadge {
    var pointsText: String {
        let format = String(localized: "catalog.row.points")
        return String(format: format, score)
    }
}

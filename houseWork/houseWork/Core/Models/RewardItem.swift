//
//  RewardItem.swift
//  houseWork
//
//  Represents a redeemable reward in the in-app catalog.
//

import SwiftUI

struct RewardItem: Identifiable, Hashable {
    let id: UUID
    let titleKey: String
    let detailKey: String
    let cost: Int
    let iconName: String
    let accentColor: Color
    
    init(
        id: UUID = UUID(),
        titleKey: String,
        detailKey: String,
        cost: Int,
        iconName: String,
        accentColor: Color
    ) {
        self.id = id
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.cost = cost
        self.iconName = iconName
        self.accentColor = accentColor
    }
}

struct RewardRedemption: Identifiable, Codable, Hashable {
    let id: UUID
    let rewardId: UUID
    let rewardTitleKey: String
    let memberId: UUID
    let memberName: String
    let redeemedAt: Date
    let cost: Int
    
    init(
        id: UUID = UUID(),
        rewardId: UUID,
        rewardTitleKey: String,
        memberId: UUID,
        memberName: String,
        redeemedAt: Date = Date(),
        cost: Int
    ) {
        self.id = id
        self.rewardId = rewardId
        self.rewardTitleKey = rewardTitleKey
        self.memberId = memberId
        self.memberName = memberName
        self.redeemedAt = redeemedAt
        self.cost = cost
    }
}

extension RewardItem {
    static let sampleCatalog: [RewardItem] = [
        RewardItem(
            titleKey: "rewards.reward.coffee.title",
            detailKey: "rewards.reward.coffee.description",
            cost: 50,
            iconName: "cup.and.saucer.fill",
            accentColor: Color(red: 0.95, green: 0.73, blue: 0.38)
        ),
        RewardItem(
            titleKey: "rewards.reward.movieNight.title",
            detailKey: "rewards.reward.movieNight.description",
            cost: 120,
            iconName: "popcorn.fill",
            accentColor: Color(red: 0.82, green: 0.47, blue: 0.91)
        ),
        RewardItem(
            titleKey: "rewards.reward.takeout.title",
            detailKey: "rewards.reward.takeout.description",
            cost: 180,
            iconName: "takeoutbag.and.cup.and.straw.fill",
            accentColor: Color(red: 0.32, green: 0.71, blue: 0.91)
        ),
        RewardItem(
            titleKey: "rewards.reward.dayOff.title",
            detailKey: "rewards.reward.dayOff.description",
            cost: 250,
            iconName: "sun.max.fill",
            accentColor: Color(red: 0.97, green: 0.61, blue: 0.54)
        )
    ]
}

extension RewardRedemption {
    static func sample(memberId: UUID) -> [RewardRedemption] {
        [
            RewardRedemption(
                rewardId: RewardItem.sampleCatalog[0].id,
                rewardTitleKey: RewardItem.sampleCatalog[0].titleKey,
                memberId: memberId,
                memberName: "Sample Member",
                redeemedAt: Date().addingTimeInterval(-3600),
                cost: RewardItem.sampleCatalog[0].cost
            )
        ]
    }
}

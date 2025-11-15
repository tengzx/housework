//
//  RewardItem.swift
//  houseWork
//
//  Represents a redeemable reward in the in-app catalog.
//

import Foundation

struct RewardItem: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var cost: Int
    
    init(id: UUID = UUID(), name: String, cost: Int) {
        self.id = id
        self.name = name
        self.cost = cost
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cost
        case legacyTitleKey = "titleKey"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let legacyName = try container.decodeIfPresent(String.self, forKey: .legacyTitleKey)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? legacyName ?? "Reward"
        cost = try container.decodeIfPresent(Int.self, forKey: .cost) ?? 0
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cost, forKey: .cost)
    }
}

struct RewardRedemption: Identifiable, Codable, Hashable {
    let id: UUID
    let rewardId: UUID
    let rewardName: String
    let memberId: UUID
    let memberName: String
    let redeemedAt: Date
    let cost: Int
    
    init(
        id: UUID = UUID(),
        rewardId: UUID,
        rewardName: String,
        memberId: UUID,
        memberName: String,
        redeemedAt: Date = Date(),
        cost: Int
    ) {
        self.id = id
        self.rewardId = rewardId
        self.rewardName = rewardName
        self.memberId = memberId
        self.memberName = memberName
        self.redeemedAt = redeemedAt
        self.cost = cost
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case rewardId
        case rewardName
        case memberId
        case memberName
        case redeemedAt
        case cost
        case legacyTitleKey = "rewardTitleKey"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        rewardId = try container.decode(UUID.self, forKey: .rewardId)
        let legacyName = try container.decodeIfPresent(String.self, forKey: .legacyTitleKey)
        rewardName = try container.decodeIfPresent(String.self, forKey: .rewardName) ?? legacyName ?? "Reward"
        memberId = try container.decode(UUID.self, forKey: .memberId)
        memberName = try container.decode(String.self, forKey: .memberName)
        redeemedAt = try container.decode(Date.self, forKey: .redeemedAt)
        cost = try container.decode(Int.self, forKey: .cost)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(rewardId, forKey: .rewardId)
        try container.encode(rewardName, forKey: .rewardName)
        try container.encode(memberId, forKey: .memberId)
        try container.encode(memberName, forKey: .memberName)
        try container.encode(redeemedAt, forKey: .redeemedAt)
        try container.encode(cost, forKey: .cost)
    }
}

extension RewardItem {
    static let sampleCatalog: [RewardItem] = [
        RewardItem(name: "Coffee Break", cost: 50),
        RewardItem(name: "Movie Night", cost: 120),
        RewardItem(name: "Takeout Dinner", cost: 180),
        RewardItem(name: "Day Off Voucher", cost: 250)
    ]
}

extension RewardRedemption {
    static func sample(memberId: UUID) -> [RewardRedemption] {
        [
            RewardRedemption(
                rewardId: RewardItem.sampleCatalog[0].id,
                rewardName: RewardItem.sampleCatalog[0].name,
                memberId: memberId,
                memberName: "Sample Member",
                redeemedAt: Date().addingTimeInterval(-3600),
                cost: RewardItem.sampleCatalog[0].cost
            )
        ]
    }
}

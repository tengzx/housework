# Firestore Tags 数据模型说明

为了在 Firebase 后端持久化家务标签数据，并在 iOS 端通过 `TagStore` 读取/更新，推荐以下设计：

## 集合结构

```
/households/{householdId}/tags/{tagId}
```

- `households`：顶层集合，每个家庭/家庭组一个 `householdId`。
- `tags`：每个 household 下的子集合，存储该家庭所有可用标签。
- `tagId`：Firestore 自动生成，或使用语义化 ID（例如 slug）。

## 文档字段

| 字段       | 类型     | 说明                                |
|------------|----------|-------------------------------------|
| `name`     | string   | 标签名称（唯一，可用 index 限制）    |
| `createdAt`| timestamp| 创建时间（服务端时间）              |
| `updatedAt`| timestamp| 最近一次更新（可用于排序/同步）     |
| `color`    | string   | （可选）标签颜色十六进制，如 `#FF9500` |

> 若标签需要全局共享（跨家庭），可以在顶层创建 `/tags/{tagId}`，并在 household 文档中维护引用；当前方案假设标签只在家庭内可见。

## 安全规则示例

```
match /databases/{database}/documents {
  match /households/{householdId}/{document=**} {
    allow read, write: if request.auth != null &&
      request.auth.token.householdId == householdId;
  }
}
```

如果没有自定义声明，可在 `/households/{householdId}/members/{uid}` 文档中维护成员列表，规则中查询是否存在再授权。

## 客户端操作建议

1. **监听标签集合**  
   使用 `Firestore.firestore().collection("households/\(householdId)/tags")` 添加 snapshot listener，将文档映射到 `TagItem`。

2. **新增标签**  
   写入 `{ "name": trimmedName, "createdAt": FieldValue.serverTimestamp(), ... }`。可利用 `name` 设置唯一索引防重复。

3. **重命名/删除**  
   使用 doc ID 直接更新或删除，更新时同步 `updatedAt`.

4. **离线缓存**  
   Firestore SDK 默认支持离线缓存，有规律地刷新即可保持客户端 `TagStore` 与服务端一致。

## 索引（可选）

- 如果需要通过 `name` 快速查重，可创建单字段索引或使用 Firestore “唯一约束” 方案（如 Cloud Functions）。

完成以上结构后，`TagStore` 只需从本地内存切换为监听 Firestore，以便多设备共享标签。

# Firebase Auth 接入指南

该文档帮助你在 Firebase 控制台中为 houseWork 应用配置登录相关的所有资源。完成本指南后，工程即可使用 Firebase Auth + Firestore 作为后端。

## 1. 创建 Firebase 项目
1. 打开 [https://console.firebase.google.com](https://console.firebase.google.com) 并使用团队 Google 账号登录。
2. 点击 `Add project`，输入项目名称（建议与 git 仓库同名），地区选择靠近主要用户的区域。
3. 关闭或保留 Google Analytics，按团队规范执行，点击 `Create project`。

## 2. 注册 iOS 应用
1. 在新建的项目仪表盘点击 `Add app -> iOS`。
2. `iOS bundle ID` 使用 Xcode 工程中的主 Bundle Identifier（例如 `com.company.houseWork`）。
3. App nickname、App Store ID 可选。
4. 下载生成的 `GoogleService-Info.plist` 放入 `houseWork/` 目录，并在 Xcode target `Build Phases -> Copy Bundle Resources` 中确认该文件被打包。

## 3. 启用 Firebase Authentication
1. 在左侧导航进入 `Build -> Authentication`，点击 `Get started`。
2. 在 `Sign-in method` 页签中启用需要的 Provider：
   - `Email/Password`：开启并保存。
   - `Apple` 或 `Google` 等第三方登录按需求配置（需要填写 Bundle ID、Service ID 等）。
3. 在 `Users` 页签可手动创建测试账号，也可使用 CLI/脚本创建。

## 4. 初始化 Firestore
1. 进入 `Build -> Firestore Database`，点击 `Create database`。
2. 选择 `Production mode`，地区选与 Auth 同区域。
3. 建议创建以下集合路径（可以在控制台或脚本中创建）：
   - `/households/{householdId}/tags/{tagId}`
   - `/households/{householdId}/chores/{choreId}`
   - `/households/{householdId}/tasks/{taskId}`
4. 记录项目 ID、Web API Key，用于后续在 Xcode 中配置。

## 5. 配置安全规则（示例）
根据当前需求，规则至少需要限制用户只能访问自己所属的 household。示例：
```rules
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /households/{householdId}/{document=**} {
      allow read, write: if request.auth != null
        && request.auth.token.householdId == householdId;
    }
  }
} Tengzx@891230
```
实际规则需结合 Auth 自定义声明或 membership 集合实现。

## 6. Xcode 中安装 Firebase 依赖
1. 使用 Swift Package Manager：`File -> Add Packages -> https://github.com/firebase/firebase-ios-sdk`.
2. 选择 `FirebaseAuth`, `FirebaseFirestore`, `FirebaseFirestoreSwift` 模块。
3. 在 `houseWorkApp.swift` 中导入 `FirebaseCore` 并调用 `FirebaseApp.configure()`.

## 7. 本地敏感信息管理
1. 将 `GoogleService-Info.plist` 加入 `.gitignore`，只在 CI/CD 中通过安全方式注入。
2. 在 `docs/ENVIRONMENT.md` 中记录 Firebase 项目 ID、API Key 的配置方式（如 Xcode Config、环境变量等）。

## 8. 测试流程
1. 在模拟器或真机运行，使用控制台创建的测试账号登录。
2. 触发任务创建、完成操作，检查 Firestore 中数据写入是否成功。
3. 关注 Xcode 控制台是否出现 `Auth`、`Firestore` 相关报错，以便及时调整规则或配置。

完成以上步骤后，应用就具备 Firebase Auth 登录、Firestore 数据持久化的基础能力，可以继续开发 UI 与状态同步逻辑。

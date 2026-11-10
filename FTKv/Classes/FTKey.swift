//
//  FTKey.swift
//  FTReq
//
//  Created by 熊坤鹏 on 2026/10/27.
//

import Foundation
import FTLogger

// ═══════════════════════════════════════════════════════════════
// MARK: - Key（KV 存储的 key 枚举 + 路径配置）
// ═══════════════════════════════════════════════════════════════

/// KV 存储的 key 枚举 + 路径配置。
///
/// 设计意图：
/// 1. **类型安全的 FTkey**：用枚举替代字符串，编译期检查，避免拼写错误
/// 2. **集中管理**：所有 KV key 收敛到一个枚举，便于查找和审查
/// 3. **带参数**：`user(Int64)`、`draft(String)` 等关联值，动态生成 key
/// 4. **统一命名规则**：通过 `name` 属性生成最终字符串，便于统一前缀和格式
public enum FTKey {

    // ═══════════════════════════════════════════════════════════
    // MARK: - KV 存储路径
    // ═══════════════════════════════════════════════════════════

    /// KV 存储目录（MMKV 的 rootDir）。
    ///
    /// 路径：`Library/FTKv/`
    ///
    /// 为什么用 `Library`：
    /// - 不会被系统随意清理（对比 Caches）
    /// - 不在用户可见范围（对比 Documents）
    ///
    /// ⚠️ 获取失败时 `fatalError` 崩溃——理论上 `Library` 目录一定存在，
    /// 但崩溃代价大，可以改成 throw 或兜底。
    static var kvPath: String {
        guard let libURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            FTLog.error("无法获取Library路径！")
            fatalError("无法获取Library路径！")
        }
        return libURL.appendingPathComponent("FTKv", isDirectory: true).path
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - Key 定义
    // ═══════════════════════════════════════════════════════════

    /// 我（当前用户信息）。
    case me

    /// 用户信息（按 uid 区分）。
    case user(Int64)

    /// 一般信息（extra 任意字符串）。
    case general(String)

    /// 草稿（按本地会话 id 区分）。
    case draft(String)

    /// 群成员信息（uid + groupId）。
    case groupUser(Int64, String)

    /// 好友分组 id（按 groupId 区分）。
    case friendGroupId(String)

    /// 联系人群组 id（按 groupId 区分）。
    case contactGroupId(String)

    /// 群详情（按 groupId 区分）。
    case groupDetail(String)

    /// 好友分组是否隐藏（按 groupingId 区分）。
    case friendGroupStatus(String)

    /// AI 语音消息时长数据（按 msgId 区分）。
    case aiMsgVoiceData(String)

    /// 不加任何前缀的 key（原始字符串）。
    case withoutPrefix(String)

    /// 底部栏配置。
    case tabBarConfig

    /// 新底部栏配置。
    case newTabBarConfig

    /// 群喇叭显示开关。
    case loudSpeakerSwitch

    /// 用户当前使用的地址。
    case currentUsedAddress

    /// 红包广告。
    case redpacketAd

    /// 群管理禁言时间。
    case groupMuteTimeout

    // ═══════════════════════════════════════════════════════════
    // MARK: - 生成最终 key 字符串
    // ═══════════════════════════════════════════════════════════

    /// 最终存储到 MMKV 的 key 字符串。
    ///
    /// 命名规则：
    /// - 带参数的 key：`前缀_参数`（如 `userInfo_1001`）
    /// - 无参数的 key：固定字符串（如 `TabBarConfigData`）
    /// - `withoutPrefix`：直接用原始字符串
    ///
    /// 为什么要统一命名：
    /// - 避免不同模块的 key 冲突
    /// - 便于通过 MMKV 文件排查数据
    /// - 前缀能看出用途（如 `ft_` 表示通用，`groupUserInfo_` 表示群成员）
    public var name: String {
        switch self {
        // ───────── 带参数的 key ─────────
        case .me:
            return "MeDataPbKey"

        case let .user(uid):
            return "userInfo_\(uid)"

        case let .general(extra):
            return "ft_general_\(extra)"

        case let .draft(lcd):
            return "draftStr_\(lcd)"

        case let .groupUser(uid, groupId):
            return "groupUserInfo_\(groupId)_\(uid)"

        case let .friendGroupId(groupId):
            return "ft_friend_groupId_\(groupId)"

        case let .contactGroupId(groupId):
            return "ft_contact_groupId_\(groupId)"

        case let .groupDetail(groupId):
            return "ft_group_detail_\(groupId)"

        case let .friendGroupStatus(groupingId):
            return "ft_status_groupingId_\(groupingId)"

        case let .aiMsgVoiceData(msgId):
            return "ft_ai_message_voice_data_\(msgId)"

        case let .withoutPrefix(temp):
            return temp

        // ───────── 无参数的 key ─────────
        case .tabBarConfig:
            return "TabBarConfigData"

        case .newTabBarConfig:
            return "newTabBarConfigData"

        case .loudSpeakerSwitch:
            return "loudSpeakerSwitch"

        case .currentUsedAddress:
            return "CurrentUsedAddress"

        case .redpacketAd:
            return "redpacketAd"

        case .groupMuteTimeout:
            return "groupMuteTimeout"
        }
    }
}

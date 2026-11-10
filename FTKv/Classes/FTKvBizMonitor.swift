//
//  FTKvBizMonitor.swift
//  Pods
//
//  Created by 熊坤鹏 on 2026/10/27.
//

//  KV / MMKV CLS 上报助手。
//  不直接依赖 FTReq（FTReq 已依赖 FTKv），由上层注入 errorReporter。
//  data 不含 key 原文、uid、cryptKey、业务内容。
//

import Foundation

// ═══════════════════════════════════════════════════════════════
// MARK: - FTKvBizMonitor（KV 层错误上报助手）
// ═══════════════════════════════════════════════════════════════

/// KV / MMKV 层的错误上报助手。
///
/// 设计意图：
/// 1. **避免循环依赖**：FTReq 依赖 FTKv，FTKv 不能反向依赖 FTReq
/// 2. **依赖注入**：由上层（宿主 / FTReq）注入 `errorReporter`，FTKv 只调用
/// 3. **隐私安全**：上报数据不含 key 原文、uid、cryptKey、业务内容
///
/// 上报字段：
/// - `error_domain`：错误域（如 NSCocoaErrorDomain）
/// - `error_code`：错误码
/// - `value_kind`：值类型（如 "String"、"Model"），不含值本身
/// - `err`：错误消息（限长 200 字符）
public enum FTKvBizMonitor {

    // ═══════════════════════════════════════════════════════════
    // MARK: - 依赖注入
    // ═══════════════════════════════════════════════════════════

    /// 错误上报器（由 FTReq / 宿主注入）。
    ///
    /// 为什么要注入：
    /// - FTReq 依赖 FTKv，FTKv 不能 import FTReq（否则循环依赖）
    /// - 所以 FTKv 只暴露一个闭包，由上层注入具体实现
    ///
    /// 注入方式（在 FTReq 或宿主里）：
    /// ```swift
    /// FTKvBizMonitor.errorReporter = { message, model, data in
    ///     BizMonitor.error(tag: "KV", message: message, model: model, data: data)
    /// }
    /// ```
    ///
    /// 闭包签名：
    /// - `message`：事件名（如 "kv_encode_failed"）
    /// - `model`：接口路径（如 "/kv/set"）
    /// - `data`：上报数据字典
    public static var errorReporter: ((_ message: String, _ model: String?, _ data: [String: String]) -> Void)?

    // ═══════════════════════════════════════════════════════════
    // MARK: - 具体上报方法
    // ═══════════════════════════════════════════════════════════

    /// 上报编码失败（如模型转 JSON/Data 失败）。
    ///
    /// - Parameters:
    ///   - valueKind: 值类型（如 "String"、"Model"），不含值本身
    ///   - error: 原始错误
    static func reportEncodeFailed(valueKind: String, error: Error) {
        // ① 基础错误信息
        var data = errorData(error)
        // ② 附加值类型（限长 128）
        data["value_kind"] = limited(valueKind)
        report(message: "kv_encode_failed", model: "/kv/set", data: data)
    }

    /// 上报解码失败（如 JSON/Data 转模型失败）。
    ///
    /// - Parameters:
    ///   - valueKind: 值类型
    ///   - error: 原始错误
    static func reportDecodeFailed(valueKind: String, error: Error) {
        var data = errorData(error)
        data["value_kind"] = limited(valueKind)
        report(message: "kv_decode_failed", model: "/kv/get", data: data)
    }

    /// 上报 MMKV CRC 校验失败（数据损坏）。
    ///
    /// MMKV 是微信开源的 KV 存储，内部有 CRC 校验，失败说明文件损坏。
    static func reportMMKVCRCCheckFailed() {
        report(message: "mmkv_crc_check_failed", model: "/kv/mmkv")
    }

    /// 上报 MMKV SDK 错误（MMKV 内部抛错）。
    ///
    /// - Parameter message: MMKV 错误消息（可能为空）
    static func reportMMKVSDKError(message: String?) {
        var data: [String: String] = [:]
        // ① 有错误消息才附加（限长 200）
        if let message, !message.isEmpty {
            data["err"] = limited(message, max: 200)
        }
        report(message: "mmkv_sdk_error", model: "/kv/mmkv", data: data)
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - 私有工具
    // ═══════════════════════════════════════════════════════════

    /// 统一上报入口（转调注入的 errorReporter）。
    ///
    /// - Parameters:
    ///   - message: 事件名
    ///   - model: 接口路径
    ///   - data: 上报数据
    private static func report(message: String, model: String?, data: [String: String] = [:]) {
        // ① 如果没注入，什么都不做（静默）
        errorReporter?(message, model, data)
    }

    /// 从 Error 提取上报数据（只取 domain 和 code）。
    ///
    /// **不取 `userInfo`**——可能包含业务数据、key 原文、敏感信息。
    ///
    /// - Parameter error: 错误
    /// - Returns: `["error_domain": ..., "error_code": ...]`
    private static func errorData(_ error: Error) -> [String: String] {
        let nsError = error as NSError
        return [
            "error_domain": limited(nsError.domain),
            "error_code": "\(nsError.code)"
        ]
    }

    /// 字符串限长（防止上报体过大）。
    ///
    /// - Parameters:
    ///   - value: 原始字符串
    ///   - max: 最大长度，默认 128
    /// - Returns: 截断后的字符串
    private static func limited(_ value: String, max: Int = 128) -> String {
        String(value.prefix(max))
    }
}

//
//  FTKv.swift
//  FTReq
//
//  Created by 熊坤鹏 on 2026/10/27.
//

import Foundation
import MMKV
import FTLogger
import SwiftProtobuf

// ═══════════════════════════════════════════════════════════════
// MARK: - FTKv（基于 MMKV 的 KV 存储封装，单例）
// ═══════════════════════════════════════════════════════════════

/// 基于 MMKV 的 KV 存储封装。
///
/// 核心能力：
/// 1. **单例**：全局唯一入口
/// 2. **用户隔离**：每个用户一个 MMKV 实例（`mmapID = uid`），切换账号数据隔离
/// 3. **全局存储**：`isGlobal = true` 时不跟随用户（如 App 配置）
/// 4. **加密**：MMKV 实例带 `cryptKey`
/// 5. **类型支持**：Int / Int32 / Int64 / UInt32 / UInt64 / Bool / Float / Double / String / Data / Date / Protobuf / 字典 / Codable / NSCoding
/// 6. **错误上报**：编码/解码失败、MMKV CRC 失败、SDK 错误都上报 `FTKvBizMonitor`
public class FTKv: NSObject {

    // MARK: - 单例

    /// 全局单例。
    public static let shared = FTKv()

    // MARK: - 当前用户

    /// 当前用户 uid。
    ///
    /// - 0：未登录，用默认 MMKV（`defaultMMKV`）
    /// - >0：已登录，用用户 MMKV（`userMMKV`，`mmapID = uid`）
    public private(set) var uid: Int64 = 0

    // ═══════════════════════════════════════════════════════════
    // MARK: - 初始化
    // ═══════════════════════════════════════════════════════════

    /// 初始化 MMKV。
    ///
    /// 必须在 `setup(uid:)` 之前调用（App 启动时）。
    ///
    /// - `rootDir`：MMKV 存储目录（`Key.kvPath`）
    /// - `logLevel`：日志级别（`.info`）
    /// - `handler`：MMKV 事件处理器（`self`，处理 CRC 失败、日志重定向等）
    public func initKv() {
        MMKV.initialize(rootDir: FTKey.kvPath, logLevel: .info, handler: self)
        FTLog.debug("MMKV version: \(MMKV.version())")
    }

    /// 配置 uid，KV 信息存储到当前用户上。
    ///
    /// 登录成功后调用。
    ///
    /// - Parameter uid: 用户 id（必须 > 0）
    public func setup(uid: Int64) {
        if uid > 0 {
            self.uid = uid
        }
    }

    /// 重置 uid，KV 信息回到默认配置。
    ///
    /// 登出时调用。
    public func resetUid() {
        uid = 0
    }

    /// App 终止时调用（`applicationWillTerminate`）。
    ///
    /// 清理 MMKV 资源，确保数据落盘。
    public func terminalKv() {
        uid = 0
        MMKV.onAppTerminate()
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - MMKV 实例（用户 / 全局）
    // ═══════════════════════════════════════════════════════════

    /// 用户 MMKV 实例（跟随 uid）。
    ///
    /// - uid > 0：用 `mmapID = uid` 的实例（每个用户一个）
    /// - uid == 0：用默认实例
    ///
    /// 加密：`cryptKey = "gome.FT.kv.2024"`
    /// 过期：`never`（永不过期）
    private var userMMKV: MMKV? {
        if uid > 0 {
            let mmkv = MMKV(mmapID: String(uid), cryptKey: Constrant.kvPwd.data(using: .utf8))
            mmkv?.enableAutoKeyExpire(expiredInSeconds: MMKVExpireDuration.never.rawValue)
            return mmkv
        } else {
            return defaultMMKV
        }
    }

    /// 默认 MMKV 实例（全局，不跟随用户）。
    private var defaultMMKV: MMKV? {
        let mmkv = MMKV.defaultMMKV(withCryptKey: Constrant.kvPwd.data(using: .utf8))
        mmkv?.enableAutoKeyExpire(expiredInSeconds: MMKVExpireDuration.never.rawValue)
        return mmkv
    }

    /// 常量。
    enum Constrant {
        /// MMKV 加密密钥。
        ///
        /// ⚠️ 硬编码在代码里，反编译可见，是安全风险。
        static let kvPwd = "gome.FT.kv.2024"
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - 写入（set）
    // ═══════════════════════════════════════════════════════════

    /// 写入值。
    ///
    /// 按值类型分派到 MMKV 的对应方法：
    /// - 基础类型（Int / Bool / String / Data / Date 等）：直接 `mmkv?.set`
    /// - Protobuf（`Message`）：转 JSON 字符串后存
    /// - 字典（`[String: Any]`）：转 JSON 字符串后存
    /// - Codable：JSON 编码成 Data 后存
    /// - NSCoding：直接 `mmkv?.set`
    ///
    /// - Parameters:
    ///   - value: 值
    ///   - key: 类型安全的 key（`Key`）
    ///   - isGlobal: 是否全局（不跟随用户）
    // swiftlint:disable:next cyclomatic_complexity
    public func set(_ value: Any?, forKey key: FTKey, isGlobal: Bool = false) {
        // ① 选 MMKV 实例（用户 or 全局）
        let mmkv = isGlobal ? defaultMMKV : userMMKV

        // ② nil 不存
        guard let value = value else { return }

        // ③ 按类型分派
        switch value {
        case let aVal as Int:
            mmkv?.set(Int64(aVal), forKey: key.name)
        case let aVal as Int32:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Int64:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as UInt32:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as UInt64:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Bool:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Float:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Double:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as String:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Data:
            mmkv?.set(aVal, forKey: key.name)
        case let aVal as Date:
            mmkv?.set(aVal, forKey: key.name)

        case let aVal as Message:
            // ④ Protobuf：转 JSON 字符串
            do {
                let bVal = try aVal.jsonString()
                mmkv?.set(bVal, forKey: key.name)
            } catch {
                assert(true, "转换失败：原pb类型是: \(String(describing: aVal)), err: \(error)")
                
                FTKvBizMonitor.reportEncodeFailed(valueKind: "protobuf", error: error)
            }

        case let aVal as [String: Any]:
            // ⑤ 字典：转 JSON 字符串
            do {
                let aData = try JSONSerialization.data(withJSONObject: aVal)
                if let bVal = String(data: aData, encoding: .utf8) {
                    mmkv?.set(bVal, forKey: key.name)
                } else {
                    assert(true, "存储失败，原字典类型是: \(String(describing: aVal)), err: 空")
                    FTKvBizMonitor.reportEncodeFailed(
                        valueKind: "json",
                        error: NSError(domain: "FTKv", code: -1, userInfo: [NSLocalizedDescriptionKey: "utf8_encode_nil"])
                    )
                }
            } catch {
                assert(true, "转换失败：原字典类型是: \(String(describing: aVal)), err: \(error)")
                
                FTKvBizMonitor.reportEncodeFailed(valueKind: "json", error: error)
            }

        case let aVal as Codable:
            // ⑥ Codable：JSON 编码成 Data
            do {
                let tempData = try JSONEncoder().encode(aVal)
                mmkv?.set(tempData, forKey: key.name)
            } catch {
                assert(true, "转换失败：原Codable协议类型是: \(String(describing: aVal)), err: \(error)")
                
                FTKvBizMonitor.reportEncodeFailed(valueKind: "codable", error: error)
            }

        case let aVal as (NSCoding & NSObjectProtocol):
            // ⑦ NSCoding：直接存（MMKV 支持归档）
            mmkv?.set(aVal, forKey: key.name)

        default:
            // ⑧ 不支持的类型：断言提示
            assert(true, "暂不支持当前类型: \(String(describing: value)), 存储 `struct,class,enum` 需要遵守`Codable`协议")
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - 读取（value）
    // ═══════════════════════════════════════════════════════════

    /// 读取值。
    ///
    /// 按目标类型分派到 MMKV 的对应方法。
    ///
    /// 注意：用 `hasValue` 区分"值不存在"和"值存在但为默认值（0/false/空串）"。
    ///
    /// - Parameters:
    ///   - as: 目标类型
    ///   - key: 类型安全的 key（`Key`）
    ///   - isGlobal: 是否全局
    /// - Returns: 读取的值；不存在或类型不匹配返回 nil
    // swiftlint:disable:next cyclomatic_complexity
    public func value<T>(_ as: T.Type, forKey key: FTKey, isGlobal: Bool = false) -> T? {
        // ① 选 MMKV 实例
        let mmkv = isGlobal ? defaultMMKV : userMMKV

        // ② hasValue：区分"不存在"和"存在但为默认值"
        var hasValue: ObjCBool = false

        switch `as` {
        case is Int.Type:
            guard let aVal = mmkv?.int64(forKey: key.name, defaultValue: 0, hasValue: &hasValue) else {
                return nil
            }
            return hasValue.boolValue ? NSNumber(value: aVal).intValue as? T : nil

        case is Int64.Type:
            let aVal = mmkv?.int64(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is Int32.Type:
            let aVal = mmkv?.int32(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is UInt32.Type:
            let aVal = mmkv?.uint32(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is UInt64.Type:
            let aVal = mmkv?.uint64(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is Bool.Type:
            let aVal = mmkv?.bool(forKey: key.name, defaultValue: false, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is Float.Type:
            let aVal = mmkv?.float(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is Double.Type:
            let aVal = mmkv?.double(forKey: key.name, defaultValue: 0, hasValue: &hasValue) as? T
            return hasValue.boolValue ? aVal : nil

        case is String.Type:
            return mmkv?.string(forKey: key.name) as? T

        case is Data.Type:
            return mmkv?.data(forKey: key.name) as? T

        case is Date.Type:
            return mmkv?.date(forKey: key.name) as? T

        case let aVal as Message.Type:
            // ③ Protobuf：从 JSON 字符串解析
            guard let strVal = mmkv?.string(forKey: key.name) else { return nil }
            do {
                return try aVal.init(jsonString: strVal) as? T
            } catch {
                assert(true, "获取失败 类型: \(aVal), Key: \(key.name), err: \(error)")
                
                FTKvBizMonitor.reportDecodeFailed(valueKind: "protobuf", error: error)
                return nil
            }

        case is [String: Any].Type:
            // ④ 字典：从 JSON 字符串解析
            guard
                let json = mmkv?.string(forKey: key.name),
                let jsonData = json.data(using: .utf8) else {
                return nil
            }
            do {
                return try JSONSerialization.jsonObject(with: jsonData) as? T
            } catch {
                assert(true, "获取失败 类型: \(`as`), Key: \(key.name), err: \(error)")
                
                FTKvBizMonitor.reportDecodeFailed(valueKind: "json", error: error)
                return nil
            }

        case let temp as Codable.Type:
            // ⑤ Codable：JSON 解码
            guard let tempData = mmkv?.data(forKey: key.name) else { return nil }
            do {
                return try JSONDecoder().decode(temp.self, from: tempData) as? T
            } catch {
                assert(true, "获取失败 类型: \(`as`), Key: \(key.name), err: \(error)")
                
                FTKvBizMonitor.reportDecodeFailed(valueKind: "codable", error: error)
                return nil
            }

        case let temp as (NSObjectProtocol & NSCoding).Type:
            // ⑥ NSCoding：直接解归档
            return mmkv?.object(of: temp.self, forKey: key.name) as? T

        default:
            // ⑦ 不支持的类型：断言提示
            assert(true, "暂不支持当前类型: \(`as`), key: \(key.name), 存储 struct/class/enum 需要遵守Codable协议 或 NSObject<NSCoding>")
            return nil
        }
    }

    // ═══════════════════════════════════════════════════════════
    // MARK: - 删除
    // ═══════════════════════════════════════════════════════════

    /// 删除值。
    public func remove(forKey key: FTKey, isGlobal: Bool = false) {
        let mmkv = isGlobal ? defaultMMKV : userMMKV
        mmkv?.removeValue(forKey: key.name)
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - MMKVHandler（MMKV 事件处理）
// ═══════════════════════════════════════════════════════════════

extension FTKv: MMKVHandler {

    /// MMKV CRC 校验失败（数据损坏）。
    ///
    /// 返回 `.onErrorRecover`：丢弃损坏数据，继续运行。
    public func onMMKVCRCCheckFail(_ mmapID: String!) -> MMKVRecoverStrategic {
        FTKvBizMonitor.reportMMKVCRCCheckFailed()
        return .onErrorRecover
    }

    /// MMKV 内容变化（其他进程修改了 MMKV 文件）。
    public func onMMKVContentChange(_ mmapID: String!) {
        FTLog.debug("onMMKVContentChange: \(mmapID!)")
    }

    /// MMKV 内部日志重定向到 FTLogger。
    ///
    /// - 错误级别同时上报 `FTKvBizMonitor`
    public func mmkvLog(
        with level: MMKVLogLevel,
        file: UnsafePointer<CChar>!,
        line: Int32,
        func funcname: UnsafePointer<CChar>!,
        message: String!
    ) {
        // ① 级别 → 单字符
        let levelDesc: String
        switch level {
        case .debug: levelDesc = "D"
        case .info: levelDesc = "I"
        case .warning: levelDesc = "W"
        case .error: levelDesc = "E"
        case .none: levelDesc = "N"
        @unknown default: levelDesc = "UN"
        }

        // ② 错误级别上报
        if level == .error {
            FTKvBizMonitor.reportMMKVSDKError(message: message)
        }

        // ③ 本地日志
        FTLog.debug("redirect logging [\(levelDesc)] <\(String(describing: file)):\(line)::\(String(describing: funcname))> \(String(describing: message))")
    }
}

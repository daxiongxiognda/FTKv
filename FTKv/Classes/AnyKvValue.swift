//
//  AnyKvValue.swift
//  FTReq
//
//  Created by 熊坤鹏 on 2026/10/27.
//

import Foundation
import SwiftProtobuf

// ═══════════════════════════════════════════════════════════════
// MARK: - AnyKvValue（KV 存储支持的值类型枚举）
// ═══════════════════════════════════════════════════════════════

/// KV 存储支持的值类型枚举。
///
/// 用途：
/// 把任意支持的类型包装成一个统一枚举，解决 `Any` 类型不安全的问题。
///
/// 设计意图：
/// 1. **类型安全**：用枚举明确列出所有支持的类型，编译器检查
/// 2. **统一入口**：`FTKv.set` / `FTKv.value` 可以接收 `AnyKvValue`
/// 3. **可扩展**：新增类型只需加一个 case
///
/// 对比 `Any`：
/// ```swift
/// // ❌ 用 Any：类型不安全，运行时才知道类型
/// kv.set(someValue as Any, forKey: key)
///
/// // ✅ 用 AnyKvValue：编译期检查，明确支持的类型
/// kv.set(.string("hello"), forKey: key)
/// ```
public enum AnyKvValue {

    /// 布尔值。
    case bool(Bool)

    /// Int（平台相关，32/64 位）。
    case int(Int)

    /// 32 位有符号整数。
    case int32(Int32)

    /// 32 位无符号整数。
    case uint32(UInt32)

    /// 64 位有符号整数。
    case int64(Int64)

    /// 64 位无符号整数。
    case uint64(UInt64)

    /// 单精度浮点数。
    case float(Float)

    /// 双精度浮点数。
    case double(Double)

    /// 字符串。
    case string(String)

    /// 日期。
    case date(Date)

    /// 二进制数据。
    case data(Data)

    /// Protobuf 消息。
    ///
    /// `Message` 是 SwiftProtobuf 的协议，所有生成的 pb 类型都遵循。
    case protobuf(Message)

    /// 遵循 NSCoding 的对象（如 NSString、NSArray、自定义 NSObject 子类）。
    case nscoding(NSCoding)
}

import Foundation

struct GenericImportRecordDraft: Equatable {
    enum Kind: String { case expense, income }
    let rowNumber: Int
    let kind: Kind
    let businessDate: String
    let occurredAt: String?
    let amountMinor: Int64
    let currency: String
    let merchant: String
    let category: String
    let channel: String
    let note: String?
    let sourceRecordID: String?
    let rawFields: [String: String]
    let warnings: [String]

    var sourceFingerprint: String {
        let value = [kind.rawValue, businessDate, String(amountMinor), merchant, category, channel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
        return String(value.utf8.reduce(into: UInt64(14695981039346656037)) { hash, byte in
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }, radix: 16)
    }
}

struct GenericImportCSVError: Equatable, LocalizedError {
    let row: Int
    let field: String?
    let reason: String

    var errorDescription: String? {
        if let field { return "第\(row)行「\(field)」：\(reason)" }
        return "第\(row)行：\(reason)"
    }
}

struct GenericImportCSVParser {
    private let aliases: [String: Set<String>] = [
        "date": ["date", "日期", "交易日期", "记账日期", "消费日期", "收入日期", "transaction_date", "income_date"],
        "time": ["time", "时间", "交易时间", "record_time", "transaction_time"],
        "amount": ["amount", "金额", "交易金额", "消费金额", "收入金额"],
        "kind": ["kind", "type", "类型", "收支", "收支类型", "交易类型", "record_type"],
        "merchant": ["merchant", "merchant_name", "商户", "商家", "名称", "来源", "来源名称", "source_name", "title"],
        "category": ["category", "分类", "类别", "消费分类", "收入分类"],
        "channel": ["channel", "platform", "payment_method", "支付渠道", "支付方式", "平台", "渠道"],
        "note": ["note", "备注", "说明", "摘要", "summary"],
        "id": ["id", "交易号", "流水号", "订单号", "记录id", "record_id"]
    ]

    func parse(_ data: Data) -> (records: [GenericImportRecordDraft], errors: [GenericImportCSVError]) {
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\u{FEFF}", with: "")
        let rows = Self.rows(text)
        guard let header = rows.first else { return ([], [GenericImportCSVError(row: 1, field: nil, reason: "文件没有表头")]) }
        let normalizedHeader = header.map(Self.normalize)
        func index(_ key: String) -> Int? { normalizedHeader.firstIndex { aliases[key, default: []].contains($0) } }
        guard let dateIndex = index("date"), let amountIndex = index("amount") else {
            return ([], [GenericImportCSVError(row: 1, field: nil, reason: "必须包含日期和金额列")])
        }
        let kindIndex = index("kind"), timeIndex = index("time"), merchantIndex = index("merchant")
        let categoryIndex = index("category"), channelIndex = index("channel"), noteIndex = index("note"), idIndex = index("id")
        var records: [GenericImportRecordDraft] = [], errors: [GenericImportCSVError] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            guard row.count <= header.count else { errors.append(.init(row: rowNumber, field: nil, reason: "列数超过表头")); continue }
            let value: (Int?) -> String = { index in guard let index, index < row.count else { return "" }; return row[index].trimmingCharacters(in: .whitespacesAndNewlines) }
            do {
                let date = try Self.date(value(dateIndex), row: rowNumber)
                let amount = try Self.amountMinor(value(amountIndex), row: rowNumber)
                let kind = Self.kind(value(kindIndex), amount: amount)
                let merchant = value(merchantIndex).isEmpty ? "未命名商户" : value(merchantIndex)
                var warnings: [String] = []
                if value(merchantIndex).isEmpty { warnings.append("商户为空，已使用未命名商户") }
                if value(categoryIndex).isEmpty { warnings.append("分类为空") }
                records.append(GenericImportRecordDraft(rowNumber: rowNumber, kind: kind, businessDate: date,
                    occurredAt: value(timeIndex).isEmpty ? nil : value(timeIndex), amountMinor: amount,
                    currency: "CNY", merchant: merchant, category: value(categoryIndex), channel: value(channelIndex),
                    note: value(noteIndex).isEmpty ? nil : value(noteIndex), sourceRecordID: value(idIndex).isEmpty ? nil : value(idIndex),
                    rawFields: Dictionary(uniqueKeysWithValues: zip(header, row).map { (Self.normalize($0.0), $0.1) }), warnings: warnings))
            } catch let error as GenericImportCSVError { errors.append(error) }
            catch { errors.append(.init(row: rowNumber, field: nil, reason: error.localizedDescription)) }
        }
        return (records, errors)
    }

    private static func rows(_ text: String) -> [[String]] {
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text), i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" { if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { quoted.toggle() } }
            else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted { if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }; row.append(field); field = ""; if row.contains(where: { !$0.isEmpty }) { result.append(row) }; row = [] }
            else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); result.append(row) }
        return result
    }

    private static func normalize(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_") }
    private static func date(_ value: String, row: Int) throws -> String {
        let v = value.replacingOccurrences(of: "/", with: "-")
        let parts = v.split(separator: "-").map(String.init)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m), (1...31).contains(d) else { throw GenericImportCSVError(row: row, field: "日期", reason: "日期格式无效") }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    private static func amountMinor(_ value: String, row: Int) throws -> Int64 {
        let cleaned = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "¥", with: "").replacingOccurrences(of: "￥", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(cleaned), amount.isFinite, amount != 0 else { throw GenericImportCSVError(row: row, field: "金额", reason: "金额格式无效或为零") }
        let minor = amount * 100
        guard minor <= Double(Int64.max), minor >= Double(Int64.min) else { throw GenericImportCSVError(row: row, field: "金额", reason: "金额超出范围") }
        return abs(Int64(minor.rounded()))
    }
    private static func kind(_ value: String, amount: Int64) -> GenericImportRecordDraft.Kind { let v = value.lowercased(); return (v.contains("收入") || v.contains("income") || v == "in" || amount < 0) ? .income : .expense }
}

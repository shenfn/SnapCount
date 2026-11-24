import Foundation

struct JieziFoodNutritionItem: Identifiable, Hashable {
    let id: String
    let name: String
    let aliases: [String]
    let kcalPer100g: Double
    let defaultGrams: Int
    let unitHint: String
}

struct JieziFoodCalorieEstimate: Equatable {
    let item: JieziFoodNutritionItem
    let grams: Int
    let estimatedKcal: Int
}

/// 本地离线食物热量估算器（按常见食物每 100g 热量 × 克数估算）
enum JieziFoodCalorieEstimator {
    static let maxGrams = 5_000

    static let catalog: [JieziFoodNutritionItem] = [
        // 主食
        .init(id: "rice", name: "米饭", aliases: ["白米饭", "大米饭", "蒸米饭"], kcalPer100g: 116, defaultGrams: 150, unitHint: "约1小碗"),
        .init(id: "brown_rice", name: "糙米饭", aliases: ["杂粮饭", "藜麦饭"], kcalPer100g: 111, defaultGrams: 150, unitHint: "约1小碗"),
        .init(id: "noodles", name: "面条", aliases: ["挂面", "阳春面", "拉面", "清汤面"], kcalPer100g: 110, defaultGrams: 250, unitHint: "约1碗"),
        .init(id: "beef_noodle", name: "牛肉面", aliases: ["红烧牛肉面", "兰州拉面"], kcalPer100g: 135, defaultGrams: 400, unitHint: "约1大碗"),
        .init(id: "fried_rice", name: "蛋炒饭", aliases: ["炒饭", "扬州炒饭"], kcalPer100g: 175, defaultGrams: 300, unitHint: "约1份"),
        .init(id: "congee", name: "白粥", aliases: ["大米粥", "小米粥", "皮蛋瘦肉粥"], kcalPer100g: 46, defaultGrams: 300, unitHint: "约1碗"),
        .init(id: "mantou", name: "馒头", aliases: ["花卷", "白馒头"], kcalPer100g: 223, defaultGrams: 100, unitHint: "约1个"),
        .init(id: "baozi", name: "包子", aliases: ["肉包", "菜包", "小笼包"], kcalPer100g: 227, defaultGrams: 120, unitHint: "约2个"),
        .init(id: "dumpling", name: "饺子", aliases: ["水饺", "煎饺", "馄饨"], kcalPer100g: 210, defaultGrams: 200, unitHint: "约10个"),
        .init(id: "toast", name: "吐司", aliases: ["全麦吐司", "切片面包", "面包"], kcalPer100g: 265, defaultGrams: 70, unitHint: "约2片"),
        .init(id: "oats", name: "燕麦", aliases: ["燕麦片", "即食燕麦"], kcalPer100g: 377, defaultGrams: 50, unitHint: "干重约5勺"),
        .init(id: "corn", name: "玉米", aliases: ["甜玉米", "糯玉米", "煮玉米"], kcalPer100g: 106, defaultGrams: 200, unitHint: "约1根"),
        .init(id: "sweet_potato", name: "红薯", aliases: ["紫薯", "烤红薯", "地瓜"], kcalPer100g: 99, defaultGrams: 200, unitHint: "约1个"),
        .init(id: "pasta", name: "意面", aliases: ["番茄意面", "意大利面"], kcalPer100g: 158, defaultGrams: 250, unitHint: "约1盘"),

        // 肉蛋奶海鲜豆制品
        .init(id: "chicken_breast", name: "鸡胸肉", aliases: ["水煮鸡胸", "香煎鸡胸", "鸡肉"], kcalPer100g: 133, defaultGrams: 150, unitHint: "约1块"),
        .init(id: "chicken_leg", name: "鸡腿", aliases: ["烤鸡腿", "卤鸡腿", "鸡翅"], kcalPer100g: 181, defaultGrams: 160, unitHint: "约1只"),
        .init(id: "beef", name: "牛肉", aliases: ["瘦牛肉", "牛排", "卤牛肉", "肥牛"], kcalPer100g: 170, defaultGrams: 150, unitHint: "约1份"),
        .init(id: "pork", name: "猪肉", aliases: ["瘦肉", "里脊", "炒肉"], kcalPer100g: 143, defaultGrams: 150, unitHint: "约1份"),
        .init(id: "braised_pork", name: "红烧肉", aliases: ["五花肉", "回锅肉", "扣肉"], kcalPer100g: 390, defaultGrams: 120, unitHint: "约4-5块"),
        .init(id: "egg", name: "鸡蛋", aliases: ["水煮蛋", "煮鸡蛋", "茶叶蛋"], kcalPer100g: 144, defaultGrams: 55, unitHint: "约1个"),
        .init(id: "fried_egg", name: "煎蛋", aliases: ["荷包蛋", "炒蛋"], kcalPer100g: 196, defaultGrams: 60, unitHint: "约1个"),
        .init(id: "shrimp", name: "虾仁", aliases: ["大虾", "白灼虾", "基围虾"], kcalPer100g: 93, defaultGrams: 150, unitHint: "约10只"),
        .init(id: "salmon", name: "三文鱼", aliases: ["鱼肉", "鳕鱼", "清蒸鱼", "鲈鱼"], kcalPer100g: 180, defaultGrams: 150, unitHint: "约1块"),
        .init(id: "tofu", name: "豆腐", aliases: ["嫩豆腐", "老豆腐", "豆干"], kcalPer100g: 81, defaultGrams: 150, unitHint: "约半盒"),
        .init(id: "milk", name: "牛奶", aliases: ["纯牛奶", "脱脂牛奶", "鲜奶"], kcalPer100g: 62, defaultGrams: 250, unitHint: "约1盒"),
        .init(id: "yogurt", name: "酸奶", aliases: ["无糖酸奶", "希腊酸奶"], kcalPer100g: 72, defaultGrams: 150, unitHint: "约1杯"),
        .init(id: "soymilk", name: "豆浆", aliases: ["无糖豆浆", "现磨豆浆"], kcalPer100g: 31, defaultGrams: 300, unitHint: "约1杯"),

        // 常见菜肴与快餐
        .init(id: "salad", name: "沙拉", aliases: ["轻食沙拉", "鸡肉沙拉", "凯撒沙拉", "蔬菜沙拉"], kcalPer100g: 110, defaultGrams: 280, unitHint: "约1盒"),
        .init(id: "tomato_egg", name: "番茄炒蛋", aliases: ["西红柿炒鸡蛋"], kcalPer100g: 105, defaultGrams: 200, unitHint: "约1盘"),
        .init(id: "greens", name: "炒青菜", aliases: ["青菜", "西兰花", "生菜", "空心菜", "油麦菜"], kcalPer100g: 55, defaultGrams: 200, unitHint: "约1盘"),
        .init(id: "malatang", name: "麻辣烫", aliases: ["冒菜", "关东煮"], kcalPer100g: 115, defaultGrams: 450, unitHint: "约1碗"),
        .init(id: "rice_bowl", name: "盖浇饭", aliases: ["黄焖鸡米饭", "猪脚饭", "煲仔饭", "卤肉饭"], kcalPer100g: 165, defaultGrams: 400, unitHint: "约1份"),
        .init(id: "burger", name: "汉堡", aliases: ["牛肉汉堡", "鸡腿堡", "三明治"], kcalPer100g: 255, defaultGrams: 220, unitHint: "约1个"),
        .init(id: "pizza", name: "披萨", aliases: ["比萨"], kcalPer100g: 266, defaultGrams: 200, unitHint: "约2片"),
        .init(id: "fries", name: "薯条", aliases: ["炸鸡", "鸡块", "鸡米花"], kcalPer100g: 298, defaultGrams: 120, unitHint: "约1中份"),
        .init(id: "hotpot", name: "火锅", aliases: ["牛肉火锅", "麻辣火锅", "寿喜烧"], kcalPer100g: 160, defaultGrams: 500, unitHint: "约1餐"),
        .init(id: "sushi", name: "寿司", aliases: ["饭团", "紫菜包饭"], kcalPer100g: 145, defaultGrams: 220, unitHint: "约6-8贯"),

        // 水果零食饮品
        .init(id: "apple", name: "苹果", aliases: ["红富士"], kcalPer100g: 52, defaultGrams: 200, unitHint: "约1个"),
        .init(id: "banana", name: "香蕉", aliases: [], kcalPer100g: 89, defaultGrams: 120, unitHint: "约1根"),
        .init(id: "orange", name: "橙子", aliases: ["橘子", "柚子", "砂糖橘"], kcalPer100g: 47, defaultGrams: 180, unitHint: "约1个"),
        .init(id: "avocado", name: "牛油果", aliases: [], kcalPer100g: 160, defaultGrams: 120, unitHint: "约1个"),
        .init(id: "nuts", name: "坚果", aliases: ["巴旦木", "核桃", "腰果", "每日坚果"], kcalPer100g: 580, defaultGrams: 25, unitHint: "约1小袋"),
        .init(id: "cake", name: "蛋糕", aliases: ["甜品", "提拉米苏", "慕斯", "芝士蛋糕"], kcalPer100g: 347, defaultGrams: 100, unitHint: "约1块"),
        .init(id: "americano", name: "美式咖啡", aliases: ["冰美式", "黑咖啡", "美式"], kcalPer100g: 4, defaultGrams: 350, unitHint: "约1杯"),
        .init(id: "latte", name: "拿铁", aliases: ["冰拿铁", "生椰拿铁", "卡布奇诺", "咖啡"], kcalPer100g: 52, defaultGrams: 350, unitHint: "约1大杯"),
        .init(id: "milk_tea", name: "奶茶", aliases: ["珍珠奶茶", "波霸奶茶", "果茶", "芝士奶盖"], kcalPer100g: 78, defaultGrams: 500, unitHint: "约1杯"),
        .init(id: "cola", name: "可乐", aliases: ["雪碧", "汽水", "橙汁"], kcalPer100g: 43, defaultGrams: 330, unitHint: "约1罐")
    ]

    /// 根据输入文本搜索匹配的食物候选（支持名称与别名模糊匹配，最多返回 limit 条）
    static func search(_ query: String, limit: Int = 5) -> [JieziFoodNutritionItem] {
        let cleaned = stripGramsToken(from: query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !cleaned.isEmpty, limit > 0 else { return [] }

        var exact: [JieziFoodNutritionItem] = []
        var prefix: [JieziFoodNutritionItem] = []
        var contains: [JieziFoodNutritionItem] = []

        for item in catalog {
            let candidates = [item.name] + item.aliases
            if candidates.contains(where: { $0.lowercased() == cleaned }) {
                exact.append(item)
            } else if candidates.contains(where: { $0.lowercased().hasPrefix(cleaned) || cleaned.hasPrefix($0.lowercased()) }) {
                prefix.append(item)
            } else if candidates.contains(where: { $0.lowercased().contains(cleaned) || cleaned.contains($0.lowercased()) }) {
                contains.append(item)
            }
        }
        return Array((exact + prefix + contains).prefix(limit))
    }

    /// 从文本中解析用户顺手输入的克数（例如 "鸡胸肉 150g" / "米饭200克" / "拿铁 350ml"）
    static func parseGrams(from text: String) -> Int? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|G|克|ml|ML|毫升)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let value = Double(text[range]),
              value.isFinite, value > 0 else {
            return nil
        }
        return min(max(Int(value.rounded()), 1), maxGrams)
    }

    /// 根据食物与克数估算热量（千卡），带防御性边界检查
    static func estimate(item: JieziFoodNutritionItem, grams: Int) -> Int {
        guard item.kcalPer100g.isFinite, item.kcalPer100g >= 0 else { return 0 }
        let safeGrams = min(max(grams, 0), maxGrams)
        let raw = item.kcalPer100g * Double(safeGrams) / 100.0
        guard raw.isFinite else { return 0 }
        return max(0, Int(raw.rounded()))
    }

    /// 便捷入口：直接根据输入文本和可选克数估算
    static func estimate(query: String, gramsOverride: Int? = nil) -> JieziFoodCalorieEstimate? {
        guard let best = search(query, limit: 1).first else { return nil }
        let grams = min(max(gramsOverride ?? parseGrams(from: query) ?? best.defaultGrams, 1), maxGrams)
        return JieziFoodCalorieEstimate(
            item: best,
            grams: grams,
            estimatedKcal: estimate(item: best, grams: grams)
        )
    }

    private static func stripGramsToken(from text: String) -> String {
        let pattern = #"\d+(?:\.\d+)?\s*(?:g|G|克|ml|ML|毫升)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

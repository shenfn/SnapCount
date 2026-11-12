# IMP-001 通用 CSV 导入解析

- 目标行为：把常见平台导出的 CSV 行转换为芥子财务导入草稿。
- 本轮范围：iOS CSV 解析、字段别名、金额/日期标准化、未知列保留、行级错误。
- 非范围：数据库写入、账户绑定、云同步、PWA、第三方账号接口和 TestFlight。
- 测试：`GenericImportCSVTests` 覆盖引号/逗号/换行、中文列名、负数收入、未知列和行级错误。
- 基线：`LocalPhase1DataModelTests` 26/26 通过。

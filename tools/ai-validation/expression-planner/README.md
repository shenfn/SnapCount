# Expression Planner 实验区

该目录用于独立维护“芥子表达规划器”的算法实验，不直接承载生产 Edge Function 代码。

设计文档：`docs/expression-planner-design-v0.1.md`

## 建议结构

```text
expression-planner/
  README.md
  schemas/
    scenario-v1.schema.json
    candidate-v1.schema.json
    expression-plan-v1.schema.json
    preference-memory-v1.schema.json
  configs/
    weights-v0.1.json
    surface-thresholds-v0.1.json
    policy-v0.1.json
  scenarios/
    qlhazycoder-weekend-session-001.json
  baselines/
    legacy-prompt.json
    current-voice.json
  evaluations/
  reports/
  changelog/
    algorithm-v0.1.md
```

## 目录职责

- `schemas/`：稳定数据契约。
- `configs/`：可调权重、阈值和策略，不与代码写死。
- `scenarios/`：连续用户场景与回归样本。
- `baselines/`：旧链路和当前链路的对照输出。
- `evaluations/`：机器评测结果。
- `reports/`：人工分析和版本对比报告。
- `changelog/`：每次算法调整的原因、样本和回归结果。

## 实验原则

1. 先离线，再 Shadow，最后接管生产展示。
2. 不用单条好文案证明算法有效，必须看连续场景。
3. 不只评语言质量，分别评事实、方向、位置、偏好和重复度。
4. 参数变化必须绑定算法版本和回归报告。
5. 用户个体差异进入偏好和状态，不硬编码成全局规则。

## 第一组实验

使用合成的 API 中转站周末四笔消费场景，同时运行：

1. 早期少规则 Prompt；
2. 当前信号驱动 Voice；
3. 候选事实 + 评分 + 表达计划。

第一阶段只输出候选、评分、淘汰原因和表达计划，不调用生产写入接口。

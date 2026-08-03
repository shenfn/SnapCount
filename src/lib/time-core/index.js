/**
 * time-core / index.js
 *
 * 唯一对外入口。业务代码只能从这里 import。
 *
 * 心智模型：
 *   - 内部单位：Instant = UTC epochMs (number)
 *   - 边界规则：进来（parseInstant）+ 出去（formatDisplay / diffHuman）都必须显式 tz
 *   - 禁止：new Date(str)、str.slice(0,5) 之类的裸字符串裁剪
 *
 * 相关 bug：08-01 星之柠案（transaction_time 存了 UTC 时分与北京日期错位）。
 */

export { isInstant, nowInstant, toInstant, toIsoUtc } from './instant.js'
export {
  DEFAULT_TZ,
  parseInstant,
  parseLocalYmd,
  zonedWallTimeToInstant,
  tzOffsetMs,
} from './parse.js'
export {
  zonedParts,
  formatDateKey,
  formatDisplay,
  formatRelativeDate,
  formatIsoZoned,
  WEEK_LABELS,
} from './format.js'
export { diffMs, diffHuman, diffStructured } from './diff.js'

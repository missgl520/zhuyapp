// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 导出所有实体
// 路径：lib/domain/entities/entities.dart
//
// 职责：一次性导出 domain/entities 下的全部实体，简化 import。
//
// 上游：所有需要实体类型的层（data / presentation / core）。
// 下游：message.dart、emotion.dart、affinity.dart。
//
// 关键点：这是一个 barrel 文件，只做 export，不要在此定义任何类型，
//   否则容易产生循环依赖。新增实体后记得在此追加 export。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// 消息实体（Message）。
export 'message.dart';

/// 情绪实体（Emotion）与情绪展示工具函数。
export 'emotion.dart';

/// 好感度实体（Affinity）。
export 'affinity.dart';

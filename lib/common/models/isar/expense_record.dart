import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

part 'expense_record.g.dart';

@collection
class ExpenseRecord {
  // 业务主键，使用 uuid
  String id = const Uuid().v7();

  // 数据库主键，使用 hash 业务主键
  @Id()
  int get isarId => fastHash(id);

  // 金额（单位：分，避免浮点精度问题）
  int amount = 0;

  // 消费分类（餐饮、交通、购物等）
  String category = '';

  // 备注
  String note = '';

  // 年月索引
  @Index()
  String get yM => '${time.year.toString()}/${time.month.toString()}';

  // 年月日索引
  @Index()
  String get yMd =>
      '${time.year.toString()}/${time.month.toString()}/${time.day.toString()}';

  // 日期
  @Index()
  DateTime time = DateTime.now();

  // 是否显示（用于删除软标记）
  @Index()
  bool show = true;

  ExpenseRecord();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'category': category,
      'note': note,
      'time': time.toIso8601String(),
      'show': show,
    };
  }

  factory ExpenseRecord.fromJson(Map<String, dynamic> json) {
    return ExpenseRecord()
      ..id = json['id'] as String
      ..amount = json['amount'] as int
      ..category = json['category'] as String
      ..note = json['note'] as String
      ..time = DateTime.parse(json['time'] as String)
      ..show = json['show'] as bool;
  }
}

int fastHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }
  return hash;
}

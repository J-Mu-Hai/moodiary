// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'guide_message.dart';

// **************************************************************************
// _IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, invalid_use_of_protected_member, lines_longer_than_80_chars, constant_identifier_names, avoid_js_rounded_ints, no_leading_underscores_for_local_identifiers, require_trailing_commas, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_in_if_null_operators, library_private_types_in_public_api, prefer_const_constructors
// ignore_for_file: type=lint

extension GetGuideMessageCollection on Isar {
  IsarCollection<int, GuideMessage> get guideMessages => this.collection();
}

const GuideMessageSchema = IsarGeneratedSchema(
  schema: IsarSchema(
    name: 'GuideMessage',
    idName: 'isarId',
    embedded: false,
    properties: [
      IsarPropertySchema(
        name: 'id',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'diaryId',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'role',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'kind',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'content',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'extra',
        type: IsarType.string,
      ),
      IsarPropertySchema(
        name: 'stage',
        type: IsarType.long,
      ),
      IsarPropertySchema(
        name: 'ts',
        type: IsarType.dateTime,
      ),
    ],
    indexes: [
      IsarIndexSchema(
        name: 'diaryId',
        properties: [
          "diaryId",
        ],
        unique: false,
        hash: false,
      ),
      IsarIndexSchema(
        name: 'ts',
        properties: [
          "ts",
        ],
        unique: false,
        hash: false,
      ),
    ],
  ),
  converter: IsarObjectConverter<int, GuideMessage>(
    serialize: serializeGuideMessage,
    deserialize: deserializeGuideMessage,
    deserializeProperty: deserializeGuideMessageProp,
  ),
  embeddedSchemas: [],
);

@isarProtected
int serializeGuideMessage(IsarWriter writer, GuideMessage object) {
  IsarCore.writeString(writer, 1, object.id);
  IsarCore.writeString(writer, 2, object.diaryId);
  IsarCore.writeString(writer, 3, object.role);
  IsarCore.writeString(writer, 4, object.kind);
  IsarCore.writeString(writer, 5, object.content);
  IsarCore.writeString(writer, 6, object.extra);
  IsarCore.writeLong(writer, 7, object.stage);
  IsarCore.writeLong(writer, 8, object.ts.toUtc().microsecondsSinceEpoch);
  return object.isarId;
}

@isarProtected
GuideMessage deserializeGuideMessage(IsarReader reader) {
  final object = GuideMessage();
  object.id = IsarCore.readString(reader, 1) ?? '';
  object.diaryId = IsarCore.readString(reader, 2) ?? '';
  object.role = IsarCore.readString(reader, 3) ?? '';
  object.kind = IsarCore.readString(reader, 4) ?? '';
  object.content = IsarCore.readString(reader, 5) ?? '';
  object.extra = IsarCore.readString(reader, 6) ?? '';
  object.stage = IsarCore.readLong(reader, 7);
  {
    final value = IsarCore.readLong(reader, 8);
    if (value == -9223372036854775808) {
      object.ts = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
    } else {
      object.ts =
          DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true).toLocal();
    }
  }
  return object;
}

@isarProtected
dynamic deserializeGuideMessageProp(IsarReader reader, int property) {
  switch (property) {
    case 1:
      return IsarCore.readString(reader, 1) ?? '';
    case 2:
      return IsarCore.readString(reader, 2) ?? '';
    case 3:
      return IsarCore.readString(reader, 3) ?? '';
    case 4:
      return IsarCore.readString(reader, 4) ?? '';
    case 5:
      return IsarCore.readString(reader, 5) ?? '';
    case 6:
      return IsarCore.readString(reader, 6) ?? '';
    case 7:
      return IsarCore.readLong(reader, 7);
    case 8:
      {
        final value = IsarCore.readLong(reader, 8);
        if (value == -9223372036854775808) {
          return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true).toLocal();
        } else {
          return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true)
              .toLocal();
        }
      }
    case 0:
      return IsarCore.readId(reader);
    default:
      throw ArgumentError('Unknown property: $property');
  }
}

sealed class _GuideMessageUpdate {
  bool call({
    required int isarId,
    String? id,
    String? diaryId,
    String? role,
    String? kind,
    String? content,
    String? extra,
    int? stage,
    DateTime? ts,
  });
}

class _GuideMessageUpdateImpl implements _GuideMessageUpdate {
  const _GuideMessageUpdateImpl(this.collection);

  final IsarCollection<int, GuideMessage> collection;

  @override
  bool call({
    required int isarId,
    Object? id = ignore,
    Object? diaryId = ignore,
    Object? role = ignore,
    Object? kind = ignore,
    Object? content = ignore,
    Object? extra = ignore,
    Object? stage = ignore,
    Object? ts = ignore,
  }) {
    return collection.updateProperties([
          isarId
        ], {
          if (id != ignore) 1: id as String?,
          if (diaryId != ignore) 2: diaryId as String?,
          if (role != ignore) 3: role as String?,
          if (kind != ignore) 4: kind as String?,
          if (content != ignore) 5: content as String?,
          if (extra != ignore) 6: extra as String?,
          if (stage != ignore) 7: stage as int?,
          if (ts != ignore) 8: ts as DateTime?,
        }) >
        0;
  }
}

sealed class _GuideMessageUpdateAll {
  int call({
    required List<int> isarId,
    String? id,
    String? diaryId,
    String? role,
    String? kind,
    String? content,
    String? extra,
    int? stage,
    DateTime? ts,
  });
}

class _GuideMessageUpdateAllImpl implements _GuideMessageUpdateAll {
  const _GuideMessageUpdateAllImpl(this.collection);

  final IsarCollection<int, GuideMessage> collection;

  @override
  int call({
    required List<int> isarId,
    Object? id = ignore,
    Object? diaryId = ignore,
    Object? role = ignore,
    Object? kind = ignore,
    Object? content = ignore,
    Object? extra = ignore,
    Object? stage = ignore,
    Object? ts = ignore,
  }) {
    return collection.updateProperties(isarId, {
      if (id != ignore) 1: id as String?,
      if (diaryId != ignore) 2: diaryId as String?,
      if (role != ignore) 3: role as String?,
      if (kind != ignore) 4: kind as String?,
      if (content != ignore) 5: content as String?,
      if (extra != ignore) 6: extra as String?,
      if (stage != ignore) 7: stage as int?,
      if (ts != ignore) 8: ts as DateTime?,
    });
  }
}

extension GuideMessageUpdate on IsarCollection<int, GuideMessage> {
  _GuideMessageUpdate get update => _GuideMessageUpdateImpl(this);

  _GuideMessageUpdateAll get updateAll => _GuideMessageUpdateAllImpl(this);
}

sealed class _GuideMessageQueryUpdate {
  int call({
    String? id,
    String? diaryId,
    String? role,
    String? kind,
    String? content,
    String? extra,
    int? stage,
    DateTime? ts,
  });
}

class _GuideMessageQueryUpdateImpl implements _GuideMessageQueryUpdate {
  const _GuideMessageQueryUpdateImpl(this.query, {this.limit});

  final IsarQuery<GuideMessage> query;
  final int? limit;

  @override
  int call({
    Object? id = ignore,
    Object? diaryId = ignore,
    Object? role = ignore,
    Object? kind = ignore,
    Object? content = ignore,
    Object? extra = ignore,
    Object? stage = ignore,
    Object? ts = ignore,
  }) {
    return query.updateProperties(limit: limit, {
      if (id != ignore) 1: id as String?,
      if (diaryId != ignore) 2: diaryId as String?,
      if (role != ignore) 3: role as String?,
      if (kind != ignore) 4: kind as String?,
      if (content != ignore) 5: content as String?,
      if (extra != ignore) 6: extra as String?,
      if (stage != ignore) 7: stage as int?,
      if (ts != ignore) 8: ts as DateTime?,
    });
  }
}

extension GuideMessageQueryUpdate on IsarQuery<GuideMessage> {
  _GuideMessageQueryUpdate get updateFirst =>
      _GuideMessageQueryUpdateImpl(this, limit: 1);

  _GuideMessageQueryUpdate get updateAll => _GuideMessageQueryUpdateImpl(this);
}

class _GuideMessageQueryBuilderUpdateImpl implements _GuideMessageQueryUpdate {
  const _GuideMessageQueryBuilderUpdateImpl(this.query, {this.limit});

  final QueryBuilder<GuideMessage, GuideMessage, QOperations> query;
  final int? limit;

  @override
  int call({
    Object? id = ignore,
    Object? diaryId = ignore,
    Object? role = ignore,
    Object? kind = ignore,
    Object? content = ignore,
    Object? extra = ignore,
    Object? stage = ignore,
    Object? ts = ignore,
  }) {
    final q = query.build();
    try {
      return q.updateProperties(limit: limit, {
        if (id != ignore) 1: id as String?,
        if (diaryId != ignore) 2: diaryId as String?,
        if (role != ignore) 3: role as String?,
        if (kind != ignore) 4: kind as String?,
        if (content != ignore) 5: content as String?,
        if (extra != ignore) 6: extra as String?,
        if (stage != ignore) 7: stage as int?,
        if (ts != ignore) 8: ts as DateTime?,
      });
    } finally {
      q.close();
    }
  }
}

extension GuideMessageQueryBuilderUpdate
    on QueryBuilder<GuideMessage, GuideMessage, QOperations> {
  _GuideMessageQueryUpdate get updateFirst =>
      _GuideMessageQueryBuilderUpdateImpl(this, limit: 1);

  _GuideMessageQueryUpdate get updateAll =>
      _GuideMessageQueryBuilderUpdateImpl(this);
}

extension GuideMessageQueryFilter
    on QueryBuilder<GuideMessage, GuideMessage, QFilterCondition> {
  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      idGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      idLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 1,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 1,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 1,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> idIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      idIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 1,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 2,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 2,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 2,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      diaryIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 2,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 3,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 3,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> roleMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 3,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      roleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 3,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 4,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 4,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> kindMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 4,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      kindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 4,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 5,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 5,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 5,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      contentIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 5,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraGreaterThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraGreaterThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraLessThan(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraLessThanOrEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraBetween(
    String lower,
    String upper, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 6,
          lower: lower,
          upper: upper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        StartsWithCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EndsWithCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraContains(
      String value,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        ContainsCondition(
          property: 6,
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> extraMatches(
      String pattern,
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        MatchesCondition(
          property: 6,
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const EqualCondition(
          property: 6,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      extraIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const GreaterCondition(
          property: 6,
          value: '',
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> stageEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      stageGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      stageGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> stageLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      stageLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 7,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> stageBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 7,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> tsEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> tsGreaterThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      tsGreaterThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> tsLessThan(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      tsLessThanOrEqualTo(
    DateTime value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 8,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> tsBetween(
    DateTime lower,
    DateTime upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 8,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> isarIdEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        EqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      isarIdGreaterThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      isarIdGreaterThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        GreaterOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      isarIdLessThan(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition>
      isarIdLessThanOrEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        LessOrEqualCondition(
          property: 0,
          value: value,
        ),
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterFilterCondition> isarIdBetween(
    int lower,
    int upper,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        BetweenCondition(
          property: 0,
          lower: lower,
          upper: upper,
        ),
      );
    });
  }
}

extension GuideMessageQueryObject
    on QueryBuilder<GuideMessage, GuideMessage, QFilterCondition> {}

extension GuideMessageQuerySortBy
    on QueryBuilder<GuideMessage, GuideMessage, QSortBy> {
  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByIdDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        1,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByDiaryId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByDiaryIdDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        2,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByRole(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByRoleDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        3,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByKind(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByKindDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        4,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByContentDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        5,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByExtra(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        6,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByExtraDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(
        6,
        sort: Sort.desc,
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByStage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByStageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByTs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByTsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> sortByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }
}

extension GuideMessageQuerySortThenBy
    on QueryBuilder<GuideMessage, GuideMessage, QSortThenBy> {
  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByIdDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(1, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByDiaryId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByDiaryIdDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(2, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByRole(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByRoleDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(3, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByKind(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByKindDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(4, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByContentDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(5, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByExtra(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByExtraDesc(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(6, sort: Sort.desc, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByStage() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByStageDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(7, sort: Sort.desc);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByTs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByTsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(8, sort: Sort.desc);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByIsarId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterSortBy> thenByIsarIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(0, sort: Sort.desc);
    });
  }
}

extension GuideMessageQueryWhereDistinct
    on QueryBuilder<GuideMessage, GuideMessage, QDistinct> {
  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctById(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(1, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByDiaryId(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(2, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByRole(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(3, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByKind(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(4, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByContent(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(5, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByExtra(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(6, caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByStage() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(7);
    });
  }

  QueryBuilder<GuideMessage, GuideMessage, QAfterDistinct> distinctByTs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(8);
    });
  }
}

extension GuideMessageQueryProperty1
    on QueryBuilder<GuideMessage, GuideMessage, QProperty> {
  QueryBuilder<GuideMessage, String, QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<GuideMessage, String, QAfterProperty> diaryIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<GuideMessage, String, QAfterProperty> roleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<GuideMessage, String, QAfterProperty> kindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<GuideMessage, String, QAfterProperty> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<GuideMessage, String, QAfterProperty> extraProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<GuideMessage, int, QAfterProperty> stageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<GuideMessage, DateTime, QAfterProperty> tsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<GuideMessage, int, QAfterProperty> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }
}

extension GuideMessageQueryProperty2<R>
    on QueryBuilder<GuideMessage, R, QAfterProperty> {
  QueryBuilder<GuideMessage, (R, String), QAfterProperty> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<GuideMessage, (R, String), QAfterProperty> diaryIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<GuideMessage, (R, String), QAfterProperty> roleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<GuideMessage, (R, String), QAfterProperty> kindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<GuideMessage, (R, String), QAfterProperty> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<GuideMessage, (R, String), QAfterProperty> extraProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<GuideMessage, (R, int), QAfterProperty> stageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<GuideMessage, (R, DateTime), QAfterProperty> tsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<GuideMessage, (R, int), QAfterProperty> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }
}

extension GuideMessageQueryProperty3<R1, R2>
    on QueryBuilder<GuideMessage, (R1, R2), QAfterProperty> {
  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(1);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> diaryIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(2);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> roleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(3);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> kindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(4);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> contentProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(5);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, String), QOperations> extraProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(6);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, int), QOperations> stageProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(7);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, DateTime), QOperations> tsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(8);
    });
  }

  QueryBuilder<GuideMessage, (R1, R2, int), QOperations> isarIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addProperty(0);
    });
  }
}

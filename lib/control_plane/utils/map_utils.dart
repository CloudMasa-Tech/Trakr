/// Utility to safely convert any Map (including JS interop LinkedMap<Object?, Object?>)
/// into a Map<String, dynamic> by recursively converting keys and values.
Map<String, dynamic> asStringKeyedMap(dynamic input) {
  if (input == null) {
    return <String, dynamic>{};
  }
  if (input is Map) {
    return _convertMap(input);
  }
  return <String, dynamic>{};
}

/// Converts a Map with arbitrary key/value types to Map<String, dynamic>.
Map<String, dynamic> _convertMap(Map map) {
  final result = <String, dynamic>{};
  for (final entry in map.entries) {
    final key = entry.key?.toString() ?? '';
    final value = _convertValue(entry.value);
    result[key] = value;
  }
  return result;
}

/// Recursively converts a value, handling nested Maps and Lists.
dynamic _convertValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return _convertMap(value);
  }
  if (value is List) {
    return value.map(_convertValue).toList();
  }
  return value;
}
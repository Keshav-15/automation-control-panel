extension IterableExtension<T> on Iterable<T> {
  /// Insert any item\<T> inBetween the list items
  List<T> insertBetween(T item) => expand((e) sync* {
    yield item;
    yield e;
  }).skip(1).toList(growable: false);

  T? firstWhereOrNull(bool Function(T element) test) {
    for (var element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

/// Retains a longest ordered subsequence of stable, unique row IDs.
///
/// Mapping the old IDs to their new positions turns the common subsequence
/// into an increasing subsequence. This uses O(n log n) time and O(n) memory,
/// rather than allocating a matrix on the UI isolate for each status update.
Set<T> retainedPaymentLinkEntryIds<T>(List<T> before, List<T> after) {
  final positions = {for (final (index, id) in after.indexed) id: index};
  final ids = <T>[];
  final values = <int>[];
  for (final id in before) {
    final position = positions[id];
    if (position == null) continue;
    ids.add(id);
    values.add(position);
  }
  final tails = <int>[];
  final previous = List<int>.filled(values.length, -1);
  for (var index = 0; index < values.length; index++) {
    var low = 0;
    var high = tails.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (values[tails[middle]] < values[index]) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    if (low > 0) previous[index] = tails[low - 1];
    if (low == tails.length) {
      tails.add(index);
    } else {
      tails[low] = index;
    }
  }
  final retained = <T>{};
  var index = tails.isEmpty ? -1 : tails.last;
  while (index >= 0) {
    retained.add(ids[index]);
    index = previous[index];
  }
  return retained;
}

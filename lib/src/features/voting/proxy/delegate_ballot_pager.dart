import 'package:flutter/foundation.dart';

/// Fetches the page of one round's delegate ballot list after `startAfter`.
typedef DelegateBallotPageFetch = Future<Uint8List> Function(int startAfter);

/// Each round's whole delegate ballot list (contract §8 `DelegateBallots`),
/// fetched page by page and kept for [maxAge]. The delegator client and
/// delegate mode both page through this.
class DelegateBallotPager {
  /// Creates the pager. [nextStartAfter] checks the page fetched with
  /// `startAfter` and says where the next one starts, null on the last;
  /// [tooManyPages] is thrown once a list passes [maxPages].
  DelegateBallotPager({
    required this.maxAge,
    required DateTime Function() clock,
    required Future<int?> Function(
      String roundId,
      int startAfter,
      Uint8List page,
    )
    nextStartAfter,
    required Exception Function() tooManyPages,
  }) : _clock = clock,
       _nextStartAfter = nextStartAfter,
       _tooManyPages = tooManyPages;

  /// Most pages one round's ballot list may take: 1,000 ballots each.
  static const maxPages = 1000;

  /// How long a fetched list serves repeated reads.
  final Duration maxAge;

  final DateTime Function() _clock;
  final Future<int?> Function(String roundId, int startAfter, Uint8List page)
  _nextStartAfter;
  final Exception Function() _tooManyPages;
  final _lists = <String, ({DateTime at, List<Uint8List> pages})>{};

  /// [roundId]'s whole list, fetched again once older than [maxAge] or when
  /// [fresh]. [open] is called only to fetch, and hands back the page fetch.
  Future<List<Uint8List>> pages(
    String roundId, {
    required Future<DelegateBallotPageFetch> Function() open,
    bool fresh = false,
  }) async {
    final now = _clock();
    final cached = _lists[roundId];
    if (!fresh && cached != null && now.difference(cached.at) < maxAge) {
      return cached.pages;
    }
    final fetch = await open();
    final pages = <Uint8List>[];
    for (int? startAfter = 0; startAfter != null;) {
      if (pages.length >= maxPages) throw _tooManyPages();
      final page = await fetch(startAfter);
      startAfter = await _nextStartAfter(roundId, startAfter, page);
      pages.add(page);
    }
    final unmodifiable = List<Uint8List>.unmodifiable(pages);
    _lists[roundId] = (at: now, pages: unmodifiable);
    return unmodifiable;
  }

  /// Drops [roundId]'s list, so the next read fetches it again.
  void forget(String roundId) => _lists.remove(roundId);
}

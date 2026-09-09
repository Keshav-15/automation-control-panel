import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

typedef LoadMore = Future Function();

typedef OnLoadMore = void Function();

typedef ItemCount = int Function();

typedef HasMore = bool Function();

typedef OnLoadMoreFinished = void Function();

class IncrementallyLoadingListView extends StatefulWidget {
  final HasMore hasMore;
  final LoadMore loadMore;
  final int loadMoreOffsetFromBottom;
  final Axis scrollDirection;
  final bool reverse;
  final ScrollController? controller;
  final bool? primary;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final IndexedWidgetBuilder itemBuilder;
  final ItemCount itemCount;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final double? cacheExtent;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  /// A callback that is triggered when more items are being loaded
  final OnLoadMore? onLoadMore;

  /// A callback that is triggered when items have finished being loaded
  final OnLoadMoreFinished? onLoadMoreFinished;

  const IncrementallyLoadingListView({
    super.key,
    required this.hasMore,
    required this.loadMore,
    this.loadMoreOffsetFromBottom = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.controller,
    this.primary,
    this.physics,
    this.shrinkWrap = false,
    this.padding,
    this.itemExtent,
    required this.itemBuilder,
    required this.itemCount,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.cacheExtent,
    this.onLoadMore,
    this.onLoadMoreFinished,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
  });

  @override
  IncrementallyLoadingListViewState createState() {
    return IncrementallyLoadingListViewState();
  }
}

class IncrementallyLoadingListViewState
    extends State<IncrementallyLoadingListView> {
  bool _loadingMore = false;
  final PublishSubject<bool> _loadingMoreSubject = PublishSubject<bool>();
  Stream<bool>? _loadingMoreStream;

  IncrementallyLoadingListViewState() {
    _loadingMoreStream = _loadingMoreSubject.switchMap(
      (shouldLoadMore) => loadMore(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _loadingMoreStream,
      builder: (context, snapshot) {
        return ListView.builder(
          keyboardDismissBehavior: widget.keyboardDismissBehavior,
          key: widget.key,
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          controller: widget.controller,
          primary: widget.primary,
          physics: widget.physics,
          shrinkWrap: widget.shrinkWrap,
          padding: widget.padding,
          itemExtent: widget.itemExtent,
          itemBuilder: (itemBuilderContext, index) {
            if (!_loadingMore &&
                index ==
                    widget.itemCount() - widget.loadMoreOffsetFromBottom - 1 &&
                widget.hasMore()) {
              _loadingMore = true;
              _loadingMoreSubject.add(true);
            }
            return widget.itemBuilder(itemBuilderContext, index);
          },
          itemCount: widget.itemCount(),
          addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
          addRepaintBoundaries: widget.addRepaintBoundaries,
          cacheExtent: widget.cacheExtent,
        );
      },
    );
  }

  Stream<bool> loadMore() async* {
    yield _loadingMore;
    if (widget.onLoadMore != null) {
      widget.onLoadMore!();
    }
    await widget.loadMore();
    _loadingMore = false;
    yield _loadingMore;
    if (widget.onLoadMoreFinished != null) {
      widget.onLoadMoreFinished!();
    }
  }

  @override
  void dispose() {
    _loadingMoreSubject.close();
    super.dispose();
  }
}

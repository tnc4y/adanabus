import 'favorite_line_item.dart';
import 'favorite_route_item.dart';
import 'favorite_stop_item.dart';

enum FavoriteHomeEntryKind { line, stop, route }

class FavoriteHomeEntry {
  const FavoriteHomeEntry._({
    required this.kind,
    required this.key,
    required this.title,
    required this.subtitle,
    this.line,
    this.stop,
    this.route,
  });

  factory FavoriteHomeEntry.line(FavoriteLineItem line) {
    return FavoriteHomeEntry._(
      kind: FavoriteHomeEntryKind.line,
      key: 'line:${line.routeCode}',
      title: line.routeCode,
      subtitle: line.routeName,
      line: line,
    );
  }

  factory FavoriteHomeEntry.stop(FavoriteStopItem stop) {
    return FavoriteHomeEntry._(
      kind: FavoriteHomeEntryKind.stop,
      key: 'stop:${stop.stopId}',
      title: stop.stopName,
      subtitle: 'Durak ${stop.stopId}',
      stop: stop,
    );
  }

  factory FavoriteHomeEntry.route(FavoriteRouteItem route) {
    return FavoriteHomeEntry._(
      kind: FavoriteHomeEntryKind.route,
      key: 'route:${route.key}',
      title: '${route.startStopName} -> ${route.endStopName}',
      subtitle: 'Rota ${route.startStopId} -> ${route.endStopId}',
      route: route,
    );
  }

  final FavoriteHomeEntryKind kind;
  final String key;
  final String title;
  final String subtitle;
  final FavoriteLineItem? line;
  final FavoriteStopItem? stop;
  final FavoriteRouteItem? route;
}

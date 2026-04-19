import 'bus_vehicle.dart';

class BusOption {
  const BusOption({
    required this.displayRouteCode,
    required this.directions,
    required this.names,
  });

  final String displayRouteCode;
  final List<String> directions;
  final List<String> names;

  static List<BusOption> fromBuses(List<BusVehicle> buses) {
    final grouped = <String, BusOptionBuilder>{};

    for (final bus in buses) {
      if (bus.displayRouteCode.isEmpty) {
        continue;
      }
      final entry = grouped.putIfAbsent(
        bus.displayRouteCode,
        () => BusOptionBuilder(bus.displayRouteCode),
      );
      if (bus.direction == '0' || bus.direction == '1') {
        entry.directions.add(bus.direction);
      }
      if (bus.name.isNotEmpty) {
        entry.names.add(bus.name);
      }
    }

    final result = grouped.values
        .map(
          (entry) => BusOption(
            displayRouteCode: entry.displayRouteCode,
            directions: entry.directions.toList()..sort(),
            names: entry.names.toList(),
          ),
        )
        .toList();

    result.sort((a, b) => a.displayRouteCode.compareTo(b.displayRouteCode));
    return result;
  }
}

class BusOptionBuilder {
  BusOptionBuilder(this.displayRouteCode);

  final String displayRouteCode;
  final Set<String> directions = <String>{};
  final Set<String> names = <String>{};
}

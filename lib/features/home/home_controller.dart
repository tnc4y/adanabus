import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_option.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/services/adana_api_service.dart';

class HomeController extends ChangeNotifier {
  HomeController({AdanaApiService? apiService})
      : _apiService = apiService ?? AdanaApiService();

  static const LatLng adanaCenter = LatLng(37.0000, 35.3213);

  final AdanaApiService _apiService;

  final List<BusVehicle> _allBuses = <BusVehicle>[];
  List<BusVehicle> _visibleBuses = <BusVehicle>[];

  bool isLoading = false;
  String? errorMessage;
  String query = '';
  String selectedRoute = 'all';
  String selectedDirection = 'all';
  String selectedRouteName = '';
  BusVehicle? selectedBus;

  List<BusVehicle> get visibleBuses => _visibleBuses;
  List<BusVehicle> get busesWithLocation =>
      _visibleBuses.where((bus) => bus.hasLocation).toList();

  List<BusOption> get routeOptions => BusOption.fromBuses(_allBuses);

  bool get isDemoMode => _apiService.isDemoMode;

  LatLng get currentCenter {
    final bus = selectedBus;
    if (bus == null || !bus.hasLocation) {
      return adanaCenter;
    }
    return LatLng(bus.latitude!, bus.longitude!);
  }

  Future<void> initialize() async {
    await refresh();
  }

  Future<void> refresh() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final buses = await _apiService.fetchBuses();
      _allBuses
        ..clear()
        ..addAll(buses);
      _applyFilters();
    } catch (error) {
      errorMessage = error.toString();
      _allBuses.clear();
      _visibleBuses = <BusVehicle>[];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    query = value;
    _applyFilters();
    notifyListeners();
  }

  void setRouteFilter(String routeCode) {
    selectedRoute = routeCode;
    _applyFilters();
    notifyListeners();
  }

  void setDirectionFilter(String direction) {
    selectedDirection = direction;
    _applyFilters();
    notifyListeners();
  }

  void setLineSelection({
    required String routeCode,
    required String direction,
    required String routeName,
  }) {
    selectedRoute = routeCode;
    selectedDirection = direction;
    selectedRouteName = routeName;
    _applyFilters();
    notifyListeners();
  }

  void selectBus(BusVehicle bus) {
    selectedBus = bus;
    notifyListeners();
  }

  void _applyFilters() {
    final normalizedQuery = query.toLowerCase().trim();

    _visibleBuses = _allBuses.where((bus) {
      final routeMatch = selectedRoute == 'all' ||
          bus.displayRouteCode.toLowerCase() == selectedRoute.toLowerCase();
      if (!routeMatch) {
        return false;
      }

      final directionMatch =
          selectedDirection == 'all' || bus.direction == selectedDirection;
      if (!directionMatch) {
        return false;
      }

      if (normalizedQuery.isEmpty) {
        return true;
      }

      return bus.id.toLowerCase().contains(normalizedQuery) ||
          bus.name.toLowerCase().contains(normalizedQuery) ||
          bus.displayRouteCode.toLowerCase().contains(normalizedQuery) ||
          bus.routeCode.toLowerCase().contains(normalizedQuery);
    }).toList();

    if (selectedBus != null && !_visibleBuses.contains(selectedBus)) {
      selectedBus = null;
    }
  }
}

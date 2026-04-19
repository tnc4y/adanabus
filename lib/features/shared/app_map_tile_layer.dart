import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

TileLayer buildAppMapTileLayer(
  BuildContext context, {
  double maxZoom = 19,
  String userAgentPackageName = 'com.example.adanabus',
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isDark) {
    return TileLayer(
      urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      maxZoom: maxZoom,
      userAgentPackageName: userAgentPackageName,
    );
  }

  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    maxZoom: maxZoom,
    userAgentPackageName: userAgentPackageName,
  );
}

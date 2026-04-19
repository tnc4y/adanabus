class FavoriteLineItem {
  const FavoriteLineItem({
    required this.routeCode,
    required this.routeName,
  });

  final String routeCode;
  final String routeName;

  String get key => routeCode;

  Map<String, String> toJson() {
    return <String, String>{
      'routeCode': routeCode,
      'routeName': routeName,
    };
  }

  factory FavoriteLineItem.fromJson(Map<String, dynamic> json) {
    return FavoriteLineItem(
      routeCode: (json['routeCode'] ?? '').toString(),
      routeName: (json['routeName'] ?? '').toString(),
    );
  }
}

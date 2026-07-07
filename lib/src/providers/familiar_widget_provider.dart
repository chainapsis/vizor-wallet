import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/familiar_widget_service.dart';

final familiarWidgetServiceProvider = Provider<FamiliarWidgetService>((ref) {
  return FamiliarWidgetService();
});

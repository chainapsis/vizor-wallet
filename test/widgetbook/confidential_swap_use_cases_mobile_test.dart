@Tags(['mobile'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'confidential_swap_use_cases_test.dart' as shared;

// The shared tests branch on the form factor but carry no tag, so the mobile
// lane would never select them. This runs them there.
void main() => shared.main();

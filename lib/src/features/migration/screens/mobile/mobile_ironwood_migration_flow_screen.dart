import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart'
    show
        CircularProgressIndicator,
        Dialog,
        Divider,
        Scaffold,
        VerticalDivider,
        showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/sync_status_label.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../models/ironwood_migration_presentation.dart';
import '../../providers/ironwood_migration_announcement_provider.dart';
import '../../providers/ironwood_migration_coordinator_provider.dart';
import '../../services/ironwood_migration_service.dart';
import '../../widgets/ironwood_migration_shimmer_text.dart';
import '../ironwood_migration_flow_screen.dart';

part 'mobile_ironwood_migration_models.dart';
part 'mobile_ironwood_migration_routes.dart';
part 'mobile_ironwood_migration_intro_options.dart';
part 'mobile_ironwood_migration_analyzing.dart';
part 'mobile_ironwood_migration_review.dart';
part 'mobile_ironwood_migration_live_states.dart';
part 'mobile_ironwood_migration_fallbacks.dart';
part 'mobile_ironwood_migration_status_scaffold.dart';
part 'mobile_ironwood_migration_status_presentation.dart';
part 'mobile_ironwood_migration_status_waiting.dart';
part 'mobile_ironwood_migration_status_active.dart';
part 'mobile_ironwood_migration_status_footer.dart';
part 'mobile_ironwood_migration_step_scaffold.dart';
part 'mobile_ironwood_migration_step_hero_process.dart';
part 'mobile_ironwood_migration_step_options.dart';
part 'mobile_ironwood_migration_step_plan.dart';
part 'mobile_ironwood_migration_step_progress_parts.dart';
part 'mobile_ironwood_migration_step_review_card.dart';

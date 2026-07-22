import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Colors,
        CircularProgressIndicator,
        Dialog,
        Divider,
        LinearProgressIndicator,
        Scaffold,
        showDialog;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/primitives.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/wallet/keystone.dart' as rust_keystone_wallet;
import '../../../services/qr_scanner.dart';
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../keystone/widgets/keystone_qr_scanner_card.dart';
import '../models/ironwood_migration_presentation.dart';
import '../providers/ironwood_migration_announcement_provider.dart';
import '../providers/ironwood_migration_coordinator_provider.dart';
import '../services/ironwood_migration_service.dart';
import '../widgets/mobile/mobile_ironwood_keystone_signing_view.dart';

part 'ironwood_migration_flow/models.dart';
part 'ironwood_migration_flow/routes.dart';
part 'ironwood_migration_flow/keystone_signing.dart';
part 'ironwood_migration_flow/shell_intro_options.dart';
part 'ironwood_migration_flow/private_status.dart';
part 'ironwood_migration_flow/private_review.dart';
part 'ironwood_migration_flow/migration_progress_segments.dart';
part 'ironwood_migration_flow/migration_batch_status.dart';
part 'ironwood_migration_flow/transfer_status.dart';
part 'ironwood_migration_flow/review_plan.dart';
part 'ironwood_migration_flow/legacy_status.dart';
part 'ironwood_migration_flow/shared_widgets.dart';

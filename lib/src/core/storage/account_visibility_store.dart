import 'dart:convert';
import 'dart:math';

import '../../rust/api/secret.dart' as secret;
import 'app_secure_store.dart';

const accountVisibilityStorageKey = 'zcash_mobile_account_visibility_v1';

class MobileAccountVisibilityRule {
  const MobileAccountVisibilityRule({
    required this.id,
    required this.verifier,
    required this.accountIds,
  });

  final String id;
  final String verifier;
  final Set<String> accountIds;
}

class MobileAccountVisibilityConfig {
  const MobileAccountVisibilityConfig({this.salt, this.rules = const []});

  final String? salt;
  final List<MobileAccountVisibilityRule> rules;

  static MobileAccountVisibilityConfig decode(String? stored) {
    if (stored == null) return const MobileAccountVisibilityConfig();
    final data = jsonDecode(stored) as Map<String, dynamic>;
    final salt = data['salt'] as String;
    if (data['version'] != 1 || base64Decode(salt).length != 32) {
      throw const FormatException('Invalid account visibility settings');
    }
    final assigned = <String>{};
    final ruleIds = <String>{};
    final verifiers = <String>{};
    final rules = <MobileAccountVisibilityRule>[];
    for (final raw in data['rules'] as List<dynamic>) {
      final rule = raw as Map<String, dynamic>;
      final id = rule['id'] as String;
      final verifier = rule['verifier'] as String;
      final ids = Set<String>.unmodifiable(
        (rule['accounts'] as List<dynamic>).cast<String>(),
      );
      if (id.isEmpty ||
          !ruleIds.add(id) ||
          verifier.isEmpty ||
          !verifiers.add(verifier) ||
          ids.isEmpty ||
          ids.any((uuid) => uuid.isEmpty || !assigned.add(uuid))) {
        throw const FormatException('Invalid account visibility rule');
      }
      rules.add(
        MobileAccountVisibilityRule(
          id: id,
          verifier: verifier,
          accountIds: ids,
        ),
      );
    }
    return MobileAccountVisibilityConfig(
      salt: salt,
      rules: List.unmodifiable(rules),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'salt': salt,
    'rules': [
      for (final rule in rules)
        {
          'id': rule.id,
          'verifier': rule.verifier,
          'accounts': rule.accountIds.toList(),
        },
    ],
  });

  MobileAccountVisibilityRule? rule(String? id) {
    for (final rule in rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  Set<String> get assignedIds => {for (final rule in rules) ...rule.accountIds};

  bool allows(String uuid, String? ruleId) => ruleId == null
      ? !rules.any((rule) => rule.accountIds.contains(uuid))
      : (rule(ruleId)?.accountIds.contains(uuid) ?? false);
}

class MobileAccountVisibilityStore {
  MobileAccountVisibilityStore(this._store);

  final AppSecureStore _store;
  static final _unconfiguredSalt = base64Encode(List<int>.filled(32, 0));

  Future<MobileAccountVisibilityConfig> read() async {
    final stored = await _store.readPlain(accountVisibilityStorageKey);
    try {
      return MobileAccountVisibilityConfig.decode(stored);
    } catch (_) {
      // Decoding exceptions can include raw input in their diagnostics.
      throw const FormatException('Invalid account visibility settings');
    }
  }

  Future<void> write(MobileAccountVisibilityConfig configuration) =>
      _store.writePlain(accountVisibilityStorageKey, configuration.encode());

  static bool validCode(String code) => RegExp(r'^[0-9]{6}$').hasMatch(code);

  static String randomToken(int length) {
    final random = Random.secure();
    return base64Encode(List.generate(length, (_) => random.nextInt(256)));
  }

  Future<String> verifier(String code, String salt) =>
      secret.deriveSecretPasswordVerifier(
        password: 'vizor-account-visibility:$code',
        saltBase64: salt,
      );

  Future<MobileAccountVisibilityRule?> match(
    MobileAccountVisibilityConfig configuration,
    String code,
  ) async {
    if (!validCode(code)) return null;
    // Use the same derivation even when no alternate code has been configured.
    final derived = await verifier(
      code,
      configuration.salt ?? _unconfiguredSalt,
    );
    MobileAccountVisibilityRule? matched;
    for (final rule in configuration.rules) {
      if (rule.verifier == derived) matched = rule;
    }
    return matched;
  }
}

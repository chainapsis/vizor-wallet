import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/storage/png_save_location.dart';
import 'payment_link_recovery_store.dart';
import 'payment_link_sharing.dart';

/// Returns false when the native save panel is cancelled. URI preparation
/// finishes before the panel opens, so a failed member cannot produce a file.
Future<bool> exportPaymentLinkBatchCsv(
  List<PaymentLinkRecoveryRecord> members,
) async {
  final csv = await preparePaymentLinkBatchCsv(members);
  final date = DateTime.now().toLocal().toIso8601String().substring(0, 10);
  final path = await pickSaveLocation(
    suggestedName: 'vizor-gift-cards-$date.csv',
    type: const XTypeGroup(
      label: 'CSV file',
      extensions: ['csv'],
      mimeTypes: ['text/csv'],
      uniformTypeIdentifiers: ['public.comma-separated-values-text'],
    ),
  );
  if (path == null) return false;
  await File(path).writeAsBytes(utf8.encode(csv), flush: true);
  return true;
}

/// Validates every retained bearer link before composing any CSV bytes.
Future<String> preparePaymentLinkBatchCsv(
  List<PaymentLinkRecoveryRecord> members,
) async {
  // The store already guarantees the count and distinct addresses.
  final txid = members.first.fundingTxids?.trim();
  if (!isCompletePaymentLinkBatch(members) ||
      txid == null ||
      txid.isEmpty ||
      members.any(
        (record) =>
            record.fundingTxids?.trim() != txid ||
            (record.state != PaymentLinkRecoveryState.funded &&
                record.state != PaymentLinkRecoveryState.shared),
      )) {
    throw StateError('The Gift Card batch is not ready to export.');
  }
  final ordered = [...members]
    ..sort((a, b) => a.batchIndex!.compareTo(b.batchIndex!));
  final lines = <String>['card_number,amount_zec,link'];
  for (final record in ordered) {
    final uri = await preparePaymentLinkShareUri(record.link);
    lines.add(
      '${record.batchIndex},${_csv(formatZecAmount(record.link.amountZatoshi))},${_csv(uri.toString())}',
    );
  }
  return '${lines.join('\r\n')}\r\n';
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

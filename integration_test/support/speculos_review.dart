import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<bool> approveNextSpeculosReview(String apiUrl) async {
  final client = HttpClient();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  var reviewStarted = false;
  try {
    while (DateTime.now().isBefore(deadline)) {
      final screen = await _currentScreenText(client, apiUrl);
      final normalized = screen.toLowerCase();
      if (normalized.contains('review') ||
          normalized.contains('export') ||
          normalized.contains('viewing key')) {
        reviewStarted = true;
      }
      if (reviewStarted) {
        if (normalized.contains('approve') ||
            normalized.contains('accept') ||
            normalized.contains('confirm') ||
            normalized.contains('sign transaction')) {
          await _pressButton(client, apiUrl, 'both');
          return true;
        }
        await _pressButton(
          client,
          apiUrl,
          normalized.contains('cancel') ? 'left' : 'right',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw TimeoutException('Speculos review did not become approvable.');
  } finally {
    client.close();
  }
}

Future<String> _currentScreenText(HttpClient client, String apiUrl) async {
  final request = await client.getUrl(
    Uri.parse('$apiUrl/events?currentscreenonly=true'),
  );
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos events returned HTTP ${response.statusCode}.',
    );
  }
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final events = decoded['events']! as List<dynamic>;
  return events
      .cast<Map<String, dynamic>>()
      .map((event) => event['text'])
      .whereType<String>()
      .join(' ');
}

Future<void> _pressButton(
  HttpClient client,
  String apiUrl,
  String button,
) async {
  final request = await client.postUrl(Uri.parse('$apiUrl/button/$button'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'action': 'press-and-release'}));
  final response = await request.close();
  await response.drain<void>();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Speculos button returned HTTP ${response.statusCode}.',
    );
  }
}

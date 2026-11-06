import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/rpc_endpoint_latency_provider.dart';

/// Describes the resolved server, never Automatic's compatibility URL.
String automaticEndpointDetailLabel(
  RpcEndpointFailoverState effective,
  RpcEndpointLatencyState latencies,
) {
  if (!effective.automaticReady) return 'Selecting an endpoint…';
  final endpoint = effective.current;
  final sample = latencies.sampleForUrl(endpoint.normalizedLightwalletdUrl);
  return [endpoint.hostPort, if (sample != null) sample.label].join(' · ');
}

// Isolated direct-gift integration test transport. Never points at mainnet.
const http2 = require('node:http2');
const http = require('node:http');
let calls = [];
let failNextSubmission = false;

// Decode only the height fields needed to prove a bounded GetBlockRange.
function fields(buffer) {
  let position = 0;
  const result = new Map();
  const varint = () => {
    let value = 0, shift = 0, byte;
    do {
      byte = buffer[position++];
      value += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    return value;
  };
  while (position < buffer.length) {
    const tag = varint(), kind = tag & 7, key = tag >> 3;
    if (kind === 0) result.set(key, varint());
    else if (kind === 2) {
      const length = varint();
      result.set(key, buffer.subarray(position, position + length));
      position += length;
    } else if (kind === 1) position += 8;
    else if (kind === 5) position += 4;
    else break;
  }
  return result;
}
const height = buffer => buffer ? fields(buffer).get(1) || 0 : 0;
const upstream = http2.connect('http://127.0.0.1:9267');
upstream.on('error', error => process.stderr.write(error.message + '\n'));
const server = http2.createServer();
server.on('stream', (stream, headers) => {
  const call = {method: headers[':path'].split('/').at(-1), response_bytes: 0};
  calls.push(call);
  stream.on('error', () => {});
  if (call.method === 'SendTransaction' && failNextSubmission) {
    failNextSubmission = false;
    stream.respond({':status': 200, 'content-type': 'application/grpc'}, {waitForTrailers: true});
    stream.on('wantTrailers', () => stream.sendTrailers({
      'grpc-status': '14', 'grpc-message': 'Injected submission outage',
    }));
    stream.resume();
    stream.end();
    return;
  }
  const chunks = [];
  let trailers = {};
  const begun = performance.now();
  const request = upstream.request({...headers, ':authority': '127.0.0.1:9267'});
  stream.on('data', chunk => chunks.push(chunk));
  stream.on('end', () => {
    const buffer = Buffer.concat(chunks);
    if (buffer.length < 5) return;
    const decoded = fields(buffer.subarray(5));
    if (call.method === 'GetBlockRange') {
      call.start = height(decoded.get(1));
      call.end = height(decoded.get(2));
    }
    if (call.method === 'GetTreeState') call.height = decoded.get(1) || 0;
  });
  request.on('response', response => {
    if (!stream.destroyed) stream.respond(response, {waitForTrailers: true});
  });
  stream.on('close', () => {
    if (!request.destroyed) request.close(http2.constants.NGHTTP2_CANCEL);
  });
  request.on('trailers', value => trailers = value);
  request.on('data', chunk => call.response_bytes += chunk.length);
  request.on('end', () => {
    call.elapsed_ms = Math.round(performance.now() - begun);
    process.stdout.write(JSON.stringify(call) + '\n');
  });
  request.on('error', error => {
    call.error = error.message;
    if (!stream.destroyed) stream.close(http2.constants.NGHTTP2_INTERNAL_ERROR);
  });
  stream.on('wantTrailers', () => {
    if (!stream.destroyed) stream.sendTrailers(trailers);
  });
  stream.pipe(request);
  request.pipe(stream);
});
server.listen(9297, '127.0.0.1');
const control = http.createServer((request, response) => {
  if (request.url === '/reset') calls = [];
  if (request.url === '/fail-next-submission') failNextSubmission = true;
  response.setHeader('content-type', 'application/json');
  response.end(JSON.stringify({count: calls.length, calls}));
});
control.listen(9298, '127.0.0.1');
process.on('SIGINT', () => {
  server.close();
  control.close();
  upstream.close();
});

// Node 22+. Deploy behind HTTPS. Only the server holds the Places web-service key.
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';
export function createPlacesServer({ key = process.env.GOOGLE_PLACES_API_KEY, fetchImpl = fetch } = {}) {
  const windows = new Map();
  return createServer(async (req, res) => {
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'no-store');
    const send = (code, data) => { res.writeHead(code); res.end(JSON.stringify(data)); };
    if (req.method !== 'POST' || req.url !== '/search') { send(404, {error: 'Not found'}); return; }
    if (!key) { send(503, {error: 'Search is not configured'}); return; }
    const now = Date.now(), ip = req.socket.remoteAddress;
    for (const [address, record] of windows) { if (record.reset < now) windows.delete(address); }
    const record = windows.get(ip) ?? {count: 0, reset: now + 60000};
    windows.set(ip, record);
    if (++record.count > 20) { send(429, {error: 'Try again later'}); req.resume(); return; }
    try {
      let body = '';
      for await (const chunk of req) {
        body += chunk;
        if (body.length > 4096) { send(413, {error: 'Request too large'}); return; }
      }
      const {textQuery} = JSON.parse(body);
      if (typeof textQuery !== 'string' || !textQuery.trim() || textQuery.length > 300) { send(400, {error: 'Invalid query'}); return; }
      const upstream = await fetchImpl('https://places.googleapis.com/v1/places:searchText', {
        method: 'POST', signal: AbortSignal.timeout(12000),
        headers: {'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'places.displayName,places.formattedAddress,places.location'},
        body: JSON.stringify({textQuery: textQuery.trim(), pageSize: 5}),
      });
      if (!upstream.ok) { send(502, {error: 'Places service unavailable'}); return; }
      const data = await upstream.json();
      send(200, {places: data.places ?? []});
    } catch (error) { send(error instanceof SyntaxError ? 400 : 502, {error: 'Search failed'}); }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  createPlacesServer().listen(Number(process.env.PORT ?? 8080), '127.0.0.1');
}

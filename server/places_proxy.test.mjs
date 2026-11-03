import test from 'node:test';
import assert from 'node:assert/strict';
import {createPlacesServer} from './places_proxy.mjs';

async function withServer(options, run) {
  const server = createPlacesServer(options);
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  try { await run(`http://127.0.0.1:${server.address().port}/search`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}
const post = (url,body) => fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
test('forwards only expected query, masks results, and keeps the key server-side', async () => {
  await withServer({key:'server-only-key',fetchImpl:async (url,options) => {
    assert.equal(url,'https://places.googleapis.com/v1/places:searchText');
    assert.equal(options.headers['X-Goog-Api-Key'],'server-only-key');
    assert.equal(JSON.parse(options.body).textQuery,'Austin');
    assert.ok(options.headers['X-Goog-FieldMask'].includes('places.location'));
    return Response.json({places:[{formattedAddress:'Austin',location:{latitude:30,longitude:-98}}]});
  }}, async url => {
    const response = await post(url,{textQuery:' Austin ',apiKey:'client-input-ignored'});
    assert.equal(response.status,200);
    const text = await response.text(); assert.ok(!text.includes('server-only-key'));
    assert.equal(JSON.parse(text).places[0].formattedAddress,'Austin');
  });
});
test('rejects invalid input and conceals upstream errors', async () => {
  await withServer({key:'key',fetchImpl:async () => new Response('secret upstream error',{status:403})},async url => {
    assert.equal((await post(url,{})).status,400);
    const response = await post(url,{textQuery:'Austin'});
    assert.equal(response.status,502); assert.ok(!(await response.text()).includes('secret'));
    assert.equal((await fetch(url)).status,404);
  });
});
test('limits request rate',async () => {
  await withServer({key:'key',fetchImpl:async () => Response.json({})}, async url => {
    for (let i=0;i<20;i++) assert.equal((await post(url,{textQuery:'Austin'})).status,200);
    assert.equal((await post(url,{textQuery:'Austin'})).status,429);
  });
});

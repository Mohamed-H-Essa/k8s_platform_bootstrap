// Load test for the shortener, through the gateway like a real client.
//
//   k6 run scripts/load.js                         2 minutes at 50 requests/s
//   RATE=100 DURATION=10m k6 run scripts/load.js   heavier / longer (chaos day)
//
// Traffic mix: 85 % redirects, 10 % new links, 5 % stats reads. Redirects are not
// followed (we test the shortener, not example.com). Thresholds are the SLOs.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE || 'http://sho.localtest.me';
const RATE = Number(__ENV.RATE || 50);
const DURATION = __ENV.DURATION || '2m';

export const options = {
  maxRedirects: 0,
  scenarios: {
    traffic: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: 20,
      maxVUs: 200,
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.005', abortOnFail: false }], // availability SLO: 99.5 %
    http_req_duration: ['p(95)<300'], // latency SLO: 95 % under 300 ms
  },
  summaryTrendStats: ['avg', 'med', 'p(95)', 'p(99)', 'max'],
};

function create(i) {
  return http.post(`${BASE}/api/links`, JSON.stringify({ url: `https://example.com/k6/${i}` }), {
    headers: { 'Content-Type': 'application/json' },
    tags: { name: 'create' },
  });
}

// a pool of links to read, made once before the test
export function setup() {
  const codes = [];
  for (let i = 0; i < 50; i++) {
    const res = create(`setup-${i}`);
    if (res.status === 201) codes.push(res.json('code'));
  }
  if (codes.length === 0) throw new Error(`could not create links at ${BASE}`);
  return { codes };
}

export default function (data) {
  const roll = Math.random();
  if (roll < 0.1) {
    const res = create(`${__VU}-${__ITER}`);
    check(res, { 'create → 201': (r) => r.status === 201 });
  } else if (roll < 0.15) {
    const code = data.codes[Math.floor(Math.random() * data.codes.length)];
    const res = http.get(`${BASE}/api/links/${code}`, { tags: { name: 'stats' } });
    check(res, { 'stats → 200': (r) => r.status === 200 });
  } else {
    const code = data.codes[Math.floor(Math.random() * data.codes.length)];
    const res = http.get(`${BASE}/${code}`, { tags: { name: 'redirect' } });
    check(res, { 'redirect → 302': (r) => r.status === 302 });
  }
}

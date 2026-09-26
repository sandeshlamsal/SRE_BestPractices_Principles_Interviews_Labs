// Phase 6 capacity test: the real user journey (same payloads as the demo's Locust load generator).
// browse -> product -> recommendations -> add to cart -> checkout. Stepped ramp to find the "knee".
// Runs IN the cluster (k8s Job) against frontend-proxy, so the laptop port-forward can't be the bottleneck.
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://frontend-proxy.astronomy-shop:8080';
const PRODUCTS = ['0PUK6V6EV0','1YMWWN1N4O','2ZYFJ3GM2N','66VCHSJNUP','6E92ZMYYFZ','9SIQT8TOJO','L9ECAV7KIM','LS4PSXUNUM','OLJCESPC7Z','HQTGWGPNH4'];
const STEP = __ENV.STEP || '90s';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-vus', startVUs: 0,
      stages: [
        { duration: '15s', target: 10 },  { duration: STEP, target: 10 },
        { duration: '15s', target: 25 },  { duration: STEP, target: 25 },
        { duration: '15s', target: 50 },  { duration: STEP, target: 50 },
        { duration: '15s', target: 100 }, { duration: STEP, target: 100 },
        { duration: '15s', target: 0 },
      ],
    },
  },
  // Informational thresholds = the SLO targets (latency is judged per step from Prometheus, not pass/fail here)
  thresholds: { 'http_req_duration{name:checkout}': ['p(99)<1000'], 'http_req_failed': ['rate<0.005'] },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
};

const person = (user) => ({
  userId: user, email: 'larry_sergei@example.com', userCurrency: 'USD',
  address: { streetAddress: '1600 Amphitheatre Parkway', zipCode: '94043', city: 'Mountain View', state: 'CA', country: 'United States' },
  creditCard: { creditCardNumber: '4432-8015-6152-0454', creditCardExpirationMonth: 1, creditCardExpirationYear: 2039, creditCardCvv: 672 },
});

export default function () {
  const user = `k6-${__VU}-${__ITER}-${Date.now()}`;
  const p = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  const json = { headers: { 'Content-Type': 'application/json' } };
  check(http.get(`${BASE}/api/products`, { tags: { name: 'products' } }), { 'products 200': (r) => r.status === 200 });
  check(http.get(`${BASE}/api/products/${p}`, { tags: { name: 'product' } }), { 'product 200': (r) => r.status === 200 });
  http.get(`${BASE}/api/recommendations?productIds=${p}`, { tags: { name: 'recommendations' } });
  check(http.post(`${BASE}/api/cart`, JSON.stringify({ item: { productId: p, quantity: 1 }, userId: user }), { ...json, tags: { name: 'add_to_cart' } }), { 'cart 200': (r) => r.status === 200 });
  check(http.post(`${BASE}/api/checkout`, JSON.stringify(person(user)), { ...json, tags: { name: 'checkout' } }), { 'checkout 200': (r) => r.status === 200 });
  sleep(1);
}

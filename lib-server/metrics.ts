import client from 'prom-client';

// Prevent duplicate metrics registration error during Next.js hot-reloading
// getSingleMetric is synchronous and safe to use as a guard
const register = client.register;

if (!register.getSingleMetric('process_cpu_user_seconds_total')) {
  client.collectDefaultMetrics({ register });
}

// Global registry export
export { register, client };

// HTTP request counter singleton — reuse existing metric if already registered
// to survive Next.js hot-reload without throwing "metric already registered" errors
export const httpRequestsCounter =
  (register.getSingleMetric('http_requests_total') as client.Counter<string>) ||
  new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests handled by this Next.js app',
    labelNames: ['method', 'route', 'status'],
  });

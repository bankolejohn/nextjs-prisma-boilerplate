import client from 'prom-client';

// Prevent duplicate metrics registration error during Next.js hot-reloading
const register = client.register;

if (register.getMetricsAsJSON().length === 0) {
  client.collectDefaultMetrics({ register });
}

// Global registry export
export { register, client };

// Professional HTTP request counter singleton
export const httpRequestsCounter = register.getSingleMetric('http_requests_total') as client.Counter<string> 
  || new client.Counter({
      name: 'http_requests_total',
      help: 'Total number of HTTP requests handled by this Next.js app',
      labelNames: ['method', 'route', 'status'],
    });
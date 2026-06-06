import client from 'prom-client';

const register = client.register;

// Initialise default Node.js metrics (CPU, memory, event loop, GC)
// Guard prevents duplicate registration during Next.js hot-reload
if (!register.getSingleMetric('process_cpu_user_seconds_total')) {
  client.collectDefaultMetrics({ register });
}

export { register, client };

// -----------------------------------------------------------------------
// HTTP request counter — total requests by method, route, status code
// -----------------------------------------------------------------------
export const httpRequestsTotal =
  (register.getSingleMetric('http_requests_total') as client.Counter<string>) ||
  new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests',
    labelNames: ['method', 'route', 'status_code'],
    registers: [register],
  });

// -----------------------------------------------------------------------
// HTTP request duration histogram — measures response latency in seconds
// Buckets cover: 10ms, 50ms, 100ms, 200ms, 500ms, 1s, 2s, 5s, 10s
// -----------------------------------------------------------------------
export const httpRequestDurationSeconds =
  (register.getSingleMetric(
    'http_request_duration_seconds'
  ) as client.Histogram<string>) ||
  new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10],
    registers: [register],
  });

// -----------------------------------------------------------------------
// Helper — wraps an API handler with automatic metrics instrumentation
// Records both request count and latency with accurate status codes
// -----------------------------------------------------------------------
export function withMetrics(
  route: string,
  handler: (req: any, res: any) => Promise<void>
) {
  return async (req: any, res: any) => {
    const startTime = Date.now();
    const method = req.method || 'GET';

    // Intercept res.end to capture the actual status code after the handler runs
    const originalEnd = res.end.bind(res);
    res.end = (...args: any[]) => {
      const statusCode = String(res.statusCode || 200);
      const durationSeconds = (Date.now() - startTime) / 1000;

      httpRequestsTotal.inc({ method, route, status_code: statusCode });
      httpRequestDurationSeconds.observe(
        { method, route, status_code: statusCode },
        durationSeconds
      );

      return originalEnd(...args);
    };

    await handler(req, res);
  };
}

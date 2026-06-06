import { NextApiRequest, NextApiResponse } from 'next';
import ApiError, { handleApiError, handleSsrError } from 'lib-server/error';
import nc from 'next-connect';
import { ServerResponse } from 'http';
import { NextReq } from 'types';
import { httpRequestsTotal, httpRequestDurationSeconds } from 'lib-server/metrics';

export const ncOptions = {
  onError(error: Error, req: NextApiRequest, res: NextApiResponse) {
    handleApiError(error, req, res);
  },
  onNoMatch(req: NextApiRequest, res: NextApiResponse) {
    const error = new ApiError(`Method '${req.method}' not allowed`, 405);
    handleApiError(error, req, res);
  },
};

/**
 * Global metrics middleware — records request count and latency for every
 * API route that uses apiHandler(). Intercepts res.end to capture the
 * actual status code after the handler finishes, including error responses.
 */
const metricsMiddleware = (
  req: NextApiRequest,
  res: NextApiResponse,
  next: () => void
) => {
  const startTime = Date.now();
  const method = req.method || 'GET';
  // Normalise dynamic segments: /api/posts/123 → /api/posts/[id]
  const route = req.url?.replace(/\/\d+/g, '/[id]').split('?')[0] || 'unknown';

  const originalEnd = res.end.bind(res);
  (res as any).end = (...args: any[]) => {
    const statusCode = String(res.statusCode || 200);
    const durationSeconds = (Date.now() - startTime) / 1000;

    try {
      httpRequestsTotal.inc({ method, route, status_code: statusCode });
      httpRequestDurationSeconds.observe(
        { method, route, status_code: statusCode },
        durationSeconds
      );
    } catch (_err) {
      // Never let metrics instrumentation break a response
    }

    return originalEnd(...args);
  };

  next();
};

/**
 * Single instance must be default exported from each API route file.
 * Automatically instruments all routes with Prometheus metrics.
 */
export const apiHandler = () => {
  return nc<NextApiRequest, NextApiResponse>(ncOptions).use(metricsMiddleware);
};

// ---------- getServerSideProps error handler

export type NextApiRequestWithResult<T> = NextApiRequest & { result: T };

/* eslint-disable @typescript-eslint/no-unnecessary-type-constraint */
export const ssrNcHandler = async <T extends unknown>(
  req: NextReq,
  res: ServerResponse,
  callback: () => Promise<T>
) => {
  const base = () => {
    const handler = nc<NextApiRequestWithResult<T>, NextApiResponse>(ncOptions).use(
      async (req, res, next) => {
        req.result = await callback();
        next();
      }
    );

    return handler;
  };

  const _req = req as NextApiRequestWithResult<T>;
  const _res = res as NextApiResponse;

  try {
    await base().run(_req, _res);

    return _req.result as T;
  } catch (error) {
    handleSsrError(error, _req, _res);
    return null;
  }
};

export default nc;

// ---------- getServerSideProps error handler

export type NextApiRequestWithResult<T> = NextApiRequest & { result: T };

/* eslint-disable @typescript-eslint/no-unnecessary-type-constraint */
export const ssrNcHandler = async <T extends unknown>(
  req: NextReq,
  res: ServerResponse,
  callback: () => Promise<T>
) => {
  const base = () => {
    const handler = nc<NextApiRequestWithResult<T>, NextApiResponse>(ncOptions).use(
      async (req, res, next) => {
        req.result = await callback();
        next();
      }
    );

    return handler;
  };

  const _req = req as NextApiRequestWithResult<T>;
  const _res = res as NextApiResponse;

  try {
    await base().run(_req, _res);

    return _req.result as T;
  } catch (error) {
    handleSsrError(error, _req, _res);
    return null;
  }
};

export default nc;

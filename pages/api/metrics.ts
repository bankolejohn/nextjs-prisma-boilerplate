// import { NextApiRequest, NextApiResponse } from 'next';
// import client from 'prom-client';

// // Initialize default metrics (CPU, Memory usage, Event Loop lag)
// const collectDefaultMetrics = client.collectDefaultMetrics;
// collectDefaultMetrics({ register: client.register });

// export default async function handler(req: NextApiRequest, res: NextApiResponse) {
//   res.setHeader('Content-Type', client.register.contentType);
//   res.send(await client.register.metrics());
// }


// import { NextApiRequest, NextApiResponse } from 'next';
// import client from 'prom-client';

// // Next.js creates isolated scopes. We must ensure we don't clear or 
// // re-register default metrics if they already exist globally.
// const register = client.register;

// if (register.getMetricsAsJSON().length === 0) {
//   client.collectDefaultMetrics({ register });
// }

// export default async function handler(req: NextApiRequest, res: NextApiResponse) {
//   try {
//     res.setHeader('Content-Type', register.contentType);
//     const metrics = await register.metrics();
//     res.status(200).send(metrics);
//   } catch (error) {
//     // This will print the actual underlying crash log to your nextjs terminal
//     console.error("Prometheus Metrics Error:", error);
//     res.status(500).json({ error: 'Internal Server Error reading metrics' });
//   }
// }



import { NextApiRequest, NextApiResponse } from 'next';
import client from 'prom-client';

// Clear the registry to avoid memory leaks or duplicate errors on hot-reloads
client.register.clear();

// Force fresh initialization
const collectDefaultMetrics = client.collectDefaultMetrics;
collectDefaultMetrics({ register: client.register });

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  try {
    // Set headers to prevent ANY browser or proxy caching
    res.setHeader('Content-Type', client.register.contentType);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    
    const metrics = await client.register.metrics();
    res.status(200).send(metrics);
  } catch (error) {
    console.error("Prometheus Metrics Loop Error:", error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
}
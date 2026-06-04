import { NextApiRequest, NextApiResponse } from 'next';
import { register } from 'lib-server/metrics';

export default async function handler(req: NextApiRequest, res: NextApiResponse) {
  try {
    res.setHeader('Content-Type', register.contentType);
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    
    const metrics = await register.metrics();
    res.status(200).send(metrics);
  } catch (error) {
    res.status(500).json({ error: 'Internal Server Error' });
  }
}
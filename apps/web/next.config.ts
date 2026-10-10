import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  output: 'standalone',
  outputFileTracingRoot: __dirname,
};

export default nextConfig;

import type { NextConfig } from 'next';

const nextConfig: NextConfig = {
  poweredByHeader: false,
  output: 'standalone',
  outputFileTracingRoot: __dirname,
  async rewrites() {
    if (process.env.NODE_ENV !== 'development') return [];

    const shopApiOrigin =
      process.env.SHOP_API_INTERNAL_URL ?? 'http://127.0.0.1:4000';
    return [
      {
        source: '/api/:path*',
        destination: `${shopApiOrigin.replace(/\/+$/, '')}/:path*`,
      },
    ];
  },
};

export default nextConfig;

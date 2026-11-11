import type { NextConfig } from "next";

const apiProxy = process.env.OPEN5G_API_PROXY?.replace(/\/$/, "");

const nextConfig: NextConfig = {
  reactStrictMode: true,
  async rewrites() {
    if (!apiProxy) {
      return [];
    }
    return [
      { source: "/api/:path*", destination: `${apiProxy}/api/:path*` },
      { source: "/emulator/:path*", destination: `${apiProxy}/emulator/:path*` },
    ];
  },
};

export default nextConfig;

import type { NextConfig } from "next";

const apiProxy = process.env.OPEN5G_API_PROXY?.replace(/\/$/, "");
const screenOrigin = process.env.OPEN5G_EMULATOR_SCREEN_ORIGIN?.replace(/\/$/, "");

const nextConfig: NextConfig = {
  reactStrictMode: true,
  async rewrites() {
    if (!apiProxy) {
      return [];
    }
    return [{ source: "/api/:path*", destination: `${apiProxy}/api/:path*` }];
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [{ key: "Content-Security-Policy", value: `frame-src ${screenOrigin || "'none'"}` }],
      },
    ];
  },
};

export default nextConfig;

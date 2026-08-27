import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Workspace packages ship raw TS/TSX and are compiled by Next.
  transpilePackages: ["@clipify/ui", "@clipify/types", "@clipify/video-schema"],
};

export default nextConfig;

import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // firebase-admin (via jwks-rsa/jose) rompe l'interop ESM/CJS se bundlato da
  // Next/Turbopack sul runtime serverless (ERR_REQUIRE_ESM). Lo teniamo esterno
  // così viene richiesto a runtime da node_modules senza ri-bundling.
  serverExternalPackages: ["firebase-admin", "xlsx"],
};

export default nextConfig;

import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { SESSION_COOKIE } from "@/lib/config";

// Next 16: il vecchio `middleware.ts` è stato rinominato in `proxy.ts`.
// Difesa in profondità (edge): se manca il session cookie, reindirizza al login
// prima di eseguire il server component. La verifica autorevole del cookie
// (firma + allowlist) avviene comunque in dashboard/layout.tsx via Admin SDK.
export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname.startsWith("/dashboard") && !request.cookies.has(SESSION_COOKIE)) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/dashboard/:path*"],
};

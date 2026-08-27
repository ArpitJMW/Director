import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { TOKEN_COOKIE } from "@/lib/config";

// Gate the authenticated app. A missing JWT cookie -> redirect to /login.
// (Route handlers still verify the token with Rails; this is just UX.)
const PROTECTED = [/^\/dashboard/, /^\/projects/];

export function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const needsAuth = PROTECTED.some((re) => re.test(pathname));
  if (!needsAuth) return NextResponse.next();

  const hasToken = request.cookies.has(TOKEN_COOKIE);
  if (hasToken) return NextResponse.next();

  const url = request.nextUrl.clone();
  url.pathname = "/login";
  url.searchParams.set("next", pathname);
  return NextResponse.redirect(url);
}

export const config = {
  matcher: ["/dashboard/:path*", "/projects/:path*"],
};

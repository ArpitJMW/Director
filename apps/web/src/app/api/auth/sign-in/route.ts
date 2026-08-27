import { NextResponse } from "next/server";
import { API_URL, TOKEN_COOKIE, TOKEN_MAX_AGE } from "@/lib/config";

// POST /api/auth/sign-in  { email, password }
// Proxies to Rails, moves the returned JWT into an httpOnly cookie.
export async function POST(request: Request) {
  const { email, password } = (await request.json()) as { email?: string; password?: string };

  const railsRes = await fetch(`${API_URL}/api/v1/auth/sign_in`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ user: { email, password } }),
    cache: "no-store",
  });

  if (!railsRes.ok) {
    return NextResponse.json({ error: "invalid_credentials" }, { status: 401 });
  }

  const token = railsRes.headers.get("Authorization")?.replace(/^Bearer /, "");
  const body = await railsRes.json();

  const res = NextResponse.json(body);
  if (token) {
    res.cookies.set(TOKEN_COOKIE, token, {
      httpOnly: true,
      sameSite: "lax",
      secure: process.env.NODE_ENV === "production",
      path: "/",
      maxAge: TOKEN_MAX_AGE,
    });
  }
  return res;
}

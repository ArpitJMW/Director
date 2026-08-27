import { NextResponse } from "next/server";
import { API_URL, TOKEN_COOKIE, TOKEN_MAX_AGE } from "@/lib/config";

// POST /api/auth/sign-up  { name, email, password }
export async function POST(request: Request) {
  const { name, email, password } = (await request.json()) as {
    name?: string;
    email?: string;
    password?: string;
  };

  const railsRes = await fetch(`${API_URL}/api/v1/auth/sign_up`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({ user: { name, email, password } }),
    cache: "no-store",
  });

  const body = await railsRes.json();
  if (!railsRes.ok) {
    return NextResponse.json(body, { status: railsRes.status });
  }

  const token = railsRes.headers.get("Authorization")?.replace(/^Bearer /, "");
  const res = NextResponse.json(body, { status: 201 });
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

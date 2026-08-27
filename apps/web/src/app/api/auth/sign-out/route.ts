import { NextResponse } from "next/server";
import { TOKEN_COOKIE } from "@/lib/config";
import { railsFetch } from "@/lib/server/rails";

// POST /api/auth/sign-out — revoke the JWT server-side, then clear the cookie.
export async function POST() {
  await railsFetch("/api/v1/auth/sign_out", { method: "DELETE" }).catch(() => null);

  const res = NextResponse.json({ ok: true });
  res.cookies.delete(TOKEN_COOKIE);
  return res;
}

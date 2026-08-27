import { NextResponse } from "next/server";
import { currentUser } from "@/lib/server/rails";

// GET /api/auth/session — { user } or { user: null }
export async function GET() {
  const user = await currentUser();
  return NextResponse.json({ user });
}

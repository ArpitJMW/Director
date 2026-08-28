import { NextResponse } from "next/server";
import { railsFetch } from "@/lib/server/rails";

// Transparent authenticated proxy: /api/v1/<anything> -> Rails /api/v1/<anything>
// with the JWT attached from the httpOnly cookie. The token never reaches the
// browser. Passes bodies through as bytes so binary responses (images, audio,
// video from /api/v1/files) are not corrupted.
async function proxy(request: Request, path: string[]): Promise<Response> {
  const url = new URL(request.url);
  const target = `/api/v1/${path.join("/")}${url.search}`;

  const method = request.method;
  const body =
    method === "GET" || method === "HEAD" ? undefined : await request.arrayBuffer();

  const railsRes = await railsFetch(target, {
    method,
    body: body && body.byteLength > 0 ? body : undefined,
  });

  const headers = new Headers();
  for (const name of [
    "Content-Type",
    "Content-Disposition",
    "Cache-Control",
    "X-Total-Count",
    "X-Page",
    "X-Total-Pages",
  ]) {
    const value = railsRes.headers.get(name);
    if (value !== null) headers.set(name, value);
  }
  if (!headers.has("Content-Type")) headers.set("Content-Type", "application/json");

  const payload = await railsRes.arrayBuffer();
  return new NextResponse(payload.byteLength ? payload : null, {
    status: railsRes.status,
    headers,
  });
}

type Ctx = { params: Promise<{ path: string[] }> };

export async function GET(request: Request, { params }: Ctx) {
  return proxy(request, (await params).path);
}
export async function POST(request: Request, { params }: Ctx) {
  return proxy(request, (await params).path);
}
export async function PATCH(request: Request, { params }: Ctx) {
  return proxy(request, (await params).path);
}
export async function PUT(request: Request, { params }: Ctx) {
  return proxy(request, (await params).path);
}
export async function DELETE(request: Request, { params }: Ctx) {
  return proxy(request, (await params).path);
}

import { NextResponse } from "next/server";
import { railsFetch } from "@/lib/server/rails";

// Transparent authenticated proxy: /api/v1/<anything> -> Rails /api/v1/<anything>
// with the JWT attached from the httpOnly cookie. The token never reaches the
// browser.
async function proxy(request: Request, path: string[]): Promise<Response> {
  const url = new URL(request.url);
  const target = `/api/v1/${path.join("/")}${url.search}`;

  const method = request.method;
  const body = method === "GET" || method === "HEAD" ? undefined : await request.text();

  const railsRes = await railsFetch(target, { method, body });

  const text = await railsRes.text();
  return new NextResponse(text || null, {
    status: railsRes.status,
    headers: {
      "Content-Type": railsRes.headers.get("Content-Type") ?? "application/json",
      // Surface pagination headers to the client.
      ...pick(railsRes.headers, ["X-Total-Count", "X-Page", "X-Total-Pages"]),
    },
  });
}

function pick(headers: Headers, names: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const name of names) {
    const value = headers.get(name);
    if (value !== null) out[name] = value;
  }
  return out;
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

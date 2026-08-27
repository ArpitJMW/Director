"use client";

import Link from "next/link";
import { useState } from "react";
import { Button, Card, CardContent, Input, Label } from "@clipify/ui";
import { useSignIn } from "@/lib/api/auth";

export default function LoginPage() {
  const signIn = useSignIn();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  return (
    <Card>
      <CardContent className="pt-6">
        <h1 className="mb-1 text-xl font-semibold">Log in</h1>
        <p className="mb-6 text-sm text-muted">Welcome back to Clipify.</p>

        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            signIn.mutate({ email, password });
          }}
        >
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          {signIn.isError && (
            <p className="text-sm text-danger">{signIn.error.message}</p>
          )}

          <Button type="submit" disabled={signIn.isPending}>
            {signIn.isPending ? "Signing in…" : "Log in"}
          </Button>
        </form>

        <p className="mt-6 text-center text-sm text-muted">
          No account?{" "}
          <Link href="/signup" className="font-medium text-accent">
            Sign up
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}

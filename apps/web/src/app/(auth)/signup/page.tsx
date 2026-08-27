"use client";

import Link from "next/link";
import { useState } from "react";
import { Button, Card, CardContent, Input, Label } from "@clipify/ui";
import { useSignUp } from "@/lib/api/auth";

export default function SignupPage() {
  const signUp = useSignUp();
  const [form, setForm] = useState({ name: "", email: "", password: "" });

  const set = (key: keyof typeof form) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm((f) => ({ ...f, [key]: e.target.value }));

  return (
    <Card>
      <CardContent className="pt-6">
        <h1 className="mb-1 text-xl font-semibold">Create your account</h1>
        <p className="mb-6 text-sm text-muted">Start making videos with Clipify.</p>

        <form
          className="flex flex-col gap-4"
          onSubmit={(e) => {
            e.preventDefault();
            signUp.mutate(form);
          }}
        >
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="name">Name</Label>
            <Input id="name" required value={form.name} onChange={set("name")} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              autoComplete="email"
              required
              value={form.email}
              onChange={set("email")}
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              type="password"
              autoComplete="new-password"
              minLength={8}
              required
              value={form.password}
              onChange={set("password")}
            />
          </div>

          {signUp.isError && <p className="text-sm text-danger">{signUp.error.message}</p>}

          <Button type="submit" disabled={signUp.isPending}>
            {signUp.isPending ? "Creating account…" : "Sign up"}
          </Button>
        </form>

        <p className="mt-6 text-center text-sm text-muted">
          Already have an account?{" "}
          <Link href="/login" className="font-medium text-accent">
            Log in
          </Link>
        </p>
      </CardContent>
    </Card>
  );
}

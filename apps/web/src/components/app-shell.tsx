"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { Button, cn } from "@clipify/ui";
import { useSession, useSignOut } from "@/lib/api/auth";

const NAV = [
  { href: "/dashboard", label: "Projects" },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { data: user } = useSession();
  const signOut = useSignOut();

  return (
    <div className="flex flex-1">
      <aside className="hidden w-56 shrink-0 flex-col border-r border-border bg-surface-1 p-4 sm:flex">
        <Link href="/dashboard" className="mb-6 px-2 text-lg font-semibold">
          Clipify
        </Link>
        <nav className="flex flex-col gap-1">
          {NAV.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "rounded-md px-3 py-2 text-sm font-medium",
                pathname.startsWith(item.href)
                  ? "bg-surface-2 text-foreground"
                  : "text-muted hover:bg-surface-2 hover:text-foreground",
              )}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </aside>

      <div className="flex flex-1 flex-col">
        <header className="flex h-14 items-center justify-between border-b border-border px-6">
          <span className="text-sm text-muted sm:hidden">Clipify</span>
          <div className="ml-auto flex items-center gap-3">
            {user && <span className="text-sm text-muted">{user.name}</span>}
            <Button
              variant="outline"
              size="sm"
              onClick={() => signOut.mutate()}
              disabled={signOut.isPending}
            >
              Sign out
            </Button>
          </div>
        </header>
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}

import { redirect } from "next/navigation";
import type { ReactNode } from "react";
import { currentUser } from "@/lib/server/rails";
import { AppShell } from "@/components/app-shell";

export default async function AppLayout({ children }: { children: ReactNode }) {
  const user = await currentUser();
  if (!user) redirect("/login");

  return <AppShell>{children}</AppShell>;
}

import Link from "next/link";
import type { ReactNode } from "react";

export default function AuthLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-16">
      <Link href="/" className="mb-8 text-lg font-semibold">
        Clipify
      </Link>
      <div className="w-full max-w-sm">{children}</div>
    </div>
  );
}

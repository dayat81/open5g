import type { Metadata } from "next";
import type { ReactNode } from "react";
import "../styles/tokens.css";
import "../styles/components.css";
import "../styles/scaffold.css";

export const metadata: Metadata = {
  title: "Dashboard lab 5G",
  description: "Scaffold Overview dan editor profil IMSI. Mode demo bukan bukti lab.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="id">
      <body>{children}</body>
    </html>
  );
}

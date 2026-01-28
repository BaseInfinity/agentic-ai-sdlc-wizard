export const metadata = {
  title: 'E2E Test App',
  description: 'Next.js TypeScript fixture',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

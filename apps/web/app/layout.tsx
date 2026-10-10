import type { Metadata } from 'next';
import './globals.css';
import { StoreFooter } from './store-footer';
import { StoreHeader } from './store-header';
import { WhatsAppButton } from './whatsapp-button';

export const metadata: Metadata = {
  title: 'Shop online',
  description: 'Browse products from your local ShopSmart store.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <StoreHeader />
        {children}
        <StoreFooter />
        <WhatsAppButton />
      </body>
    </html>
  );
}

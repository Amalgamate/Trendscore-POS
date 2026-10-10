import type { Metadata } from 'next';
import './globals.css';
import { StoreFooter } from './store-footer';
import { StoreHeader } from './store-header';
import { WhatsAppButton } from './whatsapp-button';
import { StoreCartProvider } from './store-cart';

export const metadata: Metadata = {
  title: 'Gutagala Web Shop | ShopSmart',
  description:
    'Browse products published by Gutagala. Online ordering is not enabled yet.',
  icons: {
    icon: '/icon.svg',
    apple: '/apple-icon.png',
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <StoreCartProvider>
          <StoreHeader />
          {children}
          <StoreFooter />
          <WhatsAppButton />
        </StoreCartProvider>
      </body>
    </html>
  );
}

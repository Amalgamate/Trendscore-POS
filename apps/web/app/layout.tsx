import type { Metadata } from 'next';
import './globals.css';
import { StoreFooter } from './store-footer';
import { StoreHeader } from './store-header';
import { WhatsAppButton } from './whatsapp-button';
import { StoreCartProvider } from './store-cart';

export const metadata: Metadata = {
  title: 'ShopSmart Storefront Preview',
  description:
    'Explore a sample ShopSmart storefront. Sample products and prices are illustrative; ordering is not enabled.',
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

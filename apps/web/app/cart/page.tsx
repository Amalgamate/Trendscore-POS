import Link from 'next/link';

export default function CartPage() {
  return (
    <main className="simple-page">
      <p className="eyebrow">YOUR ORDER</p>
      <h1>Your bag</h1>
      <div className="empty-catalog compact-empty">
        <h2>Your bag is empty</h2>
        <p>Published products from the shop will be available to add here.</p>
        <Link className="button button-primary" href="/">
          Continue shopping
        </Link>
      </div>
      <p className="integration-note">
        Cart persistence and live stock checks connect after the public catalog
        API is available.
      </p>
    </main>
  );
}

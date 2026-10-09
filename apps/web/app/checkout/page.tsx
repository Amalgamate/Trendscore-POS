import Link from 'next/link';

export default function CheckoutPage() {
  return (
    <main className="simple-page">
      <p className="eyebrow">SECURE CHECKOUT</p>
      <h1>Checkout</h1>
      <div className="checkout-scaffold">
        <h2>Checkout setup is required</h2>
        <p>
          This shop has not connected online ordering and verified M-Pesa
          payments yet. No order or payment will be submitted from this preview.
        </p>
        <Link className="button button-secondary" href="/cart">
          Return to your bag
        </Link>
      </div>
      <ol className="checkout-steps">
        <li>Delivery or pickup details</li>
        <li>Order review and stock reservation</li>
        <li>M-Pesa prompt and verified payment result</li>
        <li>Order confirmation and status tracking</li>
      </ol>
    </main>
  );
}
